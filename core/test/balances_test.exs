defmodule Findependence.BalancesTest do
  use ExUnit.Case, async: true
  import Findependence.TestJoint

  alias Findependence.{Alignment, Balances, Exit, Household, Ledger, View}

  defp h0 do
    h = Household.new([:mom, :dad, :kid])
    {:ok, h} = Balances.add_account(h, :mom, :checking, "Joint checking", :checking)
    h = joint!(h, :mom, :checking, [:mom, :dad])
    {:ok, h} = Balances.add_debt(h, :dad, :visa, "Visa", :card)
    h
  end

  defp reading(on, bal), do: %{on: on, balance: bal}
  defp debt_reading(on, bal, bp, min), do: %{on: on, balance: bal, rate_bp: bp, min_payment: min}

  describe "REQ-130 accounts and debts are items of their own kind" do
    test "private by default, owned by the creator, with a fixed name and kind" do
      h = h0()

      assert {:ok, %{owners: [:dad], attrs: %{kind: :debt, label: "Visa", debt_type: :card}}} =
               View.get(h, :dad, :visa)

      refute View.visible?(h, :mom, :visa)
      assert {:error, :invalid_balance} = Balances.add_account(h, :kid, :x, "", :checking)
      assert {:error, :invalid_balance} = Balances.add_debt(h, :kid, :x, "Loan", :mortgage)
    end

    test "sharing, ownership, and exit apply as to any item" do
      {:ok, h, _} = Household.propose_grant(h0(), :dad, :visa, :mom)
      assert View.visible?(h, :mom, :visa)
      {:ok, h} = Exit.delete(h, :dad, :visa)
      refute Map.has_key?(h.items, :visa)
    end
  end

  describe "REQ-131 readings: any owner, nobody else, append-only, in the history" do
    test "either joint owner adds a reading without asking the other" do
      {:ok, h} = Balances.add_reading(h0(), :mom, :checking, reading("2026-09-20", 124_000))
      {:ok, h} = Balances.add_reading(h, :dad, :checking, reading("2026-09-27", 98_050))

      assert {:ok, [%{seq: 1, by: :mom, balance: 124_000}, %{seq: 2, by: :dad, balance: 98_050}]} =
               Balances.readings(h, :mom, :checking)

      {:ok, ledger} = Ledger.read(h, :mom, :checking)
      assert [:reading_added, :reading_added] = ledger |> Enum.map(& &1.event) |> Enum.take(-2)
    end

    test "someone who can see it but doesn't own it, or can't see it, can't add one" do
      {:ok, h, _} = Household.propose_grant(h0(), :dad, :visa, :mom)
      r = debt_reading("2026-09-27", 520_000, 2199, 15_000)
      assert {:error, :not_owner} = Balances.add_reading(h, :mom, :visa, r)
      assert {:error, :not_found} = Balances.add_reading(h, :kid, :visa, r)
      assert {:error, :not_found} = Balances.add_reading(h, :kid, :nope, r)
    end

    test "readings are validated by kind" do
      h = h0()

      for bad <- [
            reading("2026-02-30", 1),
            reading("yesterday", 1),
            %{on: "2026-09-27", balance: "12"},
            %{on: "2026-09-27", balance: 1, rate_bp: 10}
          ],
          do: assert({:error, :invalid_reading} = Balances.add_reading(h, :mom, :checking, bad))

      for bad <- [
            debt_reading("2026-09-27", -1, 2199, 0),
            debt_reading("2026-09-27", 1, 10_001, 0),
            debt_reading("2026-09-27", 1, 2199, -5),
            reading("2026-09-27", 1)
          ],
          do: assert({:error, :invalid_reading} = Balances.add_reading(h, :dad, :visa, bad))

      {:ok, h} = Household.add_item(h, :mom, :rent, %{note: "Rent", amount: -1})

      assert {:error, :not_a_balance} =
               Balances.add_reading(h, :mom, :rent, reading("2026-09-27", 1))
    end
  end

  describe "REQ-132 who reads which readings" do
    test "owners read all; someone it's shared with reads only the latest; others none" do
      h = h0()

      {:ok, h} =
        Balances.add_reading(h, :dad, :visa, debt_reading("2026-08-27", 540_000, 2199, 16_000))

      {:ok, h} =
        Balances.add_reading(h, :dad, :visa, debt_reading("2026-09-27", 520_000, 2199, 15_000))

      {:ok, h, _} = Household.propose_grant(h, :dad, :visa, :mom)

      assert {:ok, [_, _]} = Balances.readings(h, :dad, :visa)
      assert {:ok, [%{balance: 520_000}]} = Balances.readings(h, :mom, :visa)
      assert {:error, :not_found} = Balances.readings(h, :kid, :visa)
      assert %{balance: 520_000} = Balances.latest(h, :mom, :visa)
      assert Balances.latest(h, :kid, :visa) == nil

      {:ok, h} = Household.revoke_grant(h, :dad, :visa, :mom)
      assert {:error, :not_found} = Balances.readings(h, :mom, :visa)
    end

    test "a latest reading the member can't open is never returned" do
      h = h0()
      h = %{h | readings: %{visa: [:sealed]}}
      assert Balances.latest(h, :dad, :visa) == nil
    end
  end

  describe "REQ-134 accounts and debts are not money in or out" do
    test "they're left out of the distribution and can't be linked" do
      {:ok, h} = Alignment.add_value(h0(), :mom, :home, "Home")

      {:ok, h} =
        Household.add_item(h, :mom, :rent, %{note: "Rent", amount: -100, frequency: :monthly})

      d = Alignment.distribution(h, :mom)
      assert d.unlinked.count == 1
      assert {:error, :cannot_link_a_balance} = Alignment.link(h, :mom, :checking, :home)
    end
  end

  test "deleting removes readings; an owner's export carries them" do
    {:ok, h} =
      Balances.add_reading(h0(), :dad, :visa, debt_reading("2026-09-27", 520_000, 2199, 15_000))

    visa = Enum.find(Exit.export(h, :dad).items, &(&1.id == :visa))
    assert [%{balance: 520_000}] = visa.readings
    {:ok, h} = Exit.delete(h, :dad, :visa)
    refute Map.has_key?(h.readings, :visa)
  end

  test "REQ-135 interest for one month at the reading's rate, rounded" do
    # 5,200.00 at 21.99% = 95.29 a month
    assert Balances.monthly_interest(%{balance: 520_000, rate_bp: 2199}) == 9_529
    assert Balances.monthly_interest(%{balance: 0, rate_bp: 2199}) == 0
  end
end
