defmodule Findependence.ExitTest do
  use ExUnit.Case, async: true

  alias Findependence.{Exit, Household, Ledger, View}

  defp joint do
    {:ok, h} = Household.add_item(Household.new([:a, :b, :c]), :a, :acct, %{amount: 10})
    {:ok, h, _} = Household.propose_owners(h, :a, :acct, [:a, :b])
    h
  end

  describe "REQ-107 unilateral self-removal while another owner remains" do
    test "a joint owner leaves an item without the other's consent" do
      {:ok, h} = Household.relinquish(joint(), :b, :acct)
      assert {:ok, %{owners: [:a]}} = View.get(h, :a, :acct)
      refute View.visible?(h, :b, :acct)
      {:ok, entries} = Ledger.read(h, :a, :acct)
      assert %{event: :owner_relinquished, by: [:b]} = List.last(entries)
    end

    test "the last owner cannot relinquish, and a non-owner cannot" do
      {:ok, h} = Household.add_item(Household.new([:a, :b]), :a, :solo, %{})
      assert {:error, :sole_owner} = Household.relinquish(h, :a, :solo)
      assert {:error, :not_found} = Household.relinquish(h, :b, :solo)
    end

    test "removing someone else still needs every owner" do
      {:ok, h, pid} = Household.propose_owners(joint(), :a, :acct, [:a])
      assert {:ok, %{owners: [:a, :b]}} = View.get(h, :a, :acct)
      assert [%{id: ^pid}] = Household.pending(h, :b)
    end

    test "the relinquisher's own pending proposals, and any that would restore them, are dropped" do
      h = joint()
      {:ok, h, _} = Household.propose_grant(h, :b, :acct, :c)
      {:ok, h, _} = Household.propose_owners(h, :a, :acct, [:a, :b, :c])
      {:ok, h} = Household.relinquish(h, :b, :acct)
      assert Household.pending(h, :a) == []
    end
  end

  describe "REQ-108 sole-owner deletion" do
    test "deletes the item, its grants, proposals and ledger, keeping a content-free record for the deleter" do
      {:ok, h} = Household.add_item(Household.new([:a, :b]), :a, :solo, %{amount: 5})
      {:ok, h, _} = Household.propose_grant(h, :a, :solo, :b)
      {:ok, h} = Exit.delete(h, :a, :solo)

      refute View.visible?(h, :b, :solo)
      assert {:error, :not_found} = Ledger.read(h, :a, :solo)
      assert Ledger.deletions(h, :a) == [%{seq: 1, item_id: :solo}]
      assert Ledger.deletions(h, :b) == []
      refute Map.has_key?(h.ledger, :solo)
    end

    test "a joint owner cannot delete, and a non-owner cannot tell the item exists" do
      assert {:error, :not_sole_owner} = Exit.delete(joint(), :a, :acct)
      assert {:error, :not_found} = Exit.delete(joint(), :c, :acct)
    end

    test "a joint owner can reach sole ownership unilaterally only by the others leaving" do
      {:ok, h} = Household.relinquish(joint(), :b, :acct)
      assert {:ok, _} = Exit.delete(h, :a, :acct)
    end
  end

  describe "REQ-117 export (supersedes REQ-109)" do
    test "contains exactly the owned items with their ledgers, not items shared by grant" do
      h = joint()
      {:ok, h} = Household.add_item(h, :c, :other, %{})
      {:ok, h, _} = Household.propose_grant(h, :c, :other, :b)

      assert %{member: :b, items: [%{id: :acct, owners: [:a, :b], ledger: ledger}]} =
               Exit.export(h, :b)

      assert ledger == elem(Ledger.read(h, :a, :acct), 1)
      assert Exit.export(Household.new([:z]), :z) == %{member: :z, items: [], links: []}
    end
  end

  describe "REQ-110 departure" do
    test "an owner is refused until they own nothing, then leaves unilaterally" do
      h = joint()
      assert {:error, :still_owner} = Exit.leave(h, :b)
      {:ok, h} = Household.relinquish(h, :b, :acct)
      {:ok, h} = Exit.leave(h, :b)
      refute :b in h.members
    end

    test "leaving removes held grants (recorded) and proposals naming the leaver" do
      h = Household.new([:a, :b, :c])
      # :i is joint (a, b), so a grant to :c waits for :b
      {:ok, h} = Household.add_item(h, :a, :i, %{})
      {:ok, h, _} = Household.propose_owners(h, :a, :i, [:a, :b])
      {:ok, h, _pending} = Household.propose_grant(h, :a, :i, :c)
      # :j is solely owned by :a, so the grant to :c applies at once
      {:ok, h} = Household.add_item(h, :a, :j, %{amount: 3})
      {:ok, h, _} = Household.propose_grant(h, :a, :j, :c)
      assert View.visible?(h, :c, :j)

      {:ok, h} = Exit.leave(h, :c)

      refute View.visible?(h, :c, :j)
      {:ok, entries} = Ledger.read(h, :a, :j)
      assert %{event: :grantee_departed, details: %{grantee: :c}} = List.last(entries)
      assert Household.pending(h, :b) == []
      assert {:error, :not_a_member} = Household.propose_grant(h, :a, :j, :c)
    end

    test "a non-member cannot leave" do
      assert {:error, :not_a_member} = Exit.leave(Household.new([:a]), :x)
    end
  end
end
