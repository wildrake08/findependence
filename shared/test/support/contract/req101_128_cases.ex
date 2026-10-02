defmodule FindependenceShared.Contract.B1 do
  @moduledoc """
  Helpers for the contract cases of REQ-101..REQ-128 (REQ-188 AC-1, WI-074, batch B1). Each takes the form
  module first, like `FindependenceShared.Contract.Helpers`.
  """

  import ExUnit.Assertions
  import FindependenceShared.Contract.Helpers
  alias FindependenceShared.{Households, Items, Planning, Portability, Scope, Values}

  @doc "The reason of a context result: `:ok`, or the failure reason."
  def reason({:ok, _}), do: :ok
  def reason({:error, _category, reason, _session}), do: reason
  def reason({:error, _category, reason}), do: reason

  @doc "The member ids of these names, sorted."
  def ids(form, h, names), do: names |> Enum.map(&id(form, h, &1)) |> Enum.sort()

  @doc "The id of the entry with this value label in a household view, or nil."
  def find_label(household, label),
    do: Enum.find_value(household.items, fn {id, i} -> if i.attrs[:label] == label, do: id end)

  @doc "Adds a value for the named member through the Values context and returns its id."
  def add_value(form, h, name, label) do
    {:ok, saved} = Values.add_value(scope(form, h, name), label)
    find_label(saved.household, label)
  end

  @doc "Adds an ordinary item for `owner` and makes it jointly owned with `others`, each agreeing (WI-086)."
  def joint(form, h, owner, others, note, opts \\ []) do
    item = add_item(form, h, owner, note, opts)
    # each joining owner agrees (WI-086, CP-029)
    {:ok, _} = make_owners(form, h, owner, item, [owner | others])
    item
  end

  @doc "A value shared by `creator` and `joiners`, each joiner having consented."
  def shared_value(form, h, creator, joiners, label) do
    v = add_value(form, h, creator, label)
    owners = [id(form, h, creator) | Enum.map(joiners, &id(form, h, &1))]
    {:ok, _} = Items.propose_owners(scope(form, h, creator), v, owners)
    p = pid(form, h, creator, v)
    for j <- joiners, do: {:ok, _} = Items.consent(scope(form, h, j), p)
    v
  end

  @doc "The pending proposals on `item` the named member is shown."
  def pending_on(form, h, name, item),
    do: for(p <- Items.pending(scope(form, h, name)), p.item_id == item, do: p)

  @doc "The id of the one pending proposal on `item` the named member is shown."
  def pid(form, h, name, item) do
    [p] = pending_on(form, h, name, item)
    p.id
  end

  @doc "The item's owners, as the named member (an owner or grantee) sees them, sorted."
  def owners(form, h, name, item) do
    {:ok, i} = Items.get(scope(form, h, name), item)
    Enum.sort(i.owners)
  end

  @doc "The members the item's key is sealed to in storage, sorted."
  def sealed_to(form, h, item), do: stored(form, h).items[item].keys |> Map.keys() |> Enum.sort()

  @doc "The item's stored ledger entries as `{seq, box}`: the encrypted content of each entry."
  def stored_entries(form, h, item),
    do: for(e <- stored(form, h).items[item].ledger, do: {e.seq, e.box})

  @doc """
  A household with `names` and a former member "zed", who left; returns the household and zed's last scope,
  that of a non-member.
  """
  def with_former(form, names) do
    h = household(form, names ++ ["zed"])
    zed = id(form, h, "zed")
    {:ok, saved} = Households.leave(scope(form, h, "zed"))
    {h, Scope.new(saved), zed}
  end

  @doc "One entry of every kind created by the named member: money, value, account, debt, shared plan."
  def every_kind(form, h, name, other) do
    s = scope(form, h, name)
    money = add_item(form, h, name, "Groceries", amount: -100)
    value = add_value(form, h, name, "a home that feels safe")
    {:ok, _} = FindependenceShared.Balances.add_account(s, "b1-account", "Checking", :checking)

    {:ok, _} =
      FindependenceShared.Balances.add_debt(scope(form, h, name), "b1-debt", "Visa", :card)

    {:ok, _} = Planning.new_plan(scope(form, h, name), "b1-plan", "Side business")
    {:ok, saved} = Planning.share_plan(scope(form, h, name), "b1-plan", [id(form, h, other)])

    plan =
      Enum.find_value(saved.household.items, fn {id, i} ->
        if i.attrs[:kind] == :plan, do: id
      end)

    %{money: money, value: value, account: "b1-account", debt: "b1-debt", plan: plan}
  end

  @doc "Owners and grantees reproduced by replaying an item's history alone (REQ-105 AC-2)."
  def replay(entries) do
    Enum.reduce(entries, {MapSet.new(), MapSet.new()}, fn e, {o, g} ->
      case e.event do
        :created ->
          {MapSet.new(e.details.owners), g}

        :owners_changed ->
          new = MapSet.new(e.details.owners)
          {new, MapSet.difference(g, new)}

        :owner_relinquished ->
          {MapSet.delete(o, e.details.owner), g}

        :granted ->
          {o, MapSet.put(g, e.details.grantee)}

        ev when ev in [:grant_revoked, :grantee_departed] ->
          {o, MapSet.delete(g, e.details.grantee)}

        :reading_added ->
          {o, g}
      end
    end)
  end

  @doc """
  Everything the contexts return to a member (REQ-114 AC-5): distribution, links, export, visible items,
  pending requests, deletion records, and how link and unlink answer for `probes` ({item, value} pairs).
  """
  def seen(%Scope{} = s, probes \\ []) do
    %{
      distribution: Values.distribution(s),
      links: Values.links(s),
      export: Portability.export(s),
      visible: Items.visible(s),
      pending: Items.pending(s),
      deletions: Findependence.Ledger.deletions(s.household, s.member),
      probes:
        for {i, v} <- probes do
          {i, v, reason(Values.link(s, i, v)), reason(Values.unlink(s, i, v))}
        end
    }
  end

  @doc "A distribution bucket."
  def bucket(count, pm_in \\ 0, pm_out \\ 0, one_in \\ 0, one_out \\ 0),
    do: %{
      count: count,
      per_month: %{in: pm_in, out: pm_out},
      one_off: %{in: one_in, out: one_out}
    }

  @doc """
  REQ-114 base: ana owns rent (monthly) and a value; ben owns a bus fare (one-off) and a value.
  Returns the household and the ids.
  """
  def base114(form) do
    h = household(form, ~w(ana ben cy))

    ids = %{
      rent: add_item(form, h, "ana", "Rent", amount: -100_000, frequency: {:every, 1, :month}),
      av: add_value(form, h, "ana", "ana's value"),
      bus: add_item(form, h, "ben", "Bus", amount: -2_000, frequency: :one_off),
      bv: add_value(form, h, "ben", "ben's value")
    }

    {h, ids}
  end

  @doc "REQ-114: how ben gets sight of something and links it, and how he loses it; and the lost pair."
  def cause(:revoke_item, form, h, x) do
    share = fn ->
      {:ok, _} = Items.propose_grant(scope(form, h, "ana"), x.rent, id(form, h, "ben"))
      {:ok, _} = Values.link(scope(form, h, "ben"), x.rent, x.bv)
    end

    lose = fn -> Items.revoke_grant(scope(form, h, "ana"), x.rent, id(form, h, "ben")) end
    {share, lose, [{x.rent, x.bv}]}
  end

  def cause(:revoke_value, form, h, x) do
    share = fn ->
      {:ok, _} = Items.propose_grant(scope(form, h, "ana"), x.av, id(form, h, "ben"))
      {:ok, _} = Values.link(scope(form, h, "ben"), x.bus, x.av)
    end

    lose = fn -> Items.revoke_grant(scope(form, h, "ana"), x.av, id(form, h, "ben")) end
    {share, lose, [{x.bus, x.av}]}
  end

  def cause(:relinquish_item, form, h, x) do
    share = fn ->
      {:ok, _} = change_owners(form, h, "ana", x.rent, ~w(ana ben))
      {:ok, _} = Values.link(scope(form, h, "ben"), x.rent, x.bv)
    end

    lose = fn -> Items.relinquish(scope(form, h, "ben"), x.rent) end
    {share, lose, [{x.rent, x.bv}]}
  end

  def cause(:relinquish_value, form, h, x) do
    share = fn ->
      {:ok, _} = change_owners(form, h, "ana", x.av, ~w(ana ben))
      {:ok, _} = Items.consent(scope(form, h, "ben"), pid(form, h, "ana", x.av))
      {:ok, _} = Values.link(scope(form, h, "ben"), x.bus, x.av)
    end

    lose = fn -> Items.relinquish(scope(form, h, "ben"), x.av) end
    {share, lose, [{x.bus, x.av}]}
  end

  def cause(:delete_item, form, h, x) do
    {share, _, probes} = cause(:revoke_item, form, h, x)
    {share, fn -> Items.delete(scope(form, h, "ana"), x.rent) end, probes}
  end

  def cause(:delete_value, form, h, x) do
    {share, _, probes} = cause(:revoke_value, form, h, x)
    {share, fn -> Items.delete(scope(form, h, "ana"), x.av) end, probes}
  end

  @doc """
  REQ-108 AC-4: a joint account with a grant left pending once ana is its sole owner (ben relinquished, or
  ben's removal was agreed), deleted by ana, then the id used again.
  """
  def deleted_pending_grant(form, way) do
    h = household(form, ~w(ana ben cy))
    acct = "b1-acct-reused"
    s = fn n -> scope(form, h, n) end
    {:ok, _} = FindependenceShared.Balances.add_account(s.("ana"), acct, "Joint", :checking)
    {:ok, _} = Items.propose_owners(s.("ana"), acct, ids(form, h, ~w(ana ben)))
    # WI-086: ben agrees to become an owner
    {:ok, _} = Items.consent(s.("ben"), pid(form, h, "ben", acct))
    {:ok, _} = Items.propose_grant(s.("ana"), acct, id(form, h, "cy"))
    grant = pid(form, h, "ana", acct)

    case way do
      :relinquish ->
        {:ok, _} = Items.relinquish(s.("ben"), acct)

      :agreement ->
        {:ok, _} = Items.propose_owners(s.("ana"), acct, [id(form, h, "ana")])
        other = Enum.find(pending_on(form, h, "ben", acct), &(&1.id != grant))
        {:ok, _} = Items.consent(s.("ben"), other.id)
    end

    assert owners(form, h, "ana", acct) == [id(form, h, "ana")]
    assert [%{id: ^grant}] = pending_on(form, h, "ana", acct)

    {:ok, _} = Items.delete(s.("ana"), acct)
    assert Items.pending(s.("ana")) == []
    assert Items.proposal(s.("ana"), grant) == nil
    assert {:error, _, :not_found, _} = Items.consent(s.("ana"), grant)
    assert {:error, _, :not_found, _} = Items.withdraw(s.("ana"), grant)
    assert stored(form, h).proposals == %{}

    # the id used again
    {:ok, _} = FindependenceShared.Balances.add_account(s.("ana"), acct, "Again", :savings)
    assert Items.pending(s.("ana")) == []
    assert Items.proposal(s.("ana"), grant) == nil
    assert {:error, _, :not_found, _} = Items.consent(s.("ana"), grant)
    refute reads?(form, h, "cy", acct)
    assert owners(form, h, "ana", acct) == [id(form, h, "ana")]
  end
