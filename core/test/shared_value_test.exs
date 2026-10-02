defmodule Findependence.SharedValueTest do
  @moduledoc "CAP-005: shared values exist only by the consent of every participant (REQ-115, REQ-116)."
  use ExUnit.Case, async: true
  import Findependence.TestJoint

  alias Findependence.{Alignment, Exit, Household, View}

  defp h0 do
    {:ok, h} =
      Alignment.add_value(Household.new([:a, :b, :c]), :a, :home, "a home that feels safe")

    h
  end

  describe "REQ-115 joining needs the joiner's own consent" do
    test "a sole owner cannot make someone a co-owner of a value unilaterally" do
      {:ok, h, pid} = Household.propose_owners(h0(), :a, :home, [:a, :b])
      assert {:ok, %{owners: [:a]}} = View.get(h, :a, :home)
      refute View.visible?(h, :b, :home)

      assert [%{id: ^pid, attrs: %{label: "a home that feels safe"}}] = Household.pending(h, :b)
      {:ok, h} = Household.consent(h, :b, pid)
      assert {:ok, %{owners: [:a, :b]}} = View.get(h, :a, :home)
    end

    test "a prospective member sees the proposal only after every current owner has consented" do
      h = joint!(h0(), :a, :home, [:a, :b])
      # :a and :b now share the value; :a proposes adding :c
      {:ok, h, pid} = Household.propose_owners(h, :a, :home, [:a, :b, :c])
      assert Household.pending(h, :c) == []
      assert {:error, :not_found} = Household.consent(h, :c, pid)

      {:ok, h} = Household.consent(h, :b, pid)
      assert [%{id: ^pid, attrs: %{kind: :value}}] = Household.pending(h, :c)
      {:ok, h} = Household.consent(h, :c, pid)
      assert {:ok, %{owners: [:a, :b, :c]}} = View.get(h, :a, :home)
    end

    test "the ledger records the joiner's consent" do
      {:ok, h, pid} = Household.propose_owners(h0(), :a, :home, [:a, :b])
      {:ok, h} = Household.consent(h, :b, pid)
      {:ok, entries} = Findependence.Ledger.read(h, :a, :home)
      assert %{event: :owners_changed, by: [:a, :b]} = List.last(entries)
    end

    test "ordinary (non-value) items keep REQ-107: current owners suffice" do
      {:ok, h} = Household.add_item(Household.new([:a, :b]), :a, :acct, %{amount: 1})
      h = joint!(h, :a, :acct, [:a, :b])
      assert {:ok, %{owners: [:a, :b]}} = View.get(h, :a, :acct)
    end
  end

  describe "REQ-116 withdrawal" do
    test "any participant withdraws alone while another remains; the last may delete" do
      {:ok, h, pid} = Household.propose_owners(h0(), :a, :home, [:a, :b])
      {:ok, h} = Household.consent(h, :b, pid)
      {:ok, h} = Household.relinquish(h, :a, :home)
      assert {:ok, %{owners: [:b]}} = View.get(h, :b, :home)
      assert {:error, :sole_owner} = Household.relinquish(h, :b, :home)
      assert {:ok, _} = Exit.delete(h, :b, :home)
    end
  end
end
