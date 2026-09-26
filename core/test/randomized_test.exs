defmodule Findependence.RandomizedTest do
  @moduledoc """
  Seeded random operation sequences. After every step, the item state is rebuilt independently
  by replaying the ledger, and REQ-101..110 are checked against that rebuild, not against the
  library's own view.
  """
  use ExUnit.Case, async: true

  alias Findependence.{Exit, Household, Ledger, View}

  @members [:a, :b, :c, :d]
  @actors [:x | @members]
  @items [:i1, :i2, :i3]
  @seeds 1..1000
  @steps 80

  test "REQ-101..110 hold after every operation of #{Enum.count(@seeds)} seeded sequences" do
    counts =
      for seed <- @seeds, reduce: %{} do
        acc ->
          :rand.seed(:exsss, {seed, seed * 7, seed * 13})
          run(Household.new(@members), @steps, seed, acc)
      end

    # Guard against a vacuous run: every kind of change, and joint consent, must actually happen.
    for kind <- [
          :created,
          :owners_changed,
          :granted,
          :grant_revoked,
          :joint_consent,
          :owner_relinquished,
          :deleted,
          :departed,
          :grantee_departed
        ],
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
  defp total_deletions(h), do: h.deletions |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

  defp count(h, h2, acc) do
    new =
      for {item, entries} <- h2.ledger,
          e <- Enum.drop(entries, length(Map.get(h.ledger, item, []))),
          do: e

    deleted = List.duplicate(:deleted, total_deletions(h2) - total_deletions(h))
    departed = List.duplicate(:departed, MapSet.size(h.members) - MapSet.size(h2.members))

    kinds =
      Enum.map(new, & &1.event) ++
        for(e <- new, length(e.by) > 1, do: :joint_consent) ++ deleted ++ departed

    Enum.reduce(kinds, acc, fn k, a -> Map.update(a, k, 1, &(&1 + 1)) end)
  end

  # Mostly act as a real owner, so joint-ownership paths are exercised; 30% random actors
  # keep the refusal paths covered.
  defp step(h) do
    item = Enum.random(@items)
    actor = pick_actor(h, item)

    case :rand.uniform(24) do
      n when n in 1..3 ->
        Household.add_item(h, actor, item, %{amount: :rand.uniform(100) - 50})

      n when n in 4..7 ->
        Household.propose_owners(h, actor, item, Enum.take_random(@actors, :rand.uniform(3) - 1))

      n when n in 8..10 ->
        Household.propose_grant(h, actor, item, Enum.random(@actors))

      n when n in 11..13 ->
        Household.revoke_grant(h, actor, item, revoke_target(h, item))

      n when n in 14..19 ->
        consent_random(h, actor)

      n when n in 20..22 ->
        Household.relinquish(h, actor, item)

      23 ->
        Exit.delete(h, actor, item)

      24 ->
        Exit.leave(h, leaver(h))
    end
  end

  # Mostly a member who owns nothing, so departures actually happen.
  defp leaver(h) do
    free = for m <- h.members, not Enum.any?(h.items, fn {_, i} -> m in i.owners end), do: m
    if free != [] and :rand.uniform(10) <= 2, do: Enum.random(free), else: Enum.random(@actors)
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

    # Deleted items leave no ledger behind (REQ-108): ledger and items cover the same ids.
    assert Enum.sort(Map.keys(replayed)) == Enum.sort(Map.keys(h.items)),
           "seed #{seed}: ledger/items mismatch"

    for item <- Map.keys(h.items) do
      {owners, grantees} = replayed[item]
      # The ledger fully explains the current ownership and visibility (REQ-105).
      assert {owners, grantees} == {h.items[item].owners, h.items[item].grantees},
             "seed #{seed}: ledger/state mismatch on #{item}"

      # REQ-101
      assert MapSet.size(owners) > 0 and MapSet.subset?(owners, h.members),
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

    # REQ-105: append-only, so the old ledger is a prefix of the new one (unless the item was deleted)
    for {item, old} <- before.ledger,
        Map.has_key?(h.ledger, item),
        do:
          assert(Enum.take(h.ledger[item], length(old)) == old, "seed #{seed}: ledger rewritten")

    exit_checks!(before, h, seed)

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

          :grantee_departed ->
            owners

          :owner_relinquished ->
            # REQ-107: only oneself, alone, and never the last owner
            assert MapSet.equal?(by, MapSet.new([e.details.owner])) and e.details.owner in owners and
                     MapSet.size(owners) > 1,
                   "seed #{seed}: illegitimate relinquishment on #{item}"

            MapSet.delete(owners, e.details.owner)
        end
      end)
    end
  end

  defp exit_checks!(before, h, seed) do
    # REQ-108: an item disappears only by deletion by its sole owner, who gets a record
    for {item, old} <- before.items, not Map.has_key?(h.items, item) do
      [owner] = MapSet.to_list(old.owners)

      assert List.last(Ledger.deletions(h, owner)).item_id == item,
             "seed #{seed}: #{item} vanished without a deletion record"
    end

    # REQ-109: export is exactly the owned items, each with its ledger
    for m <- @actors do
      %{items: exported} = Exit.export(h, m)
      owned = for {id, i} <- h.items, m in i.owners, do: id

      assert Enum.sort(Enum.map(exported, & &1.id)) == Enum.sort(owned),
             "seed #{seed}: export of #{m}"

      assert Enum.all?(exported, &(&1.ledger == h.ledger[&1.id])),
             "seed #{seed}: export ledger of #{m}"
    end

    # REQ-110: a departed member owned nothing, holds no grants, and is named by no proposal
    for m <- MapSet.difference(before.members, h.members) do
      refute Enum.any?(before.items, fn {_, i} -> m in i.owners end),
             "seed #{seed}: #{m} left while owning"

      refute Enum.any?(h.items, fn {_, i} -> m in i.grantees end),
             "seed #{seed}: #{m} kept a grant"

      refute Enum.any?(h.proposals, fn {_, p} ->
               p.change == {:grant, m} or
                 (match?({:owners, _}, p.change) and m in elem(p.change, 1))
             end),
             "seed #{seed}: proposal still names #{m}"
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

            :grantee_departed ->
              {o, MapSet.delete(g, e.details.grantee)}

            :owner_relinquished ->
              {MapSet.delete(o, e.details.owner), g}
          end
        end)

      {item, state}
    end)
  end
end