end

defmodule FindependenceShared.Contract.Cases.Req101To128 do
  @moduledoc """
  Contract cases for the CORE and PERSIST acceptance criteria of REQ-101..REQ-128 (REQ-188 AC-1, WI-074,
  batch B1). Criteria no context operation reaches are listed in the batch's report, not guessed at here.
  """

  defmacro __using__(_) do
    quote do
      alias FindependenceShared.{
        Balances,
        CashFlow,
        Households,
        Items,
        Planning,
        Portability,
        Values
      }

      alias FindependenceShared.Contract.B1

      describe "REQ-101" do
        test "REQ-101 AC-1: every kind of item is created owned by its creator alone" do
          h = household(@form, ~w(ana ben))
          kinds = B1.every_kind(@form, h, "ana", "ben")
          ana = id(@form, h, "ana")
          stored = stored(@form, h)

          for {kind, item} <- kinds do
            assert B1.owners(@form, h, "ana", item) == [ana], inspect(kind)
            assert stored.items[item].owners == [ana], inspect(kind)
          end
        end

        test "REQ-101 AC-2: a non-member can't be proposed as an owner, for every kind" do
          {h, _zed_scope, zed} = B1.with_former(@form, ~w(ana ben))
          kinds = B1.every_kind(@form, h, "ana", "ben")
          ana = id(@form, h, "ana")

          for {kind, item} <- kinds, other <- [zed, "b1-not-a-member"] do
            assert {:error, :unauthorized, :not_a_member, _} =
                     Items.propose_owners(scope(@form, h, "ana"), item, [ana, other]),
                   inspect(kind)
          end
        end

        test "REQ-101 AC-2: a non-member can't create an item, a value, or an account" do
          {h, zed_scope, _zed} = B1.with_former(@form, ~w(ana))
          before = stored(@form, h).items

          input = %{note: "Rent", amount: {:ok, -1000}, frequency: :monthly, on: ""}
          assert {:error, _, :not_a_member, _} = Items.add_item(zed_scope, input)
          assert {:error, _, :not_a_member, _} = Values.add_value(zed_scope, "freedom")

          assert {:error, _, :not_a_member, _} =
                   Balances.add_account(zed_scope, "b1-zed", "Checking", :checking)

          assert stored(@form, h).items == before
        end

        test "REQ-101 AC-3: a proposal of an empty owner set is refused, for every kind" do
          h = household(@form, ~w(ana ben))

          for {kind, item} <- B1.every_kind(@form, h, "ana", "ben") do
            assert {:error, :validation, :no_owners, _} =
                     Items.propose_owners(scope(@form, h, "ana"), item, []),
                   inspect(kind)
          end
        end

        test "REQ-101 AC-4: the last owner can't relinquish an item or leave while owning it" do
          h = household(@form, ~w(ana ben))
          kinds = B1.every_kind(@form, h, "ana", "ben")

          for {kind, item} <- kinds do
            assert {:error, _, :sole_owner, _} = Items.relinquish(scope(@form, h, "ana"), item),
                   inspect(kind)
          end

          assert {:error, _, :still_owner, _} = Households.leave(scope(@form, h, "ana"))

          j = B1.joint(@form, h, "ana", ["ben"], "Rent")
          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), j)
          assert {:error, _, :sole_owner, _} = Items.relinquish(scope(@form, h, "ana"), j)
          assert B1.owners(@form, h, "ana", j) == [id(@form, h, "ana")]
        end
      end

      describe "REQ-103" do
        test "REQ-103 AC-1: a grantee, an unrelated member, or a non-member can't create a grant" do
          {h, zed_scope, _} = B1.with_former(@form, ~w(ana ben cy dan))
          item = add_item(@form, h, "ana", "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, id(@form, h, "ben"))
          dan = id(@form, h, "dan")

          for s <- [scope(@form, h, "ben"), scope(@form, h, "cy"), zed_scope] do
            assert {:error, _, :not_found, _} = Items.propose_grant(s, item, dan)
          end

          assert Items.pending(scope(@form, h, "ana")) == []
          assert stored(@form, h).proposals == %{}
          refute reads?(@form, h, "dan", item)
        end

        test "REQ-103 AC-2: a grantee (even of their own grant), an unrelated member, or a non-member can't revoke" do
          {h, zed_scope, _} = B1.with_former(@form, ~w(ana ben cy))
          item = add_item(@form, h, "ana", "Rent")
          ben = id(@form, h, "ben")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, ben)

          for s <- [scope(@form, h, "ben"), scope(@form, h, "cy"), zed_scope] do
            assert {:error, _, :not_found, _} = Items.revoke_grant(s, item, ben)
          end

          assert reads?(@form, h, "ben", item)
          {:ok, i} = Items.get(scope(@form, h, "ana"), item)
          assert i.grantees == [ben]
        end

        test "REQ-103 AC-3: on a joint item a grant takes effect only once every owner consented; a sole owner's at once" do
          h = household(@form, ~w(ana ben cy dan))
          cy = id(@form, h, "cy")
          old_cy = scope(@form, h, "cy")

          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, cy)
          refute reads?(@form, h, "cy", item)
          refute cy in B1.sealed_to(@form, h, item)
          assert [%{change: {:grant, ^cy}} = p] = B1.pending_on(@form, h, "ben", item)

          {:ok, _} = Items.consent(scope(@form, h, "ben"), p.id)
          assert {:ok, %{attrs: %{note: "Rent"}}} = Items.get(Households.view(old_cy), item)
          assert cy in B1.sealed_to(@form, h, item)
          assert Items.pending(scope(@form, h, "ana")) == []

          solo = add_item(@form, h, "ana", "Books")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), solo, id(@form, h, "dan"))
          assert reads?(@form, h, "dan", solo)
          assert Items.pending(scope(@form, h, "ana")) == []
        end

        test "REQ-103 AC-4: any single owner of a jointly owned item revokes a grant alone" do
          h = household(@form, ~w(ana ben cy dan))
          dan = id(@form, h, "dan")
          item = B1.joint(@form, h, "ana", ~w(ben cy), "Rent")

          for o <- ~w(ana ben cy) do
            {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, dan)
            p = B1.pid(@form, h, "ana", item)
            {:ok, _} = Items.consent(scope(@form, h, "ben"), p)
            {:ok, _} = Items.consent(scope(@form, h, "cy"), p)
            assert reads?(@form, h, "dan", item)

            {:ok, _} = Items.revoke_grant(scope(@form, h, o), item, dan)
            refute reads?(@form, h, "dan", item), o
          end
        end
      end

      describe "REQ-105" do
        test "REQ-105 AC-1: each ownership change, grant, and revocation (including a departure) adds an entry" do
          h = household(@form, ~w(ana ben cy))
          [ana, ben, cy] = Enum.map(~w(ana ben cy), &id(@form, h, &1))
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")

          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, cy)
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", item))
          {:ok, _} = Items.revoke_grant(scope(@form, h, "ben"), item, cy)
          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), item)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, cy)
          {:ok, _} = Households.leave(scope(@form, h, "cy"))

          {:ok, entries} = Items.ledger(Households.view(scope(@form, h, "ana")), item)

          assert Enum.map(entries, &{&1.seq, &1.event, &1.by}) == [
                   {1, :created, [ana]},
                   # WI-086: ben agreed to become an owner, so his agreement is recorded too
                   {2, :owners_changed, Enum.sort([ana, ben])},
                   {3, :granted, Enum.sort([ana, ben])},
                   {4, :grant_revoked, [ben]},
                   {5, :owner_relinquished, [ben]},
                   {6, :granted, [ana]},
                   {7, :grantee_departed, [cy]}
                 ]
        end

        test "REQ-105 AC-2: replaying the history alone reproduces the current owners and grantees" do
          h = household(@form, ~w(ana ben cy dan))
          [cy, dan] = Enum.map(~w(cy dan), &id(@form, h, &1))
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, cy)
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", item))
          {:ok, _} = Items.propose_grant(scope(@form, h, "ben"), item, dan)
          {:ok, _} = Items.consent(scope(@form, h, "ana"), B1.pid(@form, h, "ana", item))
          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), item, cy)

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), item, B1.ids(@form, h, ~w(ana ben dan)))

          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", item))
          # WI-086: dan agrees to become an owner
          {:ok, _} = Items.consent(scope(@form, h, "dan"), B1.pid(@form, h, "dan", item))
          {:ok, _} = Items.relinquish(scope(@form, h, "ana"), item)

          s = Households.view(scope(@form, h, "ben"))
          {:ok, entries} = Items.ledger(s, item)
          {:ok, now} = Items.get(s, item)
          {owners, grantees} = B1.replay(entries)
          assert Enum.sort(owners) == now.owners
          assert Enum.sort(grantees) == now.grantees
          assert now.owners == B1.ids(@form, h, ~w(ben dan))
        end

        test "REQ-105 AC-3: stored history entries are never changed or removed while the item exists" do
          h = household(@form, ~w(ana ben cy))
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, id(@form, h, "cy"))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", item))
          earlier = B1.stored_entries(@form, h, item)
          {:ok, earlier_read} = Items.ledger(scope(@form, h, "ana"), item)

          {:ok, _} = Items.revoke_grant(scope(@form, h, "ben"), item, id(@form, h, "cy"))

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), item, B1.ids(@form, h, ~w(ana ben cy)))

          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", item))
          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), item)

          later = B1.stored_entries(@form, h, item)
          assert length(later) > length(earlier)
          assert Enum.take(later, length(earlier)) == earlier

          {:ok, later_read} = Items.ledger(Households.view(scope(@form, h, "ana")), item)
          assert Enum.take(later_read, length(earlier_read)) == earlier_read
        end

        test "REQ-105 AC-4: an owner added later reads the whole history" do
          h = household(@form, ~w(ana ben cy))
          ben = id(@form, h, "ben")
          old_ben = scope(@form, h, "ben")
          item = add_item(@form, h, "ana", "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, id(@form, h, "cy"))
          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), item, id(@form, h, "cy"))

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), item, B1.ids(@form, h, ~w(ana ben)))

          # WI-086: ben agrees to become an owner
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", item))

          {:ok, ana_read} = Items.ledger(scope(@form, h, "ana"), item)
          {:ok, ben_read} = Items.ledger(Households.view(old_ben), item)
          assert ben_read == ana_read

          assert Enum.map(ben_read, & &1.event) == [
                   :created,
                   :granted,
                   :grant_revoked,
                   :owners_changed
                 ]

          for e <- stored(@form, h).items[item].ledger, do: assert(Map.has_key?(e.keys, ben))
        end
      end

      describe "REQ-106" do
        test "REQ-106 AC-1: every aggregate counts only what the member can see" do
          h = household(@form, ~w(ana ben))
          today = ~D[2026-10-01]

          add_item(@form, h, "ana", "Pay",
            amount: 300_000,
            frequency: {:every, 1, :month},
            on: "2026-10-15"
          )

          add_item(@form, h, "ana", "Rent",
            amount: -150_000,
            frequency: {:every, 1, :month},
            on: "2026-10-03"
          )

          aggregates = fn ->
            s = scope(@form, h, "ana")

            %{
              distribution: Values.distribution(s),
              project: CashFlow.project(s, today),
              cash_flow: CashFlow.cash_flow(s, today, 60),
              set_asides: CashFlow.set_asides(s),
              plan_set_asides: Planning.set_asides(s),
              cover: Planning.cover(s),
              retirement: Planning.retirement_projection(s, today)
            }
          end

          before = aggregates.()

          # ben's own entries of every kind that feeds an aggregate
          secret =
            add_item(@form, h, "ben", "Secret",
              amount: -40_000,
              frequency: {:every, 1, :month},
              on: "2026-10-05"
            )

          add_item(@form, h, "ben", "Insurance",
            amount: -90_000,
            frequency: {:every, 1, :year},
            on: "2026-11-01"
          )

          add_item(@form, h, "ben", "Bonus",
            amount: 50_000,
            frequency: :one_off,
            on: "2026-10-20"
          )

          B1.add_value(@form, h, "ben", "ben's value")

          for {id, type} <- [{"b1-ben-chk", :checking}, {"b1-ben-ira", :ira}] do
            {:ok, _} = Balances.add_account(scope(@form, h, "ben"), id, "Acct #{id}", type)

            {:ok, _} =
              Balances.add_reading(scope(@form, h, "ben"), id, %{
                balance: {:ok, 500_000, false},
                on: {:ok, "2026-09-01"},
                rate: {:ok, 0},
                min_payment: {:ok, nil}
              })
          end

          assert aggregates.() == before

          # not vacuous: once ana can see ben's item, it counts
          {:ok, _} = Items.propose_grant(scope(@form, h, "ben"), secret, id(@form, h, "ana"))
          now = aggregates.()
          refute now.distribution == before.distribution
        end
      end

      describe "REQ-107" do
        test "REQ-107 AC-1: an owner change applies only once every current owner (including one added while it waited) consented" do
          h = household(@form, ~w(ana ben cy dan))
          dan = id(@form, h, "dan")
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")

          {:ok, _} = change_owners(@form, h, "ana", item, ~w(ana))
          p = B1.pid(@form, h, "ana", item)
          assert B1.owners(@form, h, "ana", item) == B1.ids(@form, h, ~w(ana ben))
          assert {:error, _, :not_found, _} = Items.consent(scope(@form, h, "cy"), p)
          {:ok, _} = Items.consent(scope(@form, h, "ben"), p)
          assert B1.owners(@form, h, "ana", item) == B1.ids(@form, h, ~w(ana))

          # a grant proposed while ben was an owner, then cy added as an owner while it waited
          j = B1.joint(@form, h, "ana", ~w(ben), "Car")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), j, dan)
          [grant] = B1.pending_on(@form, h, "ana", j)

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ben"), j, B1.ids(@form, h, ~w(ana ben cy)))

          add = Enum.find(B1.pending_on(@form, h, "ana", j), &(&1.id != grant.id))
          {:ok, _} = Items.consent(scope(@form, h, "ana"), add.id)
          # WI-086: cy agrees to become an owner
          {:ok, _} = Items.consent(scope(@form, h, "cy"), add.id)
          assert B1.owners(@form, h, "ana", j) == B1.ids(@form, h, ~w(ana ben cy))

          assert {:error, _, :not_found, _} = Items.consent(scope(@form, h, "dan"), grant.id)
          {:ok, _} = Items.consent(scope(@form, h, "ben"), grant.id)
          refute reads?(@form, h, "dan", j), "applied before cy, added while it waited, consented"
          {:ok, _} = Items.consent(scope(@form, h, "cy"), grant.id)
          assert reads?(@form, h, "dan", j)
        end

        test "REQ-107 AC-2: an owner removes themselves without consent while another owner remains" do
          h = household(@form, ~w(ana ben))
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), item)
          assert B1.owners(@form, h, "ana", item) == B1.ids(@form, h, ~w(ana))
          refute reads?(@form, h, "ben", item)
        end

        test "REQ-107 AC-3: self-removal removes only the actor; removing anyone else needs every owner" do
          h = household(@form, ~w(ana ben cy))
          item = B1.joint(@form, h, "ana", ~w(ben cy), "Rent")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), item, B1.ids(@form, h, ~w(ana cy)))

          p = B1.pid(@form, h, "ana", item)
          assert [%{id: ^p}] = B1.pending_on(@form, h, "ben", item)
          {:ok, _} = Items.consent(scope(@form, h, "cy"), p)
          assert B1.owners(@form, h, "ana", item) == B1.ids(@form, h, ~w(ana ben cy))

          {:ok, _} = Items.relinquish(scope(@form, h, "cy"), item)
          assert B1.owners(@form, h, "ana", item) == B1.ids(@form, h, ~w(ana ben))
        end

        test "REQ-107 AC-4: the last owner can't remove themselves" do
          h = household(@form, ~w(ana ben))
          item = add_item(@form, h, "ana", "Rent")
          assert {:error, _, :sole_owner, _} = Items.relinquish(scope(@form, h, "ana"), item)
          assert B1.owners(@form, h, "ana", item) == B1.ids(@form, h, ~w(ana))
        end

        test "REQ-107 AC-5: a non-owner, a grantee, or a non-member can't add themselves as an owner" do
          {h, zed_scope, zed} = B1.with_former(@form, ~w(ana ben cy))
          [ana, ben, cy] = Enum.map(~w(ana ben cy), &id(@form, h, &1))
          item = add_item(@form, h, "ana", "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, cy)

          for {s, me} <- [
                {scope(@form, h, "ben"), ben},
                {scope(@form, h, "cy"), cy},
                {zed_scope, zed}
              ],
              owners <- [[ana, me], [me]] do
            assert {:error, _, :not_found, _} = Items.propose_owners(s, item, owners)
          end

          assert stored(@form, h).proposals == %{}
          assert B1.owners(@form, h, "ana", item) == [ana]
        end
      end

      describe "REQ-108" do
        test "REQ-108 AC-1: a sole owner deletes an item without anyone's consent" do
          h = household(@form, ~w(ana ben))
          item = add_item(@form, h, "ana", "Rent")
          assert {:ok, _} = Items.delete(scope(@form, h, "ana"), item)
          assert Items.get(scope(@form, h, "ana"), item) == {:error, :not_found}
        end

        test "REQ-108 AC-2: a joint owner's deletion is refused" do
          h = household(@form, ~w(ana ben))
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")

          for o <- ~w(ana ben) do
            assert {:error, _, :not_sole_owner, _} = Items.delete(scope(@form, h, o), item)
          end

          assert reads?(@form, h, "ana", item) and reads?(@form, h, "ben", item)
        end

        test "REQ-108 AC-3: after deletion nobody, including former grantees, can see the item" do
          h = household(@form, ~w(ana ben))
          item = add_item(@form, h, "ana", "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, id(@form, h, "ben"))
          old_ben = scope(@form, h, "ben")
          assert {:ok, _} = Items.get(old_ben, item)

          {:ok, _} = Items.delete(scope(@form, h, "ana"), item)

          for s <- [Households.view(old_ben), scope(@form, h, "ana")] do
            assert Items.get(s, item) == {:error, :not_found}
            assert Items.lookup(s, item) == nil
            assert Items.visible(s) == []
          end

          refute Map.has_key?(stored(@form, h).items, item)
        end

        test "REQ-108 AC-4: a deleted value's invitation is removed and never returns" do
          h = household(@form, ~w(ana ben))
          v = B1.add_value(@form, h, "ana", "home")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana ben)))

          invite = B1.pid(@form, h, "ben", v)

          {:ok, _} = Items.delete(scope(@form, h, "ana"), v)

          for n <- ~w(ana ben) do
            s = scope(@form, h, n)
            assert Items.pending(s) == []
            assert Items.proposal(s, invite) == nil
          end

          assert {:error, _, :not_found, _} = Items.consent(scope(@form, h, "ben"), invite)
          assert {:error, _, :not_found, _} = Items.withdraw(scope(@form, h, "ana"), invite)
          assert stored(@form, h).proposals == %{}
        end

        # FINDING (hosted): relinquishing a joint item while another owner's proposal on it is pending
        # fails in the hosted form's write (foreign key "proposals_item"); the local form accepts it.
        # failed on the hosted form before WI-074 fixed Domain.write (a changed item kept its row)
        test "REQ-108 AC-4: a grant left pending after a relinquishment goes on deletion and doesn't return with the id" do
          B1.deleted_pending_grant(@form, :relinquish)
        end

        test "REQ-108 AC-4: a grant left pending after an agreed owner change goes on deletion and doesn't return with the id" do
          B1.deleted_pending_grant(@form, :agreement)
        end

        test "REQ-108 AC-5: its history is removed" do
          h = household(@form, ~w(ana ben))
          item = add_item(@form, h, "ana", "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, id(@form, h, "ben"))
          assert [_, _] = stored(@form, h).items[item].ledger

          {:ok, _} = Items.delete(scope(@form, h, "ana"), item)
          assert Items.ledger(scope(@form, h, "ana"), item) == {:error, :not_found}
          refute Map.has_key?(stored(@form, h).items, item)
          assert Households.view(scope(@form, h, "ana")).household.ledger[item] == nil
        end

        test "REQ-108 AC-6: a deletion record of exactly the item id and a sequence number is kept" do
          h = household(@form, ~w(ana ben))
          ana = id(@form, h, "ana")
          i1 = add_item(@form, h, "ana", "Rent")
          v1 = B1.add_value(@form, h, "ana", "home")
          {:ok, _} = Items.delete(scope(@form, h, "ana"), i1)
          {:ok, _} = Items.delete(scope(@form, h, "ana"), v1)

          assert Findependence.Ledger.deletions(view(@form, h, "ana"), ana) == [
                   %{seq: 1, item_id: i1},
                   %{seq: 2, item_id: v1}
                 ]
        end

        test "REQ-108 AC-7: only the deleter can read the deletion record" do
          h = household(@form, ~w(ana ben))
          [ana, ben] = Enum.map(~w(ana ben), &id(@form, h, &1))
          item = add_item(@form, h, "ana", "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, ben)
          before = stored(@form, h).personal

          {:ok, _} = Items.delete(scope(@form, h, "ana"), item)

          after_ = stored(@form, h).personal
          refute after_[ana] == before[ana], "the record is in the deleter's own sealed record"
          assert after_[ben] == before[ben]
          assert Findependence.Ledger.deletions(view(@form, h, "ben"), ben) == []
          assert Map.keys(view(@form, h, "ben").deletions) -- [ben] == []
          assert [%{item_id: ^item}] = Findependence.Ledger.deletions(view(@form, h, "ana"), ana)
        end
      end

      describe "REQ-110" do
        test "REQ-110 AC-1: a member who owns nothing leaves without anyone's consent" do
          h = household(@form, ~w(ana ben))
          add_item(@form, h, "ana", "Rent")
          assert {:ok, _} = Households.leave(scope(@form, h, "ben"))
        end

        test "REQ-110 AC-2: leaving removes their membership" do
          h = household(@form, ~w(ana ben))
          ben = id(@form, h, "ben")
          old_ana = scope(@form, h, "ana")
          assert ben in Households.members(old_ana)

          {:ok, _} = Households.leave(scope(@form, h, "ben"))

          refute ben in Households.members(Households.view(old_ana))
          refute Map.has_key?(stored(@form, h).members, ben)

          assert {:error, _, :not_a_member, _} =
                   Items.propose_grant(
                     scope(@form, h, "ana"),
                     add_item(@form, h, "ana", "Rent"),
                     ben
                   )
        end

        test "REQ-110 AC-3: leaving removes every grant they hold" do
          h = household(@form, ~w(ana ben cy))
          [ana, ben] = Enum.map(~w(ana ben), &id(@form, h, &1))
          solo = add_item(@form, h, "ana", "Rent")
          j = B1.joint(@form, h, "ana", ~w(cy), "Car")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), solo, ben)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), j, ben)
          {:ok, _} = Items.consent(scope(@form, h, "cy"), B1.pid(@form, h, "cy", j))
          assert reads?(@form, h, "ben", solo) and reads?(@form, h, "ben", j)

          {:ok, _} = Households.leave(scope(@form, h, "ben"))

          s = Households.view(scope(@form, h, "ana"))

          for item <- [solo, j] do
            {:ok, i} = Items.get(s, item)
            assert i.grantees == []
            refute ben in B1.sealed_to(@form, h, item)
            {:ok, entries} = Items.ledger(s, item)
            assert %{event: :grantee_departed, details: %{grantee: ^ben}} = List.last(entries)
          end

          assert B1.sealed_to(@form, h, solo) == [ana]
        end

        test "REQ-110 AC-4: leaving removes every pending proposal that would grant to them" do
          h = household(@form, ~w(ana ben cy))
          ben = id(@form, h, "ben")
          j = B1.joint(@form, h, "ana", ~w(cy), "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), j, ben)
          assert [%{change: {:grant, ^ben}}] = B1.pending_on(@form, h, "cy", j)

          {:ok, _} = Households.leave(scope(@form, h, "ben"))

          assert Items.pending(Households.view(scope(@form, h, "ana"))) == []
          assert Items.pending(scope(@form, h, "cy")) == []
          assert stored(@form, h).proposals == %{}
        end

        test "REQ-110 AC-5: leaving removes every proposal that would make them an owner, and no other" do
          h = household(@form, ~w(ana ben cy))
          [ben, cy] = Enum.map(~w(ben cy), &id(@form, h, &1))
          v = B1.add_value(@form, h, "ana", "home")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana ben)))

          assert ben in B1.sealed_to(@form, h, v),
                 "a value invitation seals the key to the joiner"

          j = B1.joint(@form, h, "ana", ~w(cy), "Rent")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), j, B1.ids(@form, h, ~w(ana ben cy)))

          {:ok, _} = Items.propose_owners(scope(@form, h, "cy"), j, [cy])

          keep =
            Enum.find(
              B1.pending_on(@form, h, "cy", j),
              &(&1.change == {:owners, MapSet.new([cy])})
            )

          assert length(Items.pending(scope(@form, h, "ana"))) == 3

          {:ok, _} = Households.leave(scope(@form, h, "ben"))

          assert [%{id: id}] = Items.pending(Households.view(scope(@form, h, "ana")))
          assert id == keep.id
          assert Map.keys(stored(@form, h).proposals) == [keep.id]
          refute ben in B1.sealed_to(@form, h, v)
        end

        test "REQ-110 AC-6: a member who still owns anything, jointly or solely, item or value, is refused" do
          h = household(@form, ~w(ana ben))
          j = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          assert {:error, _, :still_owner, _} = Households.leave(scope(@form, h, "ben"))
          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), j)

          solo = add_item(@form, h, "ben", "Bus")
          assert {:error, _, :still_owner, _} = Households.leave(scope(@form, h, "ben"))
          {:ok, _} = Items.delete(scope(@form, h, "ben"), solo)

          B1.add_value(@form, h, "ben", "freedom")
          assert {:error, _, :still_owner, _} = Households.leave(scope(@form, h, "ben"))
          assert id(@form, h, "ben") in Households.members(scope(@form, h, "ana"))
        end

        test "REQ-110 AC-7: once they relinquish, transfer, or delete what they own, they leave" do
          h = household(@form, ~w(ana ben))
          ana = id(@form, h, "ana")
          j = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          solo = add_item(@form, h, "ben", "Bus")
          v = B1.add_value(@form, h, "ben", "freedom")
          assert {:error, _, :still_owner, _} = Households.leave(scope(@form, h, "ben"))

          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), j)
          {:ok, _} = Items.let_go(scope(@form, h, "ben"), solo, {:give, ana})
          # WI-086: giving an item away waits for the receiver's agreement
          assert {:error, _, :still_owner, _} = Households.leave(scope(@form, h, "ben"))
          {:ok, _} = Items.consent(scope(@form, h, "ana"), B1.pid(@form, h, "ana", solo))
          {:ok, _} = Items.let_go(scope(@form, h, "ben"), v, :delete)

          assert {:ok, _} = Households.leave(scope(@form, h, "ben"))
          assert B1.owners(@form, h, "ana", solo) == [ana]
        end
      end

      describe "REQ-111" do
        test "REQ-111 AC-1: a value is an item of kind value, in the member's words, owned by them alone" do
          h = household(@form, ~w(ana ben))
          ana = id(@form, h, "ana")
          {:ok, saved} = Values.add_value(scope(@form, h, "ana"), "  a home that feels safe ")
          v = B1.find_label(saved.household, "a home that feels safe")

          assert {:ok, %{owners: [^ana], attrs: %{kind: :value, label: "a home that feels safe"}}} =
                   Items.get(scope(@form, h, "ana"), v)

          assert Values.value?(Items.lookup(scope(@form, h, "ana"), v))
          refute reads?(@form, h, "ben", v)
        end

        test "REQ-111 AC-2: only a member can create a value" do
          {h, zed_scope, _} = B1.with_former(@form, ~w(ana))
          assert {:error, _, :not_a_member, _} = Values.add_value(zed_scope, "freedom")
          assert stored(@form, h).items == %{}
        end

        test "REQ-111 AC-3: values follow the item rules (grants, owner changes, history, deletion, export, departure)" do
          h = household(@form, ~w(ana ben cy))
          [ana, ben, cy] = Enum.map(~w(ana ben cy), &id(@form, h, &1))
          v = B1.add_value(@form, h, "ana", "home")

          # owner set and grants
          assert {:error, _, :no_owners, _} = Items.propose_owners(scope(@form, h, "ana"), v, [])
          assert {:error, _, :not_found, _} = Items.propose_grant(scope(@form, h, "ben"), v, cy)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), v, cy)
          assert reads?(@form, h, "cy", v)
          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), v, cy)
          refute reads?(@form, h, "cy", v)

          # owner changes, then the history
          {:ok, _} = Items.propose_owners(scope(@form, h, "ana"), v, Enum.sort([ana, ben]))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", v))
          {:ok, entries} = Items.ledger(scope(@form, h, "ben"), v)

          assert Enum.map(entries, & &1.event) ==
                   [:created, :granted, :grant_revoked, :owners_changed]

          # export: each owner takes it
          for {n, m} <- [{"ana", ana}, {"ben", ben}] do
            e = Portability.export(scope(@form, h, n))
            assert e.member == m
            assert [%{id: ^v}] = e.items
          end

          # departure: an owner is refused; relinquishing lets them leave
          assert {:error, _, :still_owner, _} = Households.leave(scope(@form, h, "ben"))
          assert {:error, _, :not_sole_owner, _} = Items.delete(scope(@form, h, "ana"), v)
          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), v)
          assert {:ok, _} = Households.leave(scope(@form, h, "ben"))

          # deletion
          {:ok, _} = Items.delete(scope(@form, h, "ana"), v)
          assert Items.visible(scope(@form, h, "ana")) == []
        end

        test "REQ-111 AC-4: a new household contains no items, so no values, for any member" do
          names = ~w(ana ben cy)
          h = household(@form, names)
          assert stored(@form, h).items == %{}

          for n <- names do
            s = scope(@form, h, n)
            assert Items.visible(s) == []
            assert Items.all(s) == %{}
            assert Values.distribution(s).by_value == %{}
            assert Portability.export(s).items == []
          end
        end
      end

      describe "REQ-114" do
        test "REQ-114 AC-1: after a revoked grant the item leaves the distribution, and items linked to a lost value count as unlinked" do
          {h, x} = B1.base114(@form)
          ben = id(@form, h, "ben")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.rent, ben)
          {:ok, _} = Values.link(scope(@form, h, "ben"), x.rent, x.bv)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.av, ben)
          {:ok, _} = Values.link(scope(@form, h, "ben"), x.bus, x.av)
          old_ben = scope(@form, h, "ben")

          assert Values.distribution(old_ben) == %{
                   by_value: %{
                     x.bv => B1.bucket(1, 0, -100_000),
                     x.av => B1.bucket(1, 0, 0, 0, -2_000)
                   },
                   unlinked: B1.bucket(0)
                 }

          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), x.rent, ben)
          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), x.av, ben)

          assert Values.distribution(Households.view(old_ben)) == %{
                   by_value: %{x.bv => B1.bucket(0)},
                   unlinked: B1.bucket(1, 0, 0, 0, -2_000)
                 }
        end

        test "REQ-114 AC-2: a relinquished joint item or shared value leaves the member's distribution" do
          {h, x} = B1.base114(@form)
          both = B1.ids(@form, h, ~w(ana ben))
          {:ok, _} = Items.propose_owners(scope(@form, h, "ana"), x.rent, both)
          # WI-086: ben agrees to own the rent too
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", x.rent))
          {:ok, _} = Items.propose_owners(scope(@form, h, "ana"), x.av, both)
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", x.av))
          {:ok, _} = Values.link(scope(@form, h, "ben"), x.rent, x.av)

          assert Map.keys(Values.distribution(scope(@form, h, "ben")).by_value) |> Enum.sort() ==
                   Enum.sort([x.av, x.bv])

          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), x.rent)
          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), x.av)

          assert Values.distribution(scope(@form, h, "ben")) == %{
                   by_value: %{x.bv => B1.bucket(0)},
                   unlinked: B1.bucket(1, 0, 0, 0, -2_000)
                 }
        end

        test "REQ-114 AC-3: an item or value the owner deletes leaves the member's distribution" do
          {h, x} = B1.base114(@form)
          ben = id(@form, h, "ben")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.rent, ben)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.av, ben)
          {:ok, _} = Values.link(scope(@form, h, "ben"), x.rent, x.av)
          old_ben = scope(@form, h, "ben")
          assert %{by_value: %{} = bv} = Values.distribution(old_ben)
          assert Map.has_key?(bv, x.av)

          {:ok, _} = Items.delete(scope(@form, h, "ana"), x.rent)
          {:ok, _} = Items.delete(scope(@form, h, "ana"), x.av)

          assert Values.distribution(Households.view(old_ben)) == %{
                   by_value: %{x.bv => B1.bucket(0)},
                   unlinked: B1.bucket(1, 0, 0, 0, -2_000)
                 }
        end

        test "REQ-114 AC-4: a member who leaves has an empty distribution and no links" do
          {h, x} = B1.base114(@form)
          ben = id(@form, h, "ben")
          {:ok, _} = Items.delete(scope(@form, h, "ben"), x.bus)
          {:ok, _} = Items.delete(scope(@form, h, "ben"), x.bv)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.rent, ben)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.av, ben)
          {:ok, _} = Values.link(scope(@form, h, "ben"), x.rent, x.av)
          assert [_] = Values.links(scope(@form, h, "ben"))

          left = ok!(Households.leave(scope(@form, h, "ben")))

          assert Values.distribution(left) == %{by_value: %{}, unlinked: B1.bucket(0)}
          assert Values.links(left) == []
          refute Map.has_key?(stored(@form, h).personal, ben)
        end

        for c <- [
              :revoke_item,
              :revoke_value,
              :relinquish_item,
              :relinquish_value,
              :delete_item,
              :delete_value
            ] do
          @tag b1_cause: c
          test "REQ-114 AC-5: after #{c}, everything returned to the member is as if they never had it",
               %{b1_cause: c} do
            {h, x} = B1.base114(@form)
            {share, lose, probes} = B1.cause(c, @form, h, x)
            never = B1.seen(scope(@form, h, "ben"), probes)

            share.()
            had = B1.seen(scope(@form, h, "ben"), probes)
            assert [_] = had.links
            refute had.distribution == never.distribution

            {:ok, _} = lose.()
            assert B1.seen(scope(@form, h, "ben"), probes) == never
          end
        end

        test "REQ-114 AC-5: after departure, everything returned to the member is as if they never had it" do
          # ben is given sight and links; cy, the counterfactual, never is; both then leave
          {h, x} = B1.base114(@form)
          ben = id(@form, h, "ben")
          {:ok, _} = Items.delete(scope(@form, h, "ben"), x.bus)
          {:ok, _} = Items.delete(scope(@form, h, "ben"), x.bv)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.rent, ben)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.av, ben)
          {:ok, _} = Values.link(scope(@form, h, "ben"), x.rent, x.av)
          assert [_] = Values.links(scope(@form, h, "ben"))

          refute B1.seen(scope(@form, h, "ben")).distribution ==
                   B1.seen(scope(@form, h, "cy")).distribution

          seen = fn name ->
            Households.leave(scope(@form, h, name))
            |> ok!()
            |> B1.seen()
            |> put_in([:export, :member], :me)
          end

          ben_seen = seen.("ben")
          cy_seen = seen.("cy")
          assert ben_seen == %{cy_seen | deletions: ben_seen.deletions}
          assert ben_seen.deletions == []
        end

        test "REQ-114 AC-6: a link to something no longer visible appears in and changes nothing" do
          {h, x} = B1.base114(@form)
          ben = id(@form, h, "ben")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), x.rent, ben)
          {:ok, _} = Values.link(scope(@form, h, "ben"), x.rent, x.bv)
          {:ok, _} = Values.link(scope(@form, h, "ben"), x.bus, x.bv)
          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), x.rent, ben)

          s = scope(@form, h, "ben")
          assert Values.links(s) == [{x.bus, x.bv}]
          assert Values.distribution(s).by_value == %{x.bv => B1.bucket(1, 0, 0, 0, -2_000)}
          assert Portability.export(s).links == [{x.bus, x.bv}]
          refute Enum.any?(Portability.export(s).items, &(&1.id == x.rent))
          # answers as for an item that doesn't exist, not "already linked"
          assert {:error, _, :not_found, _} = Values.link(s, x.rent, x.bv)
          assert {:error, _, :not_found, _} = Values.unlink(s, x.rent, x.bv)
          assert {:error, _, :not_found, _} = Values.link(s, "b1-missing", x.bv)
        end
      end

      describe "REQ-115" do
        test "REQ-115 AC-1: adding a member to a value needs that member's own consent" do
          h = household(@form, ~w(ana ben))
          v = B1.add_value(@form, h, "ana", "home")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana ben)))

          assert B1.owners(@form, h, "ana", v) == B1.ids(@form, h, ~w(ana))
          refute Items.visible?(scope(@form, h, "ben"), v)
        end

        test "REQ-115 AC-2: the joiner can't consent before every current owner has" do
          h = household(@form, ~w(ana ben cy))
          v = B1.shared_value(@form, h, "ana", ~w(ben), "home")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana ben cy)))

          p = B1.pid(@form, h, "ana", v)
          assert {:error, _, :not_found, _} = Items.consent(scope(@form, h, "cy"), p)
          assert B1.owners(@form, h, "ana", v) == B1.ids(@form, h, ~w(ana ben))
        end

        test "REQ-115 AC-3: the joiner sees the proposal, with the value, only once every owner consented" do
          h = household(@form, ~w(ana ben cy))
          cy = id(@form, h, "cy")
          v = B1.shared_value(@form, h, "ana", ~w(ben), "home")
          old_cy = scope(@form, h, "cy")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana ben cy)))

          p = B1.pid(@form, h, "ana", v)
          s = Households.view(old_cy)
          assert Items.pending(s) == []
          assert Items.lookup(s, v).attrs == %{}
          refute cy in B1.sealed_to(@form, h, v)

          {:ok, _} = Items.consent(scope(@form, h, "ben"), p)

          s = Households.view(old_cy)
          assert [%{id: ^p, attrs: %{kind: :value, label: "home"}}] = Items.pending(s)
          assert %{kind: :value, label: "home"} = Items.lookup(s, v).attrs
          assert %{item_id: ^v} = Items.proposal(s, p)
        end

        test "REQ-115 AC-4: the joiner may then consent and becomes an owner" do
          h = household(@form, ~w(ana ben))
          v = B1.add_value(@form, h, "ana", "home")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana ben)))

          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", v))
          assert B1.owners(@form, h, "ben", v) == B1.ids(@form, h, ~w(ana ben))
          assert {:ok, [_, _]} = Items.ledger(scope(@form, h, "ben"), v)
        end

        test "REQ-115 AC-5: without the joiner's consent they are not an owner and the value is unchanged" do
          h = household(@form, ~w(ana ben))
          v = B1.add_value(@form, h, "ana", "home")
          {:ok, before} = Items.get(scope(@form, h, "ana"), v)

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana ben)))

          assert [%{item_id: ^v}] = Items.pending(scope(@form, h, "ben"))
          assert Items.get(scope(@form, h, "ana"), v) == {:ok, before}
          assert Items.get(scope(@form, h, "ben"), v) == {:error, :not_found}
          assert {:ok, [_]} = Items.ledger(scope(@form, h, "ana"), v)
        end

        test "REQ-115 AC-6: every kind of item needs the joiner's own agreement too (WI-086, CP-029)" do
          h = household(@form, ~w(ana ben))
          ben = id(@form, h, "ben")
          item = add_item(@form, h, "ana", "Rent")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), item, B1.ids(@form, h, ~w(ana ben)))

          # not an owner yet: ben is asked, and sees what he's asked to own
          assert [%{id: p, attrs: %{note: "Rent"}}] = Items.pending(scope(@form, h, "ben"))
          refute ben in Households.view(scope(@form, h, "ana")).household.items[item].owners

          {:ok, _} = Items.consent(scope(@form, h, "ben"), p)
          assert B1.owners(@form, h, "ben", item) == B1.ids(@form, h, ~w(ana ben))
          assert Items.pending(scope(@form, h, "ben")) == []
        end
      end

      describe "REQ-116" do
        test "REQ-116 AC-1: each participant, creator or joiner, withdraws alone while another remains" do
          h = household(@form, ~w(ana ben cy))
          v = B1.shared_value(@form, h, "ana", ~w(ben cy), "home")
          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), v)
          assert B1.owners(@form, h, "ana", v) == B1.ids(@form, h, ~w(ana cy))
          {:ok, _} = Items.relinquish(scope(@form, h, "ana"), v)
          assert B1.owners(@form, h, "cy", v) == B1.ids(@form, h, ~w(cy))
          refute reads?(@form, h, "ana", v) or reads?(@form, h, "ben", v)
        end

        test "REQ-116 AC-2: the last participant deletes the value alone" do
          h = household(@form, ~w(ana ben))
          v = B1.shared_value(@form, h, "ana", ~w(ben), "home")
          {:ok, _} = Items.relinquish(scope(@form, h, "ana"), v)
          assert {:error, _, :sole_owner, _} = Items.relinquish(scope(@form, h, "ben"), v)
          assert {:ok, _} = Items.delete(scope(@form, h, "ben"), v)
          refute Map.has_key?(stored(@form, h).items, v)
        end
      end

      describe "REQ-119" do
        test "REQ-119 AC-3: the item key is sealed to exactly the current owners and grantees" do
          h = household(@form, ~w(ana ben cy))
          [ana, ben, cy] = Enum.map(~w(ana ben cy), &id(@form, h, &1))
          item = add_item(@form, h, "ana", "Rent")
          sealed = fn -> B1.sealed_to(@form, h, item) end
          assert sealed.() == [ana]

          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, ben)
          assert sealed.() == Enum.sort([ana, ben])
          assert reads?(@form, h, "ben", item)

          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), item, ben)
          assert sealed.() == [ana]
          refute reads?(@form, h, "ben", item)

          {:ok, _} = Items.propose_owners(scope(@form, h, "ana"), item, Enum.sort([ana, ben]))

          # WI-086: sealed to ben as soon as the owner agrees, so he can see what he's asked to own
          assert sealed.() == Enum.sort([ana, ben])
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", item))
          assert sealed.() == Enum.sort([ana, ben])

          {:ok, _} = Items.relinquish(scope(@form, h, "ben"), item)
          assert sealed.() == [ana]
          refute reads?(@form, h, "ben", item)

          # removed from the owners by agreement
          {:ok, _} = Items.propose_owners(scope(@form, h, "ana"), item, Enum.sort([ana, ben]))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), B1.pid(@form, h, "ben", item))
          {:ok, _} = Items.propose_owners(scope(@form, h, "ben"), item, [ben])
          {:ok, _} = Items.consent(scope(@form, h, "ana"), B1.pid(@form, h, "ana", item))
          assert sealed.() == [ben]
          refute reads?(@form, h, "ana", item)

          # leaving the household
          {:ok, _} = Items.propose_grant(scope(@form, h, "ben"), item, cy)
          assert sealed.() == Enum.sort([ben, cy])
          {:ok, _} = Households.leave(scope(@form, h, "cy"))
          assert sealed.() == [ben]
        end

        test "REQ-119 AC-4: a value's prospective joiner gets the key once every owner consented, and loses it on withdrawal" do
          h = household(@form, ~w(ana ben cy))
          cy = id(@form, h, "cy")
          v = B1.shared_value(@form, h, "ana", ~w(ben), "home")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana ben cy)))

          p = B1.pid(@form, h, "ana", v)
          refute cy in B1.sealed_to(@form, h, v)
          assert Items.lookup(scope(@form, h, "cy"), v).attrs == %{}

          {:ok, _} = Items.consent(scope(@form, h, "ben"), p)
          assert cy in B1.sealed_to(@form, h, v)
          assert %{label: "home"} = Items.lookup(scope(@form, h, "cy"), v).attrs

          {:ok, _} = Items.withdraw(scope(@form, h, "ana"), p)
          refute cy in B1.sealed_to(@form, h, v)
          assert Items.lookup(scope(@form, h, "cy"), v).attrs == %{}
          assert B1.sealed_to(@form, h, v) == B1.ids(@form, h, ~w(ana ben))
        end

        test "REQ-119 AC-5: no other member holds the item key or can open the content" do
          h = household(@form, ~w(ana ben cy))
          item = add_item(@form, h, "ana", "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, id(@form, h, "ben"))

          assert B1.sealed_to(@form, h, item) == B1.ids(@form, h, ~w(ana ben))
          s = Households.view(scope(@form, h, "cy"))
          assert Items.lookup(s, item).attrs == %{}
          assert Items.get(s, item) == {:error, :not_found}
          assert Enum.all?(Households.view(s).household.ledger[item] || [], &(&1 == :sealed))
        end
      end

      describe "REQ-121" do
        test "REQ-121 AC-3: links and deletion records are in the member's own sealed record; no other member opens it" do
          h = household(@form, ~w(ana ben))
          [ana, ben] = Enum.map(~w(ana ben), &id(@form, h, &1))
          item = add_item(@form, h, "ana", "Rent")
          v = B1.add_value(@form, h, "ana", "home")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, ben)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), v, ben)
          ben_box = stored(@form, h).personal[ben]
          ana_box = stored(@form, h).personal[ana]

          {:ok, _} = Values.link(scope(@form, h, "ana"), item, v)
          other = add_item(@form, h, "ana", "Books")
          {:ok, _} = Items.delete(scope(@form, h, "ana"), other)

          personal = stored(@form, h).personal
          refute personal[ana] == ana_box
          assert personal[ben] == ben_box

          assert Values.links(scope(@form, h, "ana")) == [{item, v}]
          bh = view(@form, h, "ben")
          assert Values.links(scope(@form, h, "ben")) == []
          assert Map.keys(bh.links) -- [ben] == []
          assert Map.keys(bh.deletions) -- [ben] == []
          assert Findependence.Ledger.deletions(bh, ben) == []
        end
      end

      describe "REQ-125" do
        test "REQ-125 AC-1: the proposer withdraws a pending proposal" do
          h = household(@form, ~w(ana ben))
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          {:ok, _} = change_owners(@form, h, "ana", item, ~w(ana))
          p = B1.pid(@form, h, "ana", item)

          assert {:ok, _} = Items.withdraw(scope(@form, h, "ana"), p)
          assert Items.pending(scope(@form, h, "ben")) == []
          assert {:error, _, :not_found, _} = Items.consent(scope(@form, h, "ben"), p)
        end

        test "REQ-125 AC-2: any current owner, including one added after, withdraws; nobody else can" do
          h = household(@form, ~w(ana ben cy dan))
          dan = id(@form, h, "dan")
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, dan)
          [grant] = B1.pending_on(@form, h, "ana", item)

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ben"), item, B1.ids(@form, h, ~w(ana ben cy)))

          add = Enum.find(B1.pending_on(@form, h, "ana", item), &(&1.id != grant.id))
          {:ok, _} = Items.consent(scope(@form, h, "ana"), add.id)
          # WI-086: cy agrees to become an owner
          {:ok, _} = Items.consent(scope(@form, h, "cy"), add.id)
          assert B1.owners(@form, h, "cy", item) == B1.ids(@form, h, ~w(ana ben cy))

          assert {:error, _, :not_found, _} = Items.withdraw(scope(@form, h, "dan"), grant.id)
          assert {:ok, _} = Items.withdraw(scope(@form, h, "cy"), grant.id)
          assert Items.pending(scope(@form, h, "ana")) == []

          # a value's prospective joiner can't withdraw the invitation
          v = B1.add_value(@form, h, "ana", "home")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), v, B1.ids(@form, h, ~w(ana dan)))

          invite = B1.pid(@form, h, "dan", v)
          assert {:error, _, :not_found, _} = Items.withdraw(scope(@form, h, "dan"), invite)
          assert {:error, _, :not_found, _} = Items.withdraw(scope(@form, h, "ben"), invite)
          assert [%{id: ^invite}] = Items.pending(scope(@form, h, "dan"))
        end

        test "REQ-125 AC-3: withdrawing removes that proposal only and changes nothing else" do
          h = household(@form, ~w(ana ben cy))
          cy = id(@form, h, "cy")
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, cy)
          {:ok, _} = change_owners(@form, h, "ben", item, ~w(ben))
          [a, b] = B1.pending_on(@form, h, "ana", item)
          st = stored(@form, h)
          {:ok, got} = Items.get(scope(@form, h, "ana"), item)
          {:ok, ledger} = Items.ledger(scope(@form, h, "ana"), item)

          {:ok, _} = Items.withdraw(scope(@form, h, "ben"), a.id)

          assert B1.pending_on(@form, h, "ana", item) == [b]
          assert Items.get(scope(@form, h, "ana"), item) == {:ok, got}
          assert Items.ledger(scope(@form, h, "ana"), item) == {:ok, ledger}
          after_ = stored(@form, h)
          assert after_.proposals == Map.delete(st.proposals, a.id)
          assert after_.items == st.items
          assert after_.members == st.members
        end

        test "REQ-125 AC-4: the proposer of each pending proposal is a current owner, so can always withdraw it" do
          h = household(@form, ~w(ana ben cy))
          [ana, ben, cy] = Enum.map(~w(ana ben cy), &id(@form, h, &1))

          invariant = fn ->
            st = stored(@form, h)

            for {pid, p} <- st.proposals do
              assert p.proposed_by in st.items[p.item_id].owners, "proposal #{pid}"
            end

            st
          end

          # a proposer who agrees to leave the owners loses their pending proposals on the item
          item = B1.joint(@form, h, "ana", ~w(ben), "Rent")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, cy)
          [grant] = B1.pending_on(@form, h, "ana", item)
          {:ok, _} = Items.propose_owners(scope(@form, h, "ben"), item, [ben])
          invariant.()
          leave = Enum.find(B1.pending_on(@form, h, "ana", item), &(&1.id != grant.id))
          {:ok, _} = Items.consent(scope(@form, h, "ana"), leave.id)
          invariant.()
          assert Items.pending(scope(@form, h, "ben")) == []
          assert {:error, _, :not_found, _} = Items.consent(scope(@form, h, "ben"), grant.id)

          # relinquishing drops the relinquisher's proposals and those that would restore them
          j = B1.joint(@form, h, "ana", ~w(ben), "Car")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), j, cy)
          {:ok, _} = Items.propose_owners(scope(@form, h, "ben"), j, Enum.sort([ana, ben, cy]))
          invariant.()
          {:ok, _} = Items.relinquish(scope(@form, h, "ana"), j)
          invariant.()
          assert Items.pending(scope(@form, h, "ben")) == []

          # a proposer who is still an owner can withdraw each of their pending proposals
          k = B1.joint(@form, h, "ben", ~w(cy), "Bus")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ben"), k, ana)
          {:ok, _} = Items.propose_owners(scope(@form, h, "cy"), k, [cy])
          st = invariant.()
          assert map_size(st.proposals) == 2

          for {pid, p} <- st.proposals do
            by = Enum.find(~w(ana ben cy), &(id(@form, h, &1) == p.proposed_by))
            assert {:ok, _} = Items.withdraw(scope(@form, h, by), pid)
          end

          assert stored(@form, h).proposals == %{}
        end
      end

      describe "REQ-128" do
        test "REQ-128 AC-1: only items visible to the member are counted" do
          h = household(@form, ~w(ana ben))
          add_item(@form, h, "ana", "Books", amount: 20, frequency: :one_off)
          secret = add_item(@form, h, "ben", "Secret", amount: -500, frequency: :one_off)
          assert Values.distribution(scope(@form, h, "ana")).unlinked == B1.bucket(1, 0, 0, 20)

          {:ok, _} = Items.propose_grant(scope(@form, h, "ben"), secret, id(@form, h, "ana"))

          assert Values.distribution(scope(@form, h, "ana")).unlinked ==
                   B1.bucket(2, 0, 0, 20, -500)
        end

        test "REQ-128 AC-2: only the member's own links are used" do
          h = household(@form, ~w(ana ben))
          ana = id(@form, h, "ana")
          rent = B1.joint(@form, h, "ana", ~w(ben), "Rent", amount: -100, frequency: :one_off)
          bv = B1.add_value(@form, h, "ben", "freedom")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ben"), bv, ana)
          {:ok, _} = Values.link(scope(@form, h, "ben"), rent, bv)

          assert Values.distribution(scope(@form, h, "ana")) == %{
                   by_value: %{bv => B1.bucket(0)},
                   unlinked: B1.bucket(1, 0, 0, 0, -100)
                 }

          assert Values.distribution(scope(@form, h, "ben")).by_value == %{
                   bv => B1.bucket(1, 0, 0, 0, -100)
                 }
        end

        test "REQ-128 AC-3: one bucket per visible value plus an unlinked remainder, and nothing else" do
          h = household(@form, ~w(ana ben))
          v1 = B1.add_value(@form, h, "ana", "home")
          v2 = B1.add_value(@form, h, "ana", "learning")
          hidden = B1.add_value(@form, h, "ben", "private")
          shared = B1.add_value(@form, h, "ben", "shared")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ben"), shared, id(@form, h, "ana"))

          {:ok, _} =
            Balances.add_account(scope(@form, h, "ana"), "b1-acct", "Checking", :checking)

          add_item(@form, h, "ana", "Rent", amount: -100, frequency: :one_off)

          d = Values.distribution(scope(@form, h, "ana"))
          assert Enum.sort(Map.keys(d)) == [:by_value, :unlinked]
          assert Enum.sort(Map.keys(d.by_value)) == Enum.sort([v1, v2, shared])
          refute Map.has_key?(d.by_value, hidden)
          assert d.unlinked == B1.bucket(1, 0, 0, 0, -100)
        end

        test "REQ-128 AC-4: each bucket reports the number of items counted" do
          h = household(@form, ~w(ana))
          v = B1.add_value(@form, h, "ana", "home")

          for n <- 1..3 do
            i = add_item(@form, h, "ana", "Item #{n}", amount: -10 * n, frequency: :one_off)
            if n < 3, do: {:ok, _} = Values.link(scope(@form, h, "ana"), i, v)
          end

          add_item(@form, h, "ana", "No amount", amount: nil, frequency: :one_off)
          d = Values.distribution(scope(@form, h, "ana"))
          assert d.by_value[v].count == 2
          assert d.unlinked.count == 2
        end

        test "REQ-128 AC-5: per-month sums of in and out over recurring items, each rounded before summing" do
          h = household(@form, ~w(ana))
          v = B1.add_value(@form, h, "ana", "home")

          # 6 a year is 0.5 a month, rounded to 1 each: 2, not round(12 / 12) = 1
          for {note, amount, f} <- [
                {"A", 6, {:every, 1, :year}},
                {"B", 6, {:every, 1, :year}},
                {"C", -3_250, {:every, 1, :week}},
                {"D", -215_000, {:every, 1, :month}},
                {"E", 148_000, {:every, 2, :week}}
              ] do
            i = add_item(@form, h, "ana", note, amount: amount, frequency: f)
            {:ok, _} = Values.link(scope(@form, h, "ana"), i, v)
          end

          # -3250 x 52/12 = -14083.33 -> -14083; 148000 x 26/12 = 320666.67 -> 320667
          assert Values.distribution(scope(@form, h, "ana")).by_value[v] ==
                   B1.bucket(5, 2 + 320_667, -14_083 - 215_000)
        end

        test "REQ-128 AC-6: the per-month conversion of every kind of frequency" do
          h = household(@form, ~w(ana))

          cases = [
            {{:every, 1, :week}, 3, 13},
            {{:every, 2, :week}, 148_000, 320_667},
            {{:every, 4, :week}, 10_000, 10_833},
            {{:every, 1, :month}, -215_000, -215_000},
            {{:every, 2, :month}, 12_000, 6_000},
            {{:every, 3, :month}, 30_000, 10_000},
            {{:every, 6, :month}, 45_000, 7_500},
            {{:every, 1, :year}, -90_001, -7_500},
            {{:every, 2, :year}, 24_001, 1_000},
            {:irregular, -90_000, -7_500},
            {:monthly, 12_345, 12_345},
            {:yearly, 6, 1}
          ]

          for {{f, amount, want}, n} <- Enum.with_index(cases) do
            v = B1.add_value(@form, h, "ana", "value #{n}")
            i = add_item(@form, h, "ana", "Item #{n}", amount: amount, frequency: f)
            {:ok, _} = Values.link(scope(@form, h, "ana"), i, v)
            assert CashFlow.per_month(amount, f) == want, inspect(f)
            bucket = Values.distribution(scope(@form, h, "ana")).by_value[v]
            side = if want > 0, do: :in, else: :out
            assert bucket.per_month[side] == want, inspect(f)
            assert bucket.one_off == %{in: 0, out: 0}
          end
        end

        test "REQ-128 AC-7: one-off money in and out are summed separately" do
          h = household(@form, ~w(ana))
          add_item(@form, h, "ana", "Gift", amount: 5_000, frequency: :one_off)
          add_item(@form, h, "ana", "Couch", amount: -64_999, frequency: :one_off)
          add_item(@form, h, "ana", "Bonus", amount: 1_000, frequency: :one_off)
          add_item(@form, h, "ana", "Rent", amount: -100, frequency: {:every, 1, :month})

          assert Values.distribution(scope(@form, h, "ana")).unlinked ==
                   B1.bucket(4, 0, -100, 6_000, -64_999)
        end

        test "REQ-128 AC-8: an item with an unrecognized frequency counts as one-off" do
          h = household(@form, ~w(ana))

          for f <- [{:every, 0, :month}, {:every, 2, :day}, {:every, 1.5, :month}, :fortnightly] do
            add_item(@form, h, "ana", "Odd #{inspect(f)}", amount: -10, frequency: f)
          end

          assert Values.distribution(scope(@form, h, "ana")).unlinked ==
                   B1.bucket(4, 0, 0, 0, -40)
        end

        test "REQ-128 AC-9: buckets hold only count, per-month in/out, and one-off in/out" do
          h = household(@form, ~w(ana))
          v = B1.add_value(@form, h, "ana", "home")
          i = add_item(@form, h, "ana", "Rent", amount: -100, frequency: {:every, 1, :month})
          {:ok, _} = Values.link(scope(@form, h, "ana"), i, v)
          add_item(@form, h, "ana", "Gift", amount: 50, frequency: :one_off)

          d = Values.distribution(scope(@form, h, "ana"))
          assert Enum.sort(Map.keys(d)) == [:by_value, :unlinked]

          for b <- [d.unlinked | Map.values(d.by_value)] do
            assert Enum.sort(Map.keys(b)) == [:count, :one_off, :per_month]
            assert Enum.sort(Map.keys(b.per_month)) == [:in, :out]
            assert Enum.sort(Map.keys(b.one_off)) == [:in, :out]
            assert is_integer(b.count)
          end
        end
      end
    end
  end
end
