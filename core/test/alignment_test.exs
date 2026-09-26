defmodule Findependence.AlignmentTest do
  use ExUnit.Case, async: true

  alias Findependence.{Alignment, Exit, Household, View}

  # :a and :b share rent; :a has private spending; each has own values.
  defp h0 do
    h = Household.new([:a, :b, :c])
    {:ok, h} = Household.add_item(h, :a, :rent, %{amount: 100})
    {:ok, h, _} = Household.propose_owners(h, :a, :rent, [:a, :b])
    {:ok, h} = Household.add_item(h, :a, :books, %{amount: 20})
    {:ok, h} = Alignment.add_value(h, :a, :security, "a home that feels safe")
    {:ok, h} = Alignment.add_value(h, :b, :freedom, "not owing anyone")
    h
  end

  describe "REQ-111 values are owned items with no predefined values" do
    test "a value is an ordinary owned item, private by default" do
      h = h0()

      assert {:ok, %{owners: [:a], attrs: %{kind: :value, label: "a home that feels safe"}}} =
               View.get(h, :a, :security)

      refute View.visible?(h, :b, :security)
    end

    test "a new household has no values, and values obey ownership rules" do
      assert Alignment.distribution(Household.new([:a]), :a).by_value == %{}
      {:ok, h, _} = Household.propose_grant(h0(), :a, :security, :b)
      assert View.visible?(h, :b, :security)
      assert {:ok, _} = Exit.delete(h, :a, :security)
    end
  end

  describe "REQ-112 private links" do
    test "a member links visible items to visible values, and nobody else sees the link" do
      {:ok, h} = Alignment.link(h0(), :a, :rent, :security)
      assert Alignment.links(h, :a) == [{:rent, :security}]
      assert Alignment.links(h, :b) == []
    end

    test "linking needs visibility of both ends; invisible looks like missing" do
      h = h0()
      assert {:error, :not_found} = Alignment.link(h, :b, :books, :freedom)
      assert {:error, :not_found} = Alignment.link(h, :b, :rent, :security)
      assert {:error, :not_found} = Alignment.link(h, :b, :rent, :nope)
    end

    test "a value is a target, not an activity" do
      h = h0()
      assert {:error, :not_a_value} = Alignment.link(h, :a, :rent, :books)
      {:ok, h, _} = Household.propose_grant(h, :b, :freedom, :a)
      assert {:error, :cannot_link_a_value} = Alignment.link(h, :a, :freedom, :security)
    end

    test "two members can link the same shared item differently, each privately" do
      {:ok, h} = Alignment.link(h0(), :a, :rent, :security)
      {:ok, h} = Alignment.link(h, :b, :rent, :freedom)
      assert Alignment.links(h, :a) == [{:rent, :security}]
      assert Alignment.links(h, :b) == [{:rent, :freedom}]
    end

    test "unlink removes only one's own link" do
      {:ok, h} = Alignment.link(h0(), :a, :rent, :security)
      assert {:error, :not_found} = Alignment.unlink(h, :b, :rent, :security)
      {:ok, h} = Alignment.unlink(h, :a, :rent, :security)
      assert Alignment.links(h, :a) == []
      {:ok, h} = Alignment.link(h, :a, :rent, :security)
      assert {:error, :already_linked} = Alignment.link(h, :a, :rent, :security)
    end
  end

  describe "REQ-113 evaluation-free distribution" do
    test "per-value sums and counts plus an unlinked remainder, nothing else" do
      {:ok, h} = Alignment.link(h0(), :a, :rent, :security)
      d = Alignment.distribution(h, :a)
      assert d == %{by_value: %{security: %{sum: 100, count: 1}}, unlinked: %{sum: 20, count: 1}}
      assert Map.keys(d) |> Enum.sort() == [:by_value, :unlinked]
    end

    test "an item linked to two values counts toward each" do
      h = h0()
      {:ok, h} = Alignment.add_value(h, :a, :learning, "keep learning")
      {:ok, h} = Alignment.link(h, :a, :books, :security)
      {:ok, h} = Alignment.link(h, :a, :books, :learning)

      assert %{security: %{sum: 20}, learning: %{sum: 20}} =
               Alignment.distribution(h, :a).by_value
    end

    test "only the requester's visible items and own links count" do
      {:ok, h} = Alignment.link(h0(), :a, :rent, :security)

      assert Alignment.distribution(h, :b) == %{
               by_value: %{freedom: %{sum: 0, count: 0}},
               unlinked: %{sum: 100, count: 1}
             }

      assert Alignment.distribution(h, :c) == %{by_value: %{}, unlinked: %{sum: 0, count: 0}}
    end
  end

  describe "REQ-114 losing visibility removes silently" do
    test "revocation hides the item from links and distribution; regaining shows the member's own link again" do
      h = h0()
      {:ok, h, _} = Household.propose_grant(h, :a, :books, :b)
      {:ok, h} = Alignment.link(h, :b, :books, :freedom)
      assert %{freedom: %{sum: 20}} = Alignment.distribution(h, :b).by_value

      {:ok, h} = Household.revoke_grant(h, :a, :books, :b)
      assert Alignment.links(h, :b) == []

      assert Alignment.distribution(h, :b) == %{
               by_value: %{freedom: %{sum: 0, count: 0}},
               unlinked: %{sum: 100, count: 1}
             }

      {:ok, h, _} = Household.propose_grant(h, :a, :books, :b)
      assert Alignment.links(h, :b) == [{:books, :freedom}]
    end

    test "relinquishing a shared item removes it from one's distribution" do
      {:ok, h} = Alignment.link(h0(), :b, :rent, :freedom)
      {:ok, h} = Household.relinquish(h, :b, :rent)
      assert Alignment.distribution(h, :b).by_value == %{freedom: %{sum: 0, count: 0}}
    end

    test "deleting an item purges links, so a reused id inherits nothing" do
      {:ok, h} = Alignment.link(h0(), :a, :books, :security)
      {:ok, h} = Exit.delete(h, :a, :books)
      {:ok, h} = Household.add_item(h, :a, :books, %{amount: 5})
      assert Alignment.links(h, :a) == []
    end

    test "leaving drops the leaver's links" do
      h = Household.new([:a, :b])
      {:ok, h} = Household.add_item(h, :a, :i, %{amount: 1})
      {:ok, h} = Alignment.add_value(h, :a, :v, "x")
      {:ok, h, _} = Household.propose_grant(h, :a, :i, :b)
      {:ok, h, _} = Household.propose_grant(h, :a, :v, :b)
      {:ok, h} = Alignment.link(h, :b, :i, :v)
      {:ok, h} = Exit.leave(h, :b)
      refute Map.has_key?(h.links, :b)
    end
  end
end
