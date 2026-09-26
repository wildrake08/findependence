defmodule FindependenceApp.ModelTest do
  @moduledoc """
  Seeded random operations run twice: once on a trusted, fully in-memory core Household (the
  model), and once through encrypted Sessions that save and reopen the vault. After every step:

  - the operation succeeds in the session exactly when it succeeds in the model (a session is
    never blocked for lack of a key it should have);
  - each member's decrypted view equals the model's view for that member: visible items, their
    own ledgers, pending proposals, links, distribution, and export;
  - no member can open an item key sealed to anyone else (REQ-119) or any ledger entry of an
    item they do not own (REQ-120).
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.{Crypto, Session, Vault}
  alias Findependence.{Alignment, Exit, Household, Ledger, View}

  @members ["a", "b", "c"]
  @items ["i1", "i2"]
  @values ["v1", "v2"]
  @seeds 1..500
  @steps 40

  test "encrypted sessions agree with the model after every operation" do
    counts =
      for seed <- @seeds, reduce: %{} do
        acc ->
          :rand.seed(:exsss, {seed, seed * 3, seed * 5})

          vault =
            Vault.create(Enum.map(@members, &{&1, "pw" <> &1}),
              iterations: 1_000,
              unsafe_test: true
            )

          run(Household.new(@members), vault, @steps, seed, acc)
      end

    for kind <- [:ok, :granted, :joint, :relinquished, :deleted, :left, :linked, :withdrawn],
        do:
          assert(
            Map.get(counts, kind, 0) >= 30,
            "only #{Map.get(counts, kind, 0)} #{kind}: #{inspect(counts)}"
          )
  end

  defp run(_model, _vault, 0, _seed, acc), do: acc

  defp run(model, vault, n, seed, acc) do
    {actor, op} = pick(model)

    case op.(model) do
      {:error, _} ->
        run(model, vault, n - 1, seed, acc)

      ok ->
        model2 = elem(ok, 1)

        {:ok, s} = Session.open(vault, actor, "pw" <> actor)
        session_result = op.(s.household)

        assert elem(session_result, 0) == :ok,
               "seed #{seed}: #{actor} blocked in session: #{inspect(session_result)}"

        vault2 = Session.save(%{s | household: elem(session_result, 1)}).vault

        compare!(model2, vault2, seed)
        run(model2, vault2, n - 1, seed, count(model, model2, acc))
    end
  end

  defp pick(model) do
    members = Enum.sort(model.members)
    anyone = if members == [], do: "a", else: Enum.random(members)
    item = Enum.random(@items ++ @values)
    other = Enum.random(@members)
    owners = if i = model.items[item], do: Enum.sort(i.owners), else: []
    # mostly act as a real owner of the chosen item, so joint paths are exercised
    actor = if owners != [] and :rand.uniform(10) <= 7, do: Enum.random(owners), else: anyone

    # Every random choice is drawn here, never inside an op: each op runs twice (model and session).
    amount = :rand.uniform(50)
    new_item = Enum.random(@items)
    new_value = Enum.random(@values)
    link_item = Enum.random(@items)
    link_value = Enum.random(@values)

    case :rand.uniform(23) do
      n when n in 1..2 ->
        {actor,
         &Household.add_item(&1, actor, new_item, %{amount: amount, note: "n", unit: :cents})}

      3 ->
        {actor, &Alignment.add_value(&1, actor, new_value, "v")}

      n when n in 4..6 ->
        {actor, &Household.propose_grant(&1, actor, item, other)}

      7 ->
        {actor, &Household.revoke_grant(&1, actor, item, other)}

      n when n in 8..9 ->
        {actor, &Household.propose_owners(&1, actor, item, Enum.sort(Enum.uniq([actor, other])))}

      n when n in 10..13 ->
        consent_op(model, anyone)

      n when n in 14..15 ->
        relinquish_op(model, actor, item)

      16 ->
        {actor, &Exit.delete(&1, actor, item)}

      n when n in 17..19 ->
        {actor, &Alignment.link(&1, actor, link_item, link_value)}

      20 ->
        {anyone, &Exit.leave(&1, anyone)}

      n when n in 21..23 ->
        withdraw_op(model, anyone)
    end
  end

  # REQ-125: mostly an owner of the proposal's item, so withdrawals actually happen.
  defp withdraw_op(model, fallback) do
    case Enum.sort(Map.keys(model.proposals)) do
      [] ->
        {fallback, fn _ -> {:error, :none} end}

      ids ->
        id = Enum.random(ids)
        owners = Enum.sort(model.items[model.proposals[id].item_id].owners)
        who = if :rand.uniform(10) <= 8, do: Enum.random(owners), else: Enum.random(@members)
        {who, &Household.withdraw(&1, who, id)}
    end
  end

  # Aimed at a jointly owned item when one exists, so relinquishment is actually exercised.
  defp relinquish_op(model, actor, item) do
    case for({id, i} <- Enum.sort(model.items), MapSet.size(i.owners) > 1, do: {id, i}) do
      [] ->
        {actor, &Household.relinquish(&1, actor, item)}

      joint ->
        {id, i} = Enum.random(joint)
        who = Enum.random(Enum.sort(i.owners))
        {who, &Household.relinquish(&1, who, id)}
    end
  end

  # A consent by a current owner or prospective joiner of a random pending proposal.
  defp consent_op(model, fallback) do
    case Enum.sort(Map.keys(model.proposals)) do
      [] ->
        {fallback, fn _ -> {:error, :none} end}

      ids ->
        id = Enum.random(ids)
        p = model.proposals[id]
        who = Enum.random(Enum.sort(MapSet.union(model.items[p.item_id].owners, joiners(p))))
        {who, &Household.consent(&1, who, id)}
    end
  end

  # m may read a value it is being added to once every current owner has consented (REQ-115).
  defp approved_joiner?(model, id, m) do
    item = model.items[id]

    Map.get(item.attrs, :kind) == :value and
      Enum.any?(model.proposals, fn {_, p} ->
        p.item_id == id and m in joiners(p) and m not in item.owners and
          MapSet.subset?(item.owners, p.consents)
      end)
  end

  defp joiners(%{change: {:owners, new}}), do: new
  defp joiners(_), do: MapSet.new()

  defp compare!(model, vault, seed) do
    for m <- Enum.sort(model.members) do
      {:ok, s} = Session.open(vault, m, "pw" <> m)
      h = s.household

      # WI-020: legitimate operations never look like tampering
      assert Session.integrity_issues(s) == [],
             "seed #{seed}: false integrity alarm for #{m}: #{inspect(Session.integrity_issues(s))}"

      assert View.visible_items(h, m) == View.visible_items(model, m),
             "seed #{seed}: visible items of #{m}"

      assert Household.pending(h, m) == Household.pending(model, m),
             "seed #{seed}: pending of #{m}"

      assert Alignment.links(h, m) |> Enum.sort() == Alignment.links(model, m) |> Enum.sort(),
             "seed #{seed}: links of #{m}"

      assert Alignment.distribution(h, m) == Alignment.distribution(model, m),
             "seed #{seed}: distribution of #{m}"

      assert Exit.export(h, m) == Exit.export(model, m), "seed #{seed}: export of #{m}"

      assert Ledger.deletions(h, m) == Ledger.deletions(model, m),
             "seed #{seed}: deletions of #{m}"

      for {id, item} <- model.items do
        assert Ledger.read(h, m, id) == Ledger.read(model, m, id),
               "seed #{seed}: ledger #{id} for #{m}"

        readable = m in item.owners or m in item.grantees
        rec = vault.items[id]

        for {r, sealed} <- rec.keys,
            r != m,
            do:
              assert(
                :error ==
                  Crypto.open(s.pub, s.priv, sealed, Vault.aad(vault.hid, {:item_key, id, r}))
              )

        # nobody can open ledger entries sealed to someone else
        for e <- rec.ledger, {r, sealed} <- e.keys, r != m do
          assert :error ==
                   Crypto.open(
                     s.pub,
                     s.priv,
                     sealed,
                     Vault.aad(vault.hid, {:entry_key, id, e.seq, r})
                   )
        end

        # a non-owner holds ledger entries only as an approved prospective joiner (REQ-120)
        if m not in item.owners and Enum.any?(rec.ledger, &Map.has_key?(&1.keys, m)) do
          assert approved_joiner?(model, id, m),
                 "seed #{seed}: non-owner #{m} holds ledger keys for #{id}"
        end

        # a non-reader holds no sealed key for the item (approved prospective joiners excepted, REQ-115)
        if not readable and Map.has_key?(rec.keys, m) do
          assert approved_joiner?(model, id, m),
                 "seed #{seed}: #{m} holds a key for unreadable #{id}"
        end
      end
    end

    assert MapSet.new(Map.keys(vault.members)) == model.members, "seed #{seed}: vault membership"
  end

  defp count(before, h, acc) do
    new =
      for {id, entries} <- h.ledger,
          e <- Enum.drop(entries, length(Map.get(before.ledger, id, []))),
          do: e

    withdrawn =
      if map_size(h.proposals) < map_size(before.proposals) and h.items == before.items and
           h.ledger == before.ledger,
         do: [:withdrawn],
         else: []

    kinds =
      [:ok] ++
        for(e <- new, e.event == :granted, do: :granted) ++
        for(e <- new, length(e.by) > 1, do: :joint) ++
        for(e <- new, e.event == :owner_relinquished, do: :relinquished) ++
        List.duplicate(:deleted, (map_size(before.items) - map_size(h.items)) |> max(0)) ++
        List.duplicate(:left, MapSet.size(before.members) - MapSet.size(h.members)) ++
        List.duplicate(:linked, max(total_links(h) - total_links(before), 0)) ++
        withdrawn

    Enum.reduce(kinds, acc, fn k, a -> Map.update(a, k, 1, &(&1 + 1)) end)
  end

  defp total_links(h), do: h.links |> Map.values() |> Enum.map(&MapSet.size/1) |> Enum.sum()
end
