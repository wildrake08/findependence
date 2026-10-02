defmodule Findependence.HouseholdTest do
  use ExUnit.Case, async: true
  import Findependence.TestJoint

  alias Findependence.{Household, Ledger, View}

  # a and b are partners; c is an adult child; x is not a member.
  defp h0, do: Household.new([:a, :b, :c])

  defp with_item(owner \\ :a, attrs \\ %{amount: 100}) do
    {:ok, h} = Household.add_item(h0(), owner, :acct, attrs)
    h
  end

  defp joint(owners \\ [:a, :b]) do
    h = with_item()
    # :a is the sole owner, so the change applies at once.
    h = joint!(h, :a, :acct, owners)
    h
  end

  describe "REQ-101 every item has a non-empty owner set of members" do
    test "an item starts owned by its creator" do
      assert {:ok, %{owners: [:a]}} = View.get(with_item(), :a, :acct)
    end

    test "an empty owner set is rejected" do
      assert {:error, :no_owners} = Household.propose_owners(with_item(), :a, :acct, [])
    end

    test "non-members can neither create items nor be made owners" do
      assert {:error, :not_a_member} = Household.add_item(h0(), :x, :i, %{})
      assert {:error, :not_a_member} = Household.propose_owners(with_item(), :a, :acct, [:a, :x])
    end
  end

  describe "REQ-102 read iff owner or grantee" do
    test "owner reads, others cannot, and invisible looks like missing" do
      h = with_item()
      assert View.visible?(h, :a, :acct)
      refute View.visible?(h, :b, :acct)
      assert View.get(h, :b, :acct) == View.get(h, :b, :nonexistent)
      assert View.visible_items(h, :b) == []
    end

    test "a grantee reads the item but not the list of other grantees" do
      {:ok, h, _} = Household.propose_grant(with_item(), :a, :acct, :b)
      assert {:ok, view} = View.get(h, :b, :acct)
      refute Map.has_key?(view, :grantees)
      assert {:ok, %{grantees: [:b]}} = View.get(h, :a, :acct)
    end
  end

  describe "REQ-103 grants" do
    test "only an owner can grant; a non-owner cannot even tell the item exists" do
      assert {:error, :not_found} = Household.propose_grant(with_item(), :b, :acct, :c)
    end

    test "a sole owner's grant takes effect at once" do
      {:ok, h, _} = Household.propose_grant(with_item(), :a, :acct, :c)
      assert View.visible?(h, :c, :acct)
      assert Household.pending(h, :a) == []
    end

    test "a grant on a joint item needs every owner's consent" do
      {:ok, h, pid} = Household.propose_grant(joint(), :a, :acct, :c)
      refute View.visible?(h, :c, :acct)
      assert [%{id: ^pid, change: {:grant, :c}}] = Household.pending(h, :b)
      assert {:error, :not_found} = Household.consent(h, :c, pid)
      {:ok, h} = Household.consent(h, :b, pid)
      assert View.visible?(h, :c, :acct)
    end

    test "any single owner can revoke; the grantee and non-owners cannot" do
      {:ok, h, pid} = Household.propose_grant(joint(), :a, :acct, :c)
      {:ok, h} = Household.consent(h, :b, pid)
      assert {:error, :not_found} = Household.revoke_grant(h, :c, :acct, :c)
      {:ok, h} = Household.revoke_grant(h, :b, :acct, :c)
      refute View.visible?(h, :c, :acct)
      assert {:error, :not_granted} = Household.revoke_grant(h, :a, :acct, :c)
    end
  end

  describe "REQ-104 owner changes need every current owner" do
    test "no member can add themselves" do
      assert {:error, :not_found} = Household.propose_owners(with_item(), :b, :acct, [:a, :b])
    end

    test "a change to a joint item waits for all owners, and consent by others is refused" do
      {:ok, h, pid} = Household.propose_owners(joint(), :a, :acct, [:a])
      assert {:ok, %{owners: [:a, :b]}} = View.get(h, :a, :acct)
      assert {:error, :not_found} = Household.consent(h, :c, pid)
      {:ok, h} = Household.consent(h, :b, pid)
      assert {:ok, %{owners: [:a]}} = View.get(h, :a, :acct)
      refute View.visible?(h, :b, :acct)
    end

    test "a pending proposal needs the consent of owners added while it waited" do
      h = joint()
      {:ok, h, grant} = Household.propose_grant(h, :a, :acct, :c)
      {:ok, h, add} = Household.propose_owners(h, :b, :acct, [:a, :b, :c])
      {:ok, h} = Household.consent(h, :a, add)
      # WI-086: :c, the new owner, agrees too
      {:ok, h} = Household.consent(h, :c, add)
      assert {:ok, %{owners: [:a, :b, :c]}} = View.get(h, :a, :acct)
      # the grant to :c is now moot: :c became an owner
      assert Enum.all?(Household.pending(h, :a), &(&1.id != grant))

      {:ok, h, shrink} = Household.propose_owners(h, :a, :acct, [:a, :b])
      {:ok, h} = Household.consent(h, :b, shrink)
      assert {:ok, %{owners: [:a, :b, :c]}} = View.get(h, :a, :acct), "still waiting for :c"
      {:ok, h} = Household.consent(h, :c, shrink)
      assert {:ok, %{owners: [:a, :b]}} = View.get(h, :a, :acct)
    end

    test "becoming an owner removes a now-redundant grant" do
      {:ok, h, _} = Household.propose_grant(with_item(), :a, :acct, :b)
      h = joint!(h, :a, :acct, [:a, :b])
      assert {:ok, %{owners: [:a, :b], grantees: []}} = View.get(h, :a, :acct)
    end
  end

  describe "REQ-105 append-only ledger readable by current owners" do
    test "every change is recorded with who consented" do
      {:ok, h, pid} = Household.propose_grant(joint(), :a, :acct, :c)
      {:ok, h} = Household.consent(h, :b, pid)
      {:ok, h} = Household.revoke_grant(h, :b, :acct, :c)
      {:ok, entries} = Ledger.read(h, :b, :acct)

      assert Enum.map(entries, &{&1.seq, &1.event, Enum.sort(&1.by)}) == [
               {1, :created, [:a]},
               # WI-086: the new owner's agreement is recorded with the owner's
               {2, :owners_changed, [:a, :b]},
               {3, :granted, [:a, :b]},
               {4, :grant_revoked, [:b]}
             ]
    end

    test "grantees, non-owners, and former owners cannot read it" do
      {:ok, h, _} = Household.propose_grant(joint(), :a, :acct, :c)
      assert {:error, :not_found} = Ledger.read(h, :c, :acct)
      {:ok, h, pid} = Household.propose_owners(h, :a, :acct, [:a])
      {:ok, h} = Household.consent(h, :b, pid)
      assert {:error, :not_found} = Ledger.read(h, :b, :acct)
    end
  end

  describe "REQ-106 aggregates only over visible items" do
    test "each member's total counts only what they can see" do
      {:ok, h} = Household.add_item(with_item(), :b, :loan, %{amount: -40})
      {:ok, h} = Household.add_item(h, :c, :wage, %{amount: 7})
      assert View.sum(h, :a, :amount) == 100
      assert View.sum(h, :b, :amount) == -40

      {:ok, h, _} = Household.propose_grant(h, :b, :loan, :a)
      assert View.sum(h, :a, :amount) == 60
      {:ok, h} = Household.revoke_grant(h, :b, :loan, :a)
      assert View.sum(h, :a, :amount) == 100
    end
  end
end
