defmodule Findependence.VVF05BTest do
  @moduledoc """
  WI-057 (VV-001 F-05/F-08, batch B): acceptance criteria for REQ-129, REQ-131, and REQ-171 that no
  earlier core test asserted.
  """
  use ExUnit.Case, async: true
  import Findependence.TestJoint

  alias Findependence.{Alignment, Balances, Exit, Household, Ledger, Schedule, View}

  @account_types [:checking, :savings, :other, :retirement_401k, :ira]
  @debt_types [:card, :heloc, :loan, :other]

  defp h0, do: Household.new([:mom, :dad, :kid])

  defp ok({:ok, h}), do: h
  defp ok({:ok, h, _proposal}), do: h

  defp reading(on, bal), do: %{on: on, balance: bal}
  defp debt_reading(on, bal), do: %{on: on, balance: bal, rate_bp: 1999, min_payment: 2_500}

  # one account and one debt, each created by :mom
  defp both do
    h0()
    |> Balances.add_account(:mom, :acct, "Checking", :checking)
    |> ok()
    |> Balances.add_debt(:mom, :debt, "Card", :card)
    |> ok()
  end

  defp read_for(:acct), do: reading("2026-09-27", 1_000)
  defp read_for(:debt), do: debt_reading("2026-09-27", 1_000)

  describe "REQ-171: an account or a debt is an item of its own kind" do
    test "every listed kind can be created; it is owned by its creator alone and private" do
      for {add, kind, types} <- [
            {&Balances.add_account/5, :account, @account_types},
            {&Balances.add_debt/5, :debt, @debt_types}
          ],
          type <- types do
        h = ok(add.(h0(), :dad, :x, "Mine", type))
        item = h.items[:x]
        assert item.attrs[:kind] == kind
        type_key = if kind == :account, do: :account_type, else: :debt_type
        assert item.attrs[type_key] == type
        assert item.owners == MapSet.new([:dad])
        assert item.grantees == MapSet.new()
        assert View.visible?(h, :dad, :x)
        refute View.visible?(h, :mom, :x) or View.visible?(h, :kid, :x)
      end

      # nothing else is an account or a debt
      assert {:error, :invalid_balance} = Balances.add_account(h0(), :dad, :x, "X", :mortgage)
      assert {:error, :invalid_balance} = Balances.add_account(h0(), :dad, :x, "X", :card)
      assert {:error, :invalid_balance} = Balances.add_debt(h0(), :dad, :x, "X", :checking)
      assert {:error, :invalid_balance} = Balances.add_debt(h0(), :dad, :x, "X", nil)
    end

    test "REQ-101, REQ-103, REQ-105, REQ-107: owners, grants, and history work as for any item" do
      for id <- [:acct, :debt] do
        h = both()
        # REQ-101: never without an owner
        assert {:error, :no_owners} = Household.propose_owners(h, :mom, id, [])
        assert {:error, :sole_owner} = Household.relinquish(h, :mom, id)
        # REQ-103: only an owner grants; REQ-107: nobody adds themselves as an owner
        assert {:error, :not_found} = Household.propose_grant(h, :dad, id, :kid)
        assert {:error, :not_found} = Household.propose_owners(h, :dad, id, [:mom, :dad])
        h = joint!(h, :mom, id, [:mom, :dad])
        assert h.items[id].owners == MapSet.new([:mom, :dad])
        # REQ-103: a grant on a joint item waits for every owner
        {:ok, h, g} = Household.propose_grant(h, :mom, id, :kid)
        refute :kid in h.items[id].grantees
        h = ok(Household.consent(h, :dad, g))
        assert :kid in h.items[id].grantees
        # any single owner revokes
        h = ok(Household.revoke_grant(h, :dad, id, :kid))
        refute :kid in h.items[id].grantees
        # REQ-107: changing the owners waits for every owner, but one may remove only themselves
        h = joint!(h, :dad, id, [:dad])
        assert h.items[id].owners == MapSet.new([:mom, :dad])
        h = ok(Household.relinquish(h, :dad, id))
        assert h.items[id].owners == MapSet.new([:mom])
        # REQ-105: every change is in the history, readable by the owners and nobody else
        {:ok, entries} = Ledger.read(h, :mom, id)

        assert Enum.map(entries, & &1.event) == [
                 :created,
                 :owners_changed,
                 :granted,
                 :grant_revoked,
                 :owner_relinquished
               ]

        assert {:error, :not_found} = Ledger.read(h, :dad, id)
        assert {:error, :not_found} = Ledger.read(h, :kid, id)
      end
    end

    test "REQ-106: a household view counts only accounts the member can see" do
      h = ok(Balances.add_reading(both(), :mom, :acct, reading("2026-09-26", 50_000)))
      assert Schedule.cash_flow(h, :mom, ~D[2026-09-27], 5).start.balance == 50_000
      assert Schedule.cash_flow(h, :dad, ~D[2026-09-27], 5).start == nil
      h = ok(Household.propose_grant(h, :mom, :acct, :dad))
      assert Schedule.cash_flow(h, :dad, ~D[2026-09-27], 5).start.balance == 50_000
    end

    test "REQ-108: only a sole owner deletes, and everything about it goes but a bare record" do
      for id <- [:acct, :debt] do
        h = both()
        h = ok(Balances.add_reading(h, :mom, id, read_for(id)))
        h = joint!(h, :mom, id, [:mom, :dad])
        assert {:error, :not_sole_owner} = Exit.delete(h, :mom, id)
        h = ok(Household.relinquish(h, :dad, id))
        h = ok(Household.propose_grant(h, :mom, id, :kid))
        h = ok(Exit.delete(h, :mom, id))
        refute Map.has_key?(h.items, id)
        refute View.visible?(h, :kid, id)
        refute Map.has_key?(h.ledger, id)
        refute Map.has_key?(h.readings, id)
        assert %{item_id: ^id} = rec = List.last(Ledger.deletions(h, :mom))
        assert Map.keys(rec) |> Enum.sort() == [:item_id, :seq]
        assert Ledger.deletions(h, :kid) == []
      end
    end

    test "REQ-110: owning an account or a debt stops a member leaving until it's gone" do
      for id <- [:acct, :debt] do
        h = ok(Household.propose_grant(both(), :mom, id, :dad))
        assert {:error, _} = Exit.leave(h, :mom)
        # a grantee who owns nothing leaves, and their grant goes
        h = ok(Exit.leave(h, :dad))
        refute :dad in h.items[id].grantees
        other = if id == :acct, do: :debt, else: :acct
        h = h |> Exit.delete(:mom, id) |> ok() |> Exit.delete(:mom, other) |> ok()
        assert {:ok, _} = Exit.leave(h, :mom)
      end
    end

    test "REQ-125: a pending change to a joint account can be withdrawn by an owner" do
      h = joint!(both(), :mom, :acct, [:mom, :dad])
      {:ok, h, pid} = Household.propose_grant(h, :mom, :acct, :kid)
      assert {:error, :not_found} = Household.withdraw(h, :kid, pid)
      h = ok(Household.withdraw(h, :dad, pid))
      refute Map.has_key?(h.proposals, pid)
      refute :kid in h.items[:acct].grantees
    end

    test "REQ-167: read if and only if owner or grantee; being proposed as an owner gives no access" do
      h = both()
      h = joint!(h, :mom, :acct, [:mom, :dad])
      # :kid is only proposed, and sees the proposal only once every owner has agreed (WI-086)
      {:ok, h, pid} = Household.propose_owners(h, :mom, :acct, [:mom, :dad, :kid])
      refute View.visible?(h, :kid, :acct)
      assert {:error, :not_found} = View.get(h, :kid, :acct)
      assert Household.pending(h, :kid) == []
      assert {:error, :not_found} = Balances.readings(h, :kid, :acct)

      # once every owner has agreed, :kid sees the request; once :kid agrees too, :kid is an owner and reads it
      h = ok(Household.consent(h, :dad, pid))
      assert [%{id: ^pid}] = Household.pending(h, :kid)
      refute :kid in h.items[:acct].owners
      h = ok(Household.consent(h, :kid, pid))
      assert View.visible?(h, :kid, :acct)
    end

    test "REQ-169: the owner's export carries the account with its readings; a grantee's doesn't" do
      h = ok(Balances.add_reading(both(), :mom, :debt, debt_reading("2026-09-27", 7_000)))
      h = ok(Household.propose_grant(h, :mom, :debt, :dad))
      mine = Enum.find(Exit.export(h, :mom).items, &(&1.id == :debt))
      assert [%{balance: 7_000}] = mine.readings
      assert mine.attrs == %{kind: :debt, label: "Card", debt_type: :card}
      refute Enum.any?(Exit.export(h, :dad).items, &(&1.id == :debt))
    end

    test "its name and kind are fixed: no operation changes them" do
      for id <- [:acct, :debt] do
        h = both()
        created = h.items[id].attrs

        steps = [
          &Balances.add_reading(&1, :mom, id, read_for(id)),
          &Household.propose_grant(&1, :mom, id, :kid),
          &joint(&1, :mom, id, [:mom, :dad]),
          &Balances.add_reading(&1, :dad, id, read_for(id)),
          &Household.revoke_grant(&1, :dad, id, :kid),
          &Household.relinquish(&1, :mom, id),
          &Exit.leave(&1, :kid)
        ]

        h =
          Enum.reduce(steps, h, fn step, h ->
            h = ok(step.(h))
            assert h.items[id].attrs == created
            h
          end)

        # an account or a debt can't be added again under its id with another name or kind
        assert {:error, :item_exists} = Balances.add_account(h, :dad, id, "Renamed", :savings)
        assert {:error, :item_exists} = Balances.add_debt(h, :dad, id, "Renamed", :loan)
        assert h.items[id].attrs == created
      end
    end
  end

  describe "REQ-131: readings" do
    test "a reading needs the date it is as of" do
      h = both()
      assert {:error, :invalid_reading} = Balances.add_reading(h, :mom, :acct, %{balance: 5})

      assert {:error, :invalid_reading} =
               Balances.add_reading(h, :mom, :debt, %{balance: 5, rate_bp: 1, min_payment: 1})

      assert {:error, :invalid_reading} =
               Balances.add_reading(h, :mom, :acct, %{on: nil, balance: 5})
    end

    test "a joint owner's reading needs nobody else's consent: it applies at once, with no proposal" do
      h = joint!(both(), :mom, :acct, [:mom, :dad])
      h = ok(Balances.add_reading(h, :dad, :acct, reading("2026-09-27", 42)))
      assert h.proposals == %{}
      assert %{balance: 42, by: :dad, on: "2026-09-27"} = Balances.latest(h, :mom, :acct)
    end
  end

  test "REQ-129: items stored with the earlier frequencies read as the same intervals" do
    for {legacy, interval} <- [
          weekly: {:every, 1, :week},
          biweekly: {:every, 2, :week},
          monthly: {:every, 1, :month},
          yearly: {:every, 1, :year},
          one_off: :one_off
        ] do
      assert Alignment.frequency(%{attrs: %{frequency: legacy}}) == interval
    end
  end
end
