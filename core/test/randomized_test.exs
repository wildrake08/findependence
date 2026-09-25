defmodule Findependence.RandomizedTest do
  @moduledoc """
  Seeded random operation sequences. After every step, the item state is rebuilt independently
  by replaying the ledger, and REQ-101..106 are checked against that rebuild, not against the
  library's own view.
  """
  use ExUnit.Case, async: true

  alias Findependence.{Household, Ledger, View}

  @members [:a, :b, :c, :d]
  @actors [:x | @members]
  @items [:i1, :i2, :i3]
  @seeds 1..500
  @steps 60

  test "REQ-101..106 hold after every operation of #{Enum.count(@seeds)} seeded sequences" do
    counts =
      for seed <- @seeds, reduce: %{} do
        acc ->
          :rand.seed(:exsss, {seed, seed * 7, seed * 13})
          run(Household.new(@members), @steps, seed, acc)
      end

    # Guard against a vacuous run: every kind of change, and joint consent, must actually happen.
    for kind <- [:created, :owners_changed, :granted, :grant_revoked, :joint_consent],
        do:
          assert(
            Map.get(counts, kind, 0) >= 100,
            "only #{Map.get(counts, kind, 0)} #{kind} in #{inspect(counts)}"
          )
  end

  defp run(_h, 0, _seed, acc), do: acc

  defp run(h, n, seed, acc) do
    h2 =
      case step(h) do
        {:ok, h2} -> h2
        {:ok, h2, _proposal} -> h2
        {:error, _} -> h
      end

    check!(h, h2, seed)
    run(h2, n - 1, seed, count(h, h2, acc))
  end

  # Counts ledger events added by the step; :joint_consent is a change consented by several owners.
  defp count(h, h2, acc) do
    new =
      for {item, entries} <- h2.ledger,
          e <- Enum.drop(entries, length(Map.get(h.ledger, item, []))),
          do: e

    kinds = Enum.map(new, & &1.event) ++ for(e <- new, length(e.by) > 1, do: :joint_consent)
    Enum.reduce(kinds, acc, fn k, a -> Map.update(a, k, 1, &(&1 + 1)) end)
  end

  # Mostly act as a real owner, so joint-ownership paths are exercised; 30% random actors
  # keep the refusal paths covered.
  defp step(h) do
    item = Enum.random(@items)
    actor = pick_actor(h, item)

    case :rand.uniform(7) do
      1 ->
        Household.add_item(h, actor, item, %{amount: :rand.uniform(100) - 50})

      2 ->
        Household.propose_owners(h, actor, item, Enum.take_random(@actors, :rand.uniform(3) - 1))

      3 ->
        Household.propose_grant(h, actor, item, Enum.random(@actors))

      n when n in [4, 5] ->
        Household.revoke_grant(h, actor, item, revoke_target(h, item))

      _ ->
        consent_random(h, actor)
    end
  end

  defp revoke_target(h, item) do
    case h.items[item] do
      %{grantees: g} ->
        if MapSet.size(g) > 0 and :rand.uniform(10) <= 7,
          do: Enum.random(MapSet.to_list(g)),
          else: Enum.random(@actors)

      nil ->
        Enum.random(@actors)
    end
  end

  defp pick_actor(h, item) do
    case h.items[item] do
      %{owners: owners} ->
        if :rand.uniform(10) <= 7,
          do: Enum.random(MapSet.to_list(owners)),
          else: Enum.random(@actors)

      nil ->
        Enum.random(@actors)
    end
  end

  defp consent_random(h, actor) do
    case Map.keys(h.proposals) do
      [] ->
        {:error, :none}

      ids ->
        id = Enum.random(ids)
        owners = MapSet.to_list(h.items[h.proposals[id].item_id].owners)
        who = if :rand.uniform(10) <= 7, do: Enum.random(owners), else: actor
        Household.consent(h, who, id)
    end
  end

  defp check!(before, h, seed) do
    replayed = replay(h)

    for item <- Map.keys(h.items) do
      {owners, grantees} = replayed[item]
      # The ledger fully explains the current ownership and visibility (REQ-105).
      assert {owners, grantees} == {h.items[item].owners, h.items[item].grantees},
             "seed #{seed}: ledger/state mismatch on #{item}"

      # REQ-101
      assert MapSet.size(owners) > 0 and MapSet.subset?(owners, MapSet.new(@members)),
             "seed #{seed}: bad owner set"

      for m <- @actors do
        # REQ-102
        assert View.visible?(h, m, item) == (m in owners or m in grantees),
               "seed #{seed}: visibility of #{item} to #{m}"

        # REQ-105: current owners and nobody else can read the ledger
        assert match?({:ok, _}, Ledger.read(h, m, item)) == m in owners,
               "seed #{seed}: ledger access"
      end
    end

    # REQ-106
    for m <- @actors do
      expected =
        for {item, {o, g}} <- replayed, m in o or m in g, reduce: 0 do
          acc -> acc + h.items[item].attrs.amount
        end

      assert View.sum(h, m, :amount) == expected, "seed #{seed}: aggregate leak for #{m}"
    end

    # REQ-105: append-only, so the old ledger is a prefix of the new one
    for {item, old} <- before.ledger,
        do:
          assert(Enum.take(h.ledger[item], length(old)) == old, "seed #{seed}: ledger rewritten")

    # REQ-103/104: every grant and owner change was consented to by every owner at that moment
    for {item, entries} <- h.ledger do
      Enum.reduce(entries, MapSet.new(), fn e, owners ->
        by = MapSet.new(e.by)

        case e.event do
          :created ->
            MapSet.new(e.details.owners)

          :owners_changed ->
            assert MapSet.subset?(owners, by),
                   "seed #{seed}: owner change on #{item} without all owners"

            MapSet.new(e.details.owners)

          :granted ->
            assert MapSet.subset?(owners, by), "seed #{seed}: grant on #{item} without all owners"
            owners

          :grant_revoked ->
            assert MapSet.size(by) == 1 and MapSet.subset?(by, owners),
                   "seed #{seed}: revocation by non-owner"

            owners
        end
      end)
    end
  end

  # Rebuilds owners and grantees for every item from its ledger alone.
  defp replay(h) do
    Map.new(h.ledger, fn {item, entries} ->
      state =
        Enum.reduce(entries, {MapSet.new(), MapSet.new()}, fn e, {o, g} ->
          case e.event do
            :created ->
              {MapSet.new(e.details.owners), g}

            :owners_changed ->
              (fn new -> {new, MapSet.difference(g, new)} end).(MapSet.new(e.details.owners))

            :granted ->
              {o, MapSet.put(g, e.details.grantee)}

            :grant_revoked ->
              {o, MapSet.delete(g, e.details.grantee)}
          end
        end)

      {item, state}
    end)
  end
end
