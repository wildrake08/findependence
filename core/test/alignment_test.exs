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

  # A distribution bucket (REQ-126).
  defp b(count, one_off_in \\ 0, pm_in \\ 0, pm_out \\ 0, one_off_out \\ 0),
    do: %{
      count: count,
      per_month: %{in: pm_in, out: pm_out},
      one_off: %{in: one_off_in, out: one_off_out}
    }

  describe "REQ-126 evaluation-free distribution, per month and one-off" do
    test "per-value buckets plus an unlinked remainder, nothing else; no frequency means one-off" do
      {:ok, h} = Alignment.link(h0(), :a, :rent, :security)
      d = Alignment.distribution(h, :a)
      assert d == %{by_value: %{security: b(1, 100)}, unlinked: b(1, 20)}
      assert Map.keys(d) |> Enum.sort() == [:by_value, :unlinked]
    end

    test "recurring items are converted to per month one by one, then summed; in and out stay apart" do
      h = Household.new([:a])
      {:ok, h} = Alignment.add_value(h, :a, :home, "home")

      for {id, amount, f} <- [
            {:rent, -215_000, :monthly},
            {:pay, 148_000, :biweekly},
            {:bus, -3_250, :weekly},
            {:insurance, -90_001, :yearly},
            {:couch, -64_999, :one_off},
            {:gift, 5_000, nil}
          ],
          reduce: h do
        h ->
          attrs = if f, do: %{amount: amount, frequency: f}, else: %{amount: amount}
          {:ok, h} = Household.add_item(h, :a, id, attrs)
          {:ok, h} = Alignment.link(h, :a, id, :home)
          h
      end
      |> then(fn h ->
        # 148000 x 26/12 = 320666.67 -> 320667; -3250 x 52/12 = -14083.33 -> -14083;
        # -90001 / 12 = -7500.08 -> -7500
        assert Alignment.distribution(h, :a).by_value == %{
                 home: %{
                   count: 6,
                   per_month: %{in: 320_667, out: -215_000 - 14_083 - 7_500},
                   one_off: %{in: 5_000, out: -64_999}
                 }
               }
      end)
    end

    test "per_month rounds half away from zero, symmetrically" do
      assert Alignment.per_month(6, :yearly) == 1
      assert Alignment.per_month(-6, :yearly) == -1
      assert Alignment.per_month(5, :yearly) == 0
      assert Alignment.per_month(3, :weekly) == 13
      assert Alignment.per_month(-3, :weekly) == -13
      assert Alignment.per_month(100, :one_off) == nil
    end

    test "an unknown frequency counts as one-off" do
      h = Household.new([:a])
      {:ok, h} = Household.add_item(h, :a, :x, %{amount: -10, frequency: :fortnightly_ish})
      assert Alignment.distribution(h, :a).unlinked == b(1, 0, 0, 0, -10)
    end

    test "an item linked to two values counts toward each" do
      h = h0()
      {:ok, h} = Alignment.add_value(h, :a, :learning, "keep learning")
      {:ok, h} = Alignment.link(h, :a, :books, :security)
      {:ok, h} = Alignment.link(h, :a, :books, :learning)

      assert %{security: %{one_off: %{in: 20}}, learning: %{one_off: %{in: 20}}} =
               Alignment.distribution(h, :a).by_value
    end

    test "only the requester's visible items and own links count" do
      {:ok, h} = Alignment.link(h0(), :a, :rent, :security)

      assert Alignment.distribution(h, :b) == %{
               by_value: %{freedom: b(0)},
               unlinked: b(1, 100)
             }

      assert Alignment.distribution(h, :c) == %{by_value: %{}, unlinked: b(0)}
    end
  end

  describe "REQ-114 losing visibility removes silently" do
    test "revocation hides the item from links and distribution; regaining shows the member's own link again" do
      h = h0()
      {:ok, h, _} = Household.propose_grant(h, :a, :books, :b)
      {:ok, h} = Alignment.link(h, :b, :books, :freedom)
      assert %{freedom: %{one_off: %{in: 20}}} = Alignment.distribution(h, :b).by_value

      {:ok, h} = Household.revoke_grant(h, :a, :books, :b)
      assert Alignment.links(h, :b) == []

      assert Alignment.distribution(h, :b) == %{by_value: %{freedom: b(0)}, unlinked: b(1, 100)}

      {:ok, h, _} = Household.propose_grant(h, :a, :books, :b)
      assert Alignment.links(h, :b) == [{:books, :freedom}]
    end

    test "relinquishing a shared item removes it from one's distribution" do
      {:ok, h} = Alignment.link(h0(), :b, :rent, :freedom)
      {:ok, h} = Household.relinquish(h, :b, :rent)
      assert Alignment.distribution(h, :b).by_value == %{freedom: b(0)}
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

defmodule Findependence.ExportLinksTest do
  @moduledoc "REQ-117: export carries a member's own links only where they own both ends."
  use ExUnit.Case, async: true

  alias Findependence.{Alignment, Exit, Household}

  test "own links between owned items and owned values are exported; links touching others' items are not" do
    h = Household.new([:a, :b])
    {:ok, h} = Household.add_item(h, :a, :books, %{amount: 20})
    {:ok, h} = Alignment.add_value(h, :a, :learning, "keep learning")
    {:ok, h} = Household.add_item(h, :b, :rent, %{amount: 100})
    {:ok, h, _} = Household.propose_grant(h, :b, :rent, :a)
    {:ok, h} = Alignment.link(h, :a, :books, :learning)
    {:ok, h} = Alignment.link(h, :a, :rent, :learning)

    export = Exit.export(h, :a)
    assert export.links == [{:books, :learning}]
    refute Enum.any?(export.items, &(&1.id == :rent))
  end

  test "a link to a value shared by grant is not exported, and another member's links never are" do
    h = Household.new([:a, :b])
    {:ok, h} = Household.add_item(h, :a, :books, %{})
    {:ok, h} = Alignment.add_value(h, :b, :freedom, "not owing anyone")
    {:ok, h, _} = Household.propose_grant(h, :b, :freedom, :a)
    {:ok, h, _} = Household.propose_grant(h, :a, :books, :b)
    {:ok, h} = Alignment.link(h, :a, :books, :freedom)
    {:ok, h} = Alignment.link(h, :b, :books, :freedom)

    assert Exit.export(h, :a).links == []
    assert Exit.export(h, :b).links == []
  end
end
