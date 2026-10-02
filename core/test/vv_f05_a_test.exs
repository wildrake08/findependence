defmodule Findependence.VVF05ATest do
  @moduledoc """
  WI-057 (VV-001 F-05, F-08), batch A: tests for acceptance criteria of REQ-101, 103, 107, 108, 110,
  111, 114, 125, 134, 167, 168, and 169 that no earlier test asserted. The criteria are in
  project/assurance/vv/acceptance-a.yaml.
  """
  use ExUnit.Case, async: true
  import Findependence.TestJoint

  alias Findependence.{
    Alignment,
    Attach,
    Balances,
    Exit,
    Household,
    Ledger,
    Plans,
    Retirement,
    View
  }

  defp ok!({:ok, h}), do: h
  defp ok!({:ok, h, _}), do: h

  defp bucket(count, pm_in \\ 0, pm_out \\ 0, one_in \\ 0, one_out \\ 0),
    do: %{
      count: count,
      per_month: %{in: pm_in, out: pm_out},
      one_off: %{in: one_in, out: one_out}
    }

  # One item of every kind, created by :a: money in or out, a value, an account, a debt, a shared plan.
  defp every_kind do
    h = Household.new([:a, :b, :c])
    {:ok, h} = Household.add_item(h, :a, :money, %{amount: -100})
    {:ok, h} = Alignment.add_value(h, :a, :value, "home")
    {:ok, h} = Balances.add_account(h, :a, :account, "Checking", :checking)
    {:ok, h} = Balances.add_debt(h, :a, :debt, "Visa", :card)
    {:ok, h} = Plans.new_plan(h, :a, :p, "Plan")
    {:ok, h, _} = Plans.propose_shared(h, :a, :p, :plan, [:b])
    h
  end

  @kinds [:money, :value, :account, :debt, :plan]

  describe "REQ-101" do
    test "every kind of item starts owned by its creator; an empty or non-member owner set is refused, and the last owner can't leave it ownerless" do
      h = every_kind()

      for id <- @kinds do
        assert h.items[id].owners == MapSet.new([:a]), inspect(id)
        assert {:error, :no_owners} = Household.propose_owners(h, :a, id, [])
        assert {:error, :not_a_member} = Household.propose_owners(h, :a, id, [:a, :x])
        assert {:error, :sole_owner} = Household.relinquish(h, :a, id)
      end

      assert {:error, :still_owner} = Exit.leave(h, :a)
    end
  end

  describe "REQ-103" do
    test "a grantee, an unrelated member, and a non-member can neither create nor revoke a grant" do
      {:ok, h} = Household.add_item(Household.new([:a, :b, :c, :d]), :a, :i, %{amount: 1})
      {:ok, h, _} = Household.propose_grant(h, :a, :i, :b)

      for x <- [:b, :c, :x] do
        assert {:error, :not_found} = Household.propose_grant(h, x, :i, :d), inspect(x)
        assert {:error, :not_found} = Household.revoke_grant(h, x, :i, :b), inspect(x)
      end

      assert h.proposals == %{}
      assert View.visible?(h, :b, :i)
      refute View.visible?(h, :d, :i)
    end

    test "with three owners a grant waits for the last one; then any one of them revokes it alone" do
      {:ok, h} = Household.add_item(Household.new([:a, :b, :c, :d]), :a, :i, %{amount: 1})
      h = joint!(h, :a, :i, [:a, :b, :c])
      {:ok, h, pid} = Household.propose_grant(h, :b, :i, :d)
      {:ok, h} = Household.consent(h, :a, pid)
      refute View.visible?(h, :d, :i), "applied before :c consented"
      {:ok, h} = Household.consent(h, :c, pid)
      assert View.visible?(h, :d, :i)

      for o <- [:a, :b, :c] do
        {:ok, h2} = Household.revoke_grant(h, o, :i, :d)
        refute View.visible?(h2, :d, :i)
      end
    end
  end

  describe "REQ-107" do
    test "a grantee or a non-member can't propose making themselves an owner" do
      {:ok, h} = Household.add_item(Household.new([:a, :b, :c]), :a, :i, %{})
      {:ok, h, _} = Household.propose_grant(h, :a, :i, :c)

      assert {:error, :not_found} = Household.propose_owners(h, :c, :i, [:a, :c])
      assert {:error, :not_found} = Household.propose_owners(h, :c, :i, [:c])
      assert {:error, :not_found} = Household.propose_owners(h, :x, :i, [:a, :x])
      assert h.proposals == %{}
      assert {:ok, %{owners: [:a]}} = View.get(h, :a, :i)
    end
  end

  describe "REQ-108" do
    test "deleting a sole-owned value removes its pending invitation, and a reused id inherits none" do
      {:ok, h} = Alignment.add_value(Household.new([:a, :b]), :a, :v, "home")
      {:ok, h, invite} = Household.propose_owners(h, :a, :v, [:a, :b])
      assert [%{id: ^invite}] = Household.pending(h, :b)

      {:ok, h} = Exit.delete(h, :a, :v)
      assert h.proposals == %{}
      assert Household.pending(h, :a) == [] and Household.pending(h, :b) == []
      assert {:error, :not_found} = Household.consent(h, :b, invite)
      assert {:error, :not_found} = Household.withdraw(h, :a, invite)

      {:ok, h} = Alignment.add_value(h, :a, :v, "something else")
      assert Household.pending(h, :b) == []
      assert {:error, :not_found} = Household.consent(h, :b, invite)
      assert {:ok, %{owners: [:a]}} = View.get(h, :a, :v)
    end

    test "a pending grant left from joint ownership goes when the remaining sole owner deletes" do
      {:ok, h} = Household.add_item(Household.new([:a, :b, :c]), :a, :i, %{amount: 1})
      h = joint!(h, :a, :i, [:a, :b])
      {:ok, h, grant} = Household.propose_grant(h, :a, :i, :c)
      {:ok, h} = Household.relinquish(h, :b, :i)
      assert [%{id: ^grant}] = Household.pending(h, :a)

      {:ok, h} = Exit.delete(h, :a, :i)
      assert h.proposals == %{}
      assert Household.pending(h, :a) == []
      assert {:error, :not_found} = Household.consent(h, :a, grant)
      refute View.visible?(h, :c, :i)
    end
  end

  describe "REQ-110" do
    test "leaving drops every pending proposal that would make the leaver an owner, and no other" do
      h = Household.new([:a, :b, :c])
      {:ok, h} = Alignment.add_value(h, :a, :v, "home")
      {:ok, h, invite} = Household.propose_owners(h, :a, :v, [:a, :c])
      {:ok, h} = Household.add_item(h, :a, :i, %{amount: 1})
      h = joint!(h, :a, :i, [:a, :b])
      {:ok, h, add_c} = Household.propose_owners(h, :a, :i, [:a, :b, :c])
      {:ok, h, keep} = Household.propose_owners(h, :b, :i, [:b])
      assert Enum.sort(Map.keys(h.proposals)) == Enum.sort([invite, add_c, keep])

      {:ok, h} = Exit.leave(h, :c)
      assert Map.keys(h.proposals) == [keep]
      assert {:error, :not_found} = Household.consent(h, :c, invite)
    end

    test "a sole owner is refused until they transfer or delete; then they leave alone" do
      {:ok, h} = Household.add_item(Household.new([:a, :b]), :a, :i, %{})
      {:ok, h} = Alignment.add_value(h, :a, :v, "home")
      assert {:error, :still_owner} = Exit.leave(h, :a)

      h = joint!(h, :a, :i, [:b])
      assert {:ok, %{owners: [:b]}} = View.get(h, :b, :i)
      assert {:error, :still_owner} = Exit.leave(h, :a)

      {:ok, h} = Exit.delete(h, :a, :v)
      {:ok, h} = Exit.leave(h, :a)
      refute :a in h.members
    end
  end

  describe "REQ-116" do
    test "each participant of a shared value, creator or joiner, withdraws alone while another remains" do
      {:ok, h} = Alignment.add_value(Household.new([:a, :b, :c]), :a, :v, "home")
      {:ok, h, pid} = Household.propose_owners(h, :a, :v, [:a, :b, :c])
      {:ok, h} = Household.consent(h, :b, pid)
      {:ok, h} = Household.consent(h, :c, pid)

      for p <- [:a, :b, :c] do
        {:ok, h2} = Household.relinquish(h, p, :v)
        rest = List.delete([:a, :b, :c], p)
        assert {:ok, %{owners: ^rest}} = View.get(h2, hd(rest), :v)

        for q <- rest do
          {:ok, h3} = Household.relinquish(h2, q, :v)
          [last] = List.delete(rest, q)
          assert {:ok, %{owners: [^last]}} = View.get(h3, last, :v)
          assert {:ok, _} = Exit.delete(h3, last, :v)
        end
      end
    end
  end

  describe "REQ-111" do
    test "a new household has no items, so no values, for any member" do
      h = Household.new([:a, :b])
      assert h.items == %{}
      for m <- [:a, :b], do: assert(View.visible_items(h, m) == [])
    end
  end

  # REQ-114. :a owns rent and a value; :b owns a bus fare and a value. Each cause of losing sight is
  # a `share` step (which gives :b sight of something and has :b link it) and a `lose` step. The
  # counterfactual runs `cf` on the same base: the same history for everyone else, with :b never
  # having had that sight or link.
  defp base114 do
    h = Household.new([:a, :b, :c])

    {:ok, h} =
      Household.add_item(h, :a, :rent, %{amount: -100_000, frequency: {:every, 1, :month}})

    {:ok, h} = Alignment.add_value(h, :a, :av, "a's value")
    {:ok, h} = Household.add_item(h, :b, :bus, %{amount: -2_000})
    {:ok, h} = Alignment.add_value(h, :b, :bv, "b's value")
    h
  end

  defp cause(:revoke_item),
    do: {
      &(&1 |> Household.propose_grant(:a, :rent, :b) |> ok!() |> link!(:b, :rent, :bv)),
      &ok!(Household.revoke_grant(&1, :a, :rent, :b)),
      & &1
    }

  defp cause(:revoke_value),
    do: {
      &(&1 |> Household.propose_grant(:a, :av, :b) |> ok!() |> link!(:b, :bus, :av)),
      &ok!(Household.revoke_grant(&1, :a, :av, :b)),
      & &1
    }

  defp cause(:relinquish_item),
    do: {
      &(&1 |> joint!(:a, :rent, [:a, :b]) |> link!(:b, :rent, :bv)),
      &ok!(Household.relinquish(&1, :b, :rent)),
      & &1
    }

  defp cause(:relinquish_value),
    do: {
      fn h ->
        {:ok, h, pid} = Household.propose_owners(h, :a, :av, [:a, :b])
        h |> Household.consent(:b, pid) |> ok!() |> link!(:b, :bus, :av)
      end,
      &ok!(Household.relinquish(&1, :b, :av)),
      & &1
    }

  defp cause(:delete_item),
    do: {
      &(&1 |> Household.propose_grant(:a, :rent, :b) |> ok!() |> link!(:b, :rent, :bv)),
      &ok!(Exit.delete(&1, :a, :rent)),
      &ok!(Exit.delete(&1, :a, :rent))
    }

  defp cause(:delete_value),
    do: {
      &(&1 |> Household.propose_grant(:a, :av, :b) |> ok!() |> link!(:b, :bus, :av)),
      &ok!(Exit.delete(&1, :a, :av)),
      &ok!(Exit.delete(&1, :a, :av))
    }

  # :b owns nothing of their own here, so they can leave
  defp cause(:departure),
    do: {
      fn h ->
        h
        |> Exit.delete(:b, :bus)
        |> ok!()
        |> Exit.delete(:b, :bv)
        |> ok!()
        |> Household.propose_grant(:a, :rent, :b)
        |> ok!()
        |> Household.propose_grant(:a, :av, :b)
        |> ok!()
        |> link!(:b, :rent, :av)
      end,
      &ok!(Exit.leave(&1, :b)),
      fn h ->
        h
        |> Exit.delete(:b, :bus)
        |> ok!()
        |> Exit.delete(:b, :bv)
        |> ok!()
        |> Exit.leave(:b)
        |> ok!()
      end
    }

  defp link!(h, m, i, v), do: ok!(Alignment.link(h, m, i, v))

  defp shape({:ok, _}), do: :ok
  defp shape(e), do: e

  # Everything :b can learn through the core's functions, including how link and unlink answer.
  defp seen_by(h, m) do
    %{
      distribution: Alignment.distribution(h, m),
      links: Alignment.links(h, m),
      export: Exit.export(h, m),
      visible: View.visible_items(h, m),
      pending: Household.pending(h, m),
      deletions: Ledger.deletions(h, m),
      probes:
        for(
          i <- [:rent, :bus],
          v <- [:av, :bv],
          do: {i, v, shape(Alignment.link(h, m, i, v)), shape(Alignment.unlink(h, m, i, v))}
        )
    }
  end

  describe "REQ-114" do
    for c <- [
          :revoke_item,
          :revoke_value,
          :relinquish_item,
          :relinquish_value,
          :delete_item,
          :delete_value,
          :departure
        ] do
      test "after #{c}, the member sees exactly what they'd see had they never had it or linked it" do
        {share, lose, cf} = cause(unquote(c))
        shared = share.(base114())
        # not vacuous: the member did have a link that counted
        assert [_] = Alignment.links(shared, :b)
        refute seen_by(shared, :b).distribution == seen_by(cf.(base114()), :b).distribution

        assert seen_by(lose.(shared), :b) == seen_by(cf.(base114()), :b)
      end
    end
  end

  # REQ-125: a small seeded walk over the operations that change owners or proposals.
  @walk_members [:a, :b, :c, :d]
  @walk_items [:i1, :i2, :v1]

  defp walk_actor(h, item) do
    case h.items[item] do
      %{owners: o} ->
        if :rand.uniform(10) <= 7, do: Enum.random(Enum.sort(o)), else: Enum.random(@walk_members)

      nil ->
        Enum.random(@walk_members)
    end
  end

  defp random_proposal(h) do
    case Enum.sort(Map.keys(h.proposals)) do
      [] -> nil
      ids -> Enum.random(ids)
    end
  end

  defp walk_op(h) do
    item = Enum.random(@walk_items)
    actor = walk_actor(h, item)

    case :rand.uniform(12) do
      1 ->
        if item == :v1,
          do: Alignment.add_value(h, actor, :v1, "v"),
          else: Household.add_item(h, actor, item, %{amount: 1})

      n when n in 2..3 ->
        Household.propose_owners(
          h,
          actor,
          item,
          Enum.take_random(@walk_members, :rand.uniform(3))
        )

      n when n in 4..5 ->
        Household.propose_grant(h, actor, item, Enum.random(@walk_members))

      n when n in 6..8 ->
        case random_proposal(h) do
          nil ->
            {:error, :none}

          id ->
            p = h.proposals[id]
            who = walk_actor(h, p.item_id)

            who =
              case p.change do
                {:owners, o} when is_struct(o, MapSet) ->
                  if :rand.uniform(3) == 1, do: Enum.random(Enum.sort(o)), else: who

                _ ->
                  who
              end

            Household.consent(h, who, id)
        end

      9 ->
        Household.relinquish(h, actor, item)

      10 ->
        Household.revoke_grant(h, actor, item, Enum.random(@walk_members))

      11 ->
        if :rand.uniform(3) == 1,
          do: Exit.delete(h, actor, item),
          else: Exit.leave(h, Enum.random(@walk_members))

      12 ->
        case random_proposal(h) do
          nil -> {:error, :none}
          id -> Household.withdraw(h, walk_actor(h, h.proposals[id].item_id), id)
        end
    end
  end

  defp walk(_h, 0, _seed, lapsed), do: lapsed

  defp walk(h, n, seed, lapsed) do
    h2 =
      case walk_op(h) do
        {:error, _} -> h
        ok -> ok!(ok)
      end

    for {id, p} <- h2.proposals do
      item = h2.items[p.item_id]

      assert item != nil and p.proposed_by in item.owners,
             "seed #{seed}: proposal #{id} pending, but its proposer #{inspect(p.proposed_by)} is not an owner"

      for o <- item.owners do
        assert {:ok, h3} = Household.withdraw(h2, o, id),
               "seed #{seed}: #{o} can't withdraw #{id}"

        assert Map.delete(h2.proposals, id) == h3.proposals
      end
    end

    # proposals whose proposer stopped owning the item (which still exists) in this step
    stopped =
      Enum.count(h.proposals, fn {_, p} ->
        match?(%{owners: _}, h2.items[p.item_id]) and
          p.proposed_by not in h2.items[p.item_id].owners
      end)

    walk(h2, n - 1, seed, lapsed + stopped)
  end

  describe "REQ-125" do
    test "in every reached state, each pending proposal's proposer is a current owner, and it and every other owner can withdraw it" do
      lapsed =
        for seed <- 1..400, reduce: 0 do
          acc ->
            :rand.seed(:exsss, {seed, seed * 11, seed * 17})
            walk(Household.new(@walk_members), 60, seed, acc)
        end

      # not vacuous: proposers did stop owning items while their proposals were pending
      assert lapsed >= 20, "only #{lapsed} lapsed proposals"
    end
  end

  describe "REQ-134" do
    test "accounts and debts, owned or shared, with readings, are never counted, and can't be linked either way" do
      h = Household.new([:a, :b])
      {:ok, h} = Alignment.add_value(h, :a, :v, "home")
      {:ok, h} = Balances.add_account(h, :a, :acct, "Checking", :checking)
      {:ok, h} = Balances.add_debt(h, :a, :debt, "Visa", :card)
      {:ok, h} = Balances.add_debt(h, :b, :loan, "Car loan", :loan)
      {:ok, h, _} = Household.propose_grant(h, :b, :loan, :a)
      {:ok, h} = Balances.add_reading(h, :a, :acct, %{on: "2026-09-01", balance: 50_000})

      {:ok, h} =
        Balances.add_reading(h, :a, :debt, %{
          on: "2026-09-01",
          balance: 90_000,
          rate_bp: 2000,
          min_payment: 3_000
        })

      {:ok, h} =
        Balances.add_reading(h, :b, :loan, %{
          on: "2026-09-01",
          balance: 800_000,
          rate_bp: 600,
          min_payment: 20_000
        })

      {:ok, h} = Household.add_item(h, :a, :rent, %{amount: -100, frequency: {:every, 1, :month}})

      assert Alignment.distribution(h, :a) == %{
               by_value: %{v: bucket(0)},
               unlinked: bucket(1, 0, -100)
             }

      for x <- [:acct, :debt, :loan] do
        assert {:error, :cannot_link_a_balance} = Alignment.link(h, :a, x, :v), inspect(x)
        assert {:error, :not_a_value} = Alignment.link(h, :a, :rent, x), inspect(x)
      end

      assert Alignment.links(h, :a) == []
    end
  end

  describe "REQ-167" do
    test "being named in a pending proposal on an ordinary item, or in a pending grant, gives no access" do
      {:ok, h} = Household.add_item(Household.new([:a, :b, :c]), :a, :i, %{amount: 1})
      h = joint!(h, :a, :i, [:a, :b])
      {:ok, h, add} = Household.propose_owners(h, :a, :i, [:a, :b, :c])
      {:ok, h, grant} = Household.propose_grant(h, :b, :i, :c)
      assert map_size(h.proposals) == 2

      refute View.visible?(h, :c, :i)
      assert View.get(h, :c, :i) == View.get(h, :c, :missing)
      assert View.visible_items(h, :c) == []
      assert Household.pending(h, :c) == []
      assert {:error, :not_found} = Household.consent(h, :c, add)
      assert {:error, :not_found} = Household.consent(h, :c, grant)
    end

    test "a member invited to a shared plan sees nothing until every current owner has agreed" do
      {:ok, h} = Plans.new_plan(Household.new([:a, :b, :c]), :a, :p, "Side business")
      {:ok, h, first} = Plans.propose_shared(h, :a, :p, :sp, [:b])
      {:ok, h} = Household.consent(h, :b, first)
      {:ok, h, invite} = Household.propose_owners(h, :a, :sp, [:a, :b, :c])

      refute View.visible?(h, :c, :sp)
      assert Household.pending(h, :c) == []
      assert {:error, :not_found} = Household.consent(h, :c, invite)

      {:ok, h} = Household.consent(h, :b, invite)

      assert [%{id: ^invite, attrs: %{kind: :plan, label: "Side business"}}] =
               Household.pending(h, :c)
    end
  end

  # REQ-168. :a owns salary, a gift, and taxes; :a and :b jointly own rent; :b shares a phone bill
  # with :a. :a has a value of their own, a value shared with :b, and :b's value shared by grant.
  defp h168 do
    h = Household.new([:a, :b, :c])

    {:ok, h} =
      Household.add_item(h, :a, :salary, %{amount: 300_000, frequency: {:every, 2, :week}})

    {:ok, h} = Household.add_item(h, :a, :gift, %{amount: 5_000, frequency: :one_off})
    {:ok, h} = Household.add_item(h, :a, :tax, %{amount: -120_000, frequency: :irregular})

    {:ok, h} =
      Household.add_item(h, :a, :rent, %{amount: -150_000, frequency: {:every, 1, :month}})

    h = joint!(h, :a, :rent, [:a, :b])
    {:ok, h} = Household.add_item(h, :b, :phone, %{amount: -6_000})
    {:ok, h, _} = Household.propose_grant(h, :b, :phone, :a)
    {:ok, h} = Alignment.add_value(h, :a, :av, "mine")
    {:ok, h} = Alignment.add_value(h, :a, :sv, "ours")
    {:ok, h, pid} = Household.propose_owners(h, :a, :sv, [:a, :b])
    {:ok, h} = Household.consent(h, :b, pid)
    {:ok, h} = Alignment.add_value(h, :b, :bv, "b's")
    {:ok, h, _} = Household.propose_grant(h, :b, :bv, :a)
    h
  end

  @money [:gift, :phone, :rent, :salary, :tax]
  @values [:av, :bv, :sv]

  describe "REQ-168" do
    test "every money item visible to the member links to every value visible to them, and unlinks" do
      h =
        Enum.reduce(for(i <- @money, v <- @values, do: {i, v}), h168(), fn {i, v}, h ->
          link!(h, :a, i, v)
        end)

      assert Enum.sort(Alignment.links(h, :a)) == for(i <- @money, v <- @values, do: {i, v})

      h =
        Enum.reduce(
          for(i <- @money, v <- @values, do: {i, v}),
          h,
          &ok!(Alignment.unlink(&2, :a, elem(&1, 0), elem(&1, 1)))
        )

      assert Alignment.links(h, :a) == []
    end

    test "a value, an account, a debt, or a shared plan can't be linked as the item" do
      h = h168()
      {:ok, h} = Balances.add_account(h, :a, :acct, "Checking", :checking)
      {:ok, h} = Balances.add_debt(h, :a, :debt, "Visa", :card)
      {:ok, h} = Plans.new_plan(h, :a, :p, "Plan")
      {:ok, h, _} = Plans.propose_shared(h, :a, :p, :plan, [:b])

      for {x, why} <- [
            av: :cannot_link_a_value,
            sv: :cannot_link_a_value,
            bv: :cannot_link_a_value,
            acct: :cannot_link_a_balance,
            debt: :cannot_link_a_balance,
            plan: :cannot_link_a_plan
          ],
          v <- @values,
          x != v,
          do: assert({:error, ^why} = Alignment.link(h, :a, x, v), inspect({x, v}))

      assert Alignment.links(h, :a) == []
    end

    test "no other member can read a member's links, even once they own both ends" do
      h = h168()

      before =
        for m <- [:b, :c],
            do: {m, Alignment.links(h, m), Alignment.distribution(h, m), Exit.export(h, m)}

      # rent and the shared value are both visible to :b
      h = h |> link!(:a, :rent, :sv) |> link!(:a, :salary, :av)

      assert for(
               m <- [:b, :c],
               do: {m, Alignment.links(h, m), Alignment.distribution(h, m), Exit.export(h, m)}
             ) == before

      assert {:error, :not_found} = Alignment.unlink(h, :b, :rent, :sv)

      # :a gives salary and their own value to :b
      h = joint!(h, :a, :salary, [:b])
      {:ok, h, pid} = Household.propose_owners(h, :a, :av, [:b])
      {:ok, h} = Household.consent(h, :b, pid)
      assert {:ok, %{owners: [:b]}} = View.get(h, :b, :av)

      assert Alignment.links(h, :b) == []
      assert Exit.export(h, :b).links == []
      assert Alignment.distribution(h, :b).by_value.av == bucket(0)
      assert {:error, :not_found} = Alignment.unlink(h, :b, :salary, :av)
    end
  end

  # :m exports; :o is someone else in the household.
  defp h169 do
    h = Household.new([:m, :o])
    {:ok, h} = Household.add_item(h, :m, :pay, %{amount: 400_000, frequency: {:every, 1, :month}})
    {:ok, h, _} = Household.propose_grant(h, :m, :pay, :o)
    {:ok, h} = Household.add_item(h, :m, :gym, %{amount: -5_000, frequency: {:every, 1, :month}})

    {:ok, h} =
      Household.add_item(h, :o, :rent, %{amount: -150_000, frequency: {:every, 1, :month}})

    h = joint!(h, :o, :rent, [:o, :m])
    {:ok, h} = Household.add_item(h, :o, :phone, %{amount: -6_000})
    {:ok, h, _} = Household.propose_grant(h, :o, :phone, :m)
    {:ok, h} = Household.add_item(h, :o, :joint, %{amount: -1_000})
    h = joint!(h, :o, :joint, [:o, :m])
    {:ok, h} = Alignment.add_value(h, :m, :home, "home")
    {:ok, h} = Alignment.add_value(h, :o, :theirs, "theirs")
    {:ok, h, _} = Household.propose_grant(h, :o, :theirs, :m)
    {:ok, h} = Balances.add_account(h, :m, :chk, "Checking", :checking)
    {:ok, h} = Balances.add_reading(h, :m, :chk, %{on: "2026-09-01", balance: 120_000})
    {:ok, h} = Balances.add_debt(h, :m, :visa, "Visa", :card)

    {:ok, h} =
      Balances.add_reading(h, :m, :visa, %{
        on: "2026-09-02",
        balance: 50_000,
        rate_bp: 2199,
        min_payment: 2_500
      })

    {:ok, h} = Balances.add_account(h, :m, :k401, "401(k)", :retirement_401k)
    {:ok, h} = Balances.add_account(h, :o, :ira, "IRA", :ira)
    {:ok, h, _} = Household.propose_grant(h, :o, :ira, :m)

    # links: one between owned ends, two touching things :m doesn't own
    h = h |> link!(:m, :pay, :home) |> link!(:m, :pay, :theirs) |> link!(:m, :phone, :home)
    h = h |> link!(:m, :rent, :home)

    # a plan whose switch-off steps name rent, which :m will stop owning
    {:ok, h} = Plans.new_plan(h, :m, :p1, "If the job stops")
    {:ok, h} = Plans.add_step(h, :m, :p1, {:switch_off, [:pay, :rent], "2026-11"})
    {:ok, h} = Plans.add_step(h, :m, :p1, {:switch_off, [:rent], "2026-12"})

    {:ok, h} =
      Plans.add_step(
        h,
        :m,
        :p1,
        {:add, %{note: "Tools", amount: -5_000, frequency: :one_off}, "2026-12"}
      )

    {:ok, h} =
      Plans.add_step(
        h,
        :m,
        :p1,
        {:borrow, %{amount: 100_000, rate_bp: 500, payment: 5_000}, "2027-01"}
      )

    {:ok, h} = Plans.mark(h, :m, :gym, :pay)
    {:ok, h} = Plans.mark(h, :m, :rent, :pay)
    {:ok, h} = Plans.set_fund_goal(h, :m, 3)
    {:ok, h} = Plans.set_aside(h, :m, :home, 2_500)
    {:ok, h} = Plans.set_aside(h, :m, :theirs, 1_000)
    {:ok, h} = Retirement.set(h, :m, :birth_year, 1980)
    {:ok, h} = Retirement.set(h, :m, :retire_age, 65)
    {:ok, h} = Retirement.set_contribution(h, :m, :k401, 20_000)
    {:ok, h} = Retirement.set_contribution(h, :m, :ira, 7_000)
    {:ok, h} = Attach.attach(h, :m, :pay, :chk)
    {:ok, h} = Attach.attach(h, :m, :phone, :chk)
    {:ok, h} = Attach.attach(h, :m, :rent, :chk)

    # a shared plan :m proposed, still waiting for :o
    {:ok, h} = Plans.new_plan(h, :m, :p2, "Holiday")

    {:ok, h} =
      Plans.add_step(
        h,
        :m,
        :p2,
        {:add, %{note: "Trip", amount: -80_000, frequency: :one_off}, "2027-06"}
      )

    {:ok, h, _} = Plans.propose_shared(h, :m, :p2, :sp, [:o])

    # :m stops owning rent, deletes something, and :o has a private record of their own
    {:ok, h} = Household.relinquish(h, :m, :rent)
    {:ok, h} = Household.add_item(h, :m, :old, %{amount: 1})
    {:ok, h} = Exit.delete(h, :m, :old)
    {:ok, h} = Plans.new_plan(h, :o, :op, "Theirs")
    {:ok, h} = Plans.set_fund_goal(h, :o, 6)
    h |> link!(:o, :rent, :theirs)
  end

  describe "REQ-169" do
    test "exactly: every owned item with attributes, owners, grantees, ledger, and readings; own links, plans, marks, goals, retirement, and attachments, keeping only references to what it contains" do
      h = h169()
      proposals = h.proposals
      e = Exit.export(h, :m)
      # nobody else's consent: nothing was asked of anyone
      assert h.proposals == proposals

      assert Enum.sort(Map.keys(e)) == [
               :attached,
               :goals,
               :items,
               :links,
               :marks,
               :member,
               :plans,
               :retirement
             ]

      assert e.member == :m

      owned = [:chk, :gym, :home, :joint, :k401, :pay, :sp, :visa]
      assert Enum.map(e.items, & &1.id) == owned

      for i <- e.items do
        assert Enum.sort(Map.keys(i)) == [:attrs, :grantees, :id, :ledger, :owners, :readings]
        assert i.attrs == h.items[i.id].attrs
        assert i.owners == Enum.sort(h.items[i.id].owners)
        assert {:ok, i.ledger} == Ledger.read(h, :m, i.id)
      end

      by_id = Map.new(e.items, &{&1.id, &1})
      assert by_id.pay.attrs == %{amount: 400_000, frequency: {:every, 1, :month}}
      assert by_id.pay.grantees == [:o]
      assert by_id.joint.owners == [:m, :o]
      assert by_id.home.attrs == %{kind: :value, label: "home"}
      assert [%{on: "2026-09-01", balance: 120_000, seq: 1, by: :m}] = by_id.chk.readings
      assert [%{balance: 50_000, rate_bp: 2199, min_payment: 2_500}] = by_id.visa.readings
      assert by_id.gym.readings == [] and by_id.home.readings == []
      assert by_id.sp.attrs.kind == :plan

      assert e.links == [{:pay, :home}]

      assert e.plans == [
               %{
                 id: :p1,
                 name: "If the job stops",
                 steps: [
                   {:switch_off, [:pay], "2026-11"},
                   {:add, %{note: "Tools", amount: -5_000, frequency: :one_off}, "2026-12"},
                   {:borrow, %{amount: 100_000, rate_bp: 500, payment: 5_000}, "2027-01"}
                 ]
               },
               %{
                 id: :p2,
                 name: "Holiday",
                 steps: [{:add, %{note: "Trip", amount: -80_000, frequency: :one_off}, "2027-06"}]
               }
             ]

      assert e.marks == [{:gym, :pay}]
      assert e.attached == [{:pay, :chk}]
      assert e.goals == %{fund_months: 3, set_aside: [{:home, 2_500}]}

      assert e.retirement == %{
               birth_year: 1980,
               retire_age: 65,
               return_bp: nil,
               ss_monthly: nil,
               target_monthly: nil,
               contributions: [{:k401, 20_000}]
             }
    end
  end
end
