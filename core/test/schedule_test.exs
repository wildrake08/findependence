defmodule Findependence.ScheduleTest do
  use ExUnit.Case, async: true

  alias Findependence.{Balances, Household, Schedule}

  defp item(on, frequency, amount \\ -100),
    do: %{attrs: %{note: "x", amount: amount, on: on, frequency: frequency}}

  defp dates(i, from, to),
    do: Schedule.occurrences(i, ~D[2026-01-01] |> then(fn _ -> from end), to)

  describe "REQ-137 dates from a date and an interval" do
    test "monthly on the 31st lands on each month's last day, including a leap February" do
      assert dates(item("2027-12-31", {:every, 1, :month}), ~D[2027-12-01], ~D[2028-04-30]) ==
               [~D[2027-12-31], ~D[2028-01-31], ~D[2028-02-29], ~D[2028-03-31], ~D[2028-04-30]]
    end

    test "every 2 weeks is every 14 days from the date, never before it" do
      assert dates(item("2026-10-02", {:every, 2, :week}), ~D[2026-09-01], ~D[2026-11-01]) ==
               [~D[2026-10-02], ~D[2026-10-16], ~D[2026-10-30]]
    end

    test "twice a year, yearly, one-off, irregular, and no date" do
      assert dates(item("2026-01-15", {:every, 6, :month}), ~D[2026-01-01], ~D[2027-12-31]) ==
               [~D[2026-01-15], ~D[2026-07-15], ~D[2027-01-15], ~D[2027-07-15]]

      assert dates(item("2024-02-29", {:every, 1, :year}), ~D[2025-01-01], ~D[2028-12-31]) ==
               [~D[2025-02-28], ~D[2026-02-28], ~D[2027-02-28], ~D[2028-02-29]]

      assert dates(item("2026-10-05", :one_off), ~D[2026-10-01], ~D[2026-10-31]) == [
               ~D[2026-10-05]
             ]

      assert dates(item("2026-10-05", :one_off), ~D[2026-10-06], ~D[2026-10-31]) == []
      assert dates(item("2026-10-05", :irregular), ~D[2026-01-01], ~D[2027-01-01]) == []

      assert dates(%{attrs: %{amount: -1, frequency: :monthly}}, ~D[2026-01-01], ~D[2027-01-01]) ==
               []

      assert dates(item("not a date", :monthly), ~D[2026-01-01], ~D[2027-01-01]) == []
    end

    test "legacy frequency values schedule like their intervals" do
      assert dates(item("2026-10-01", :weekly), ~D[2026-10-01], ~D[2026-10-20]) ==
               [~D[2026-10-01], ~D[2026-10-08], ~D[2026-10-15]]
    end
  end

  defp household do
    h = Household.new([:mom, :dad, :kid])
    {:ok, h} = Balances.add_account(h, :mom, :checking, "Joint checking", :checking)
    {:ok, h, _} = Household.propose_owners(h, :mom, :checking, [:mom, :dad])
    {:ok, h} = Balances.add_account(h, :mom, :savings, "Savings", :savings)

    for {id, note, amount, f, on} <- [
          {:mortgage, "Mortgage", -224_000, {:every, 1, :month}, "2026-10-01"},
          {:pay, "Mom's paycheck", 198_000, {:every, 2, :week}, "2026-10-02"},
          {:car, "Car insurance", -114_000, {:every, 6, :month}, "2026-10-15"},
          {:repairs, "Home repairs", -240_000, :irregular, nil}
        ],
        reduce: h do
      h ->
        attrs = %{note: note, amount: amount, frequency: f}
        attrs = if on, do: Map.put(attrs, :on, on), else: attrs
        {:ok, h} = Household.add_item(h, :mom, id, attrs)
        {:ok, h, _} = Household.propose_owners(h, :mom, id, [:mom, :dad])
        h
    end
  end

  describe "REQ-138/139 running balance from checking readings" do
    test "no checking reading: dated items listed, no balance" do
      %{start: nil, days: days} = Schedule.cash_flow(household(), :mom, ~D[2026-10-01], 3)

      assert [%{date: ~D[2026-10-01], balance: nil, entries: [{%{id: :mortgage}, -224_000}]} | _] =
               days
    end

    test "starts from the latest reading and applies only what comes after its date" do
      {:ok, h} =
        Balances.add_reading(household(), :dad, :checking, %{on: "2026-10-01", balance: 250_000})

      %{start: start, days: days} = Schedule.cash_flow(h, :mom, ~D[2026-10-01], 16)
      assert start == %{balance: 250_000, on: ~D[2026-10-01], accounts: [:checking]}
      by = Map.new(days, &{&1.date, &1.balance})
      # the mortgage on the reading's own date is already in the reading
      assert by[~D[2026-10-01]] == 250_000
      assert by[~D[2026-10-02]] == 250_000 + 198_000
      assert by[~D[2026-10-15]] == 250_000 + 198_000 - 114_000
      assert by[~D[2026-10-16]] == 250_000 + 2 * 198_000 - 114_000
    end

    test "an older reading counts what happened between it and today" do
      {:ok, h} =
        Balances.add_reading(household(), :mom, :checking, %{on: "2026-09-30", balance: 250_000})

      %{days: [first | _]} = Schedule.cash_flow(h, :mom, ~D[2026-10-02], 1)
      # the mortgage on the 1st and the paycheck on the 2nd both apply
      assert first.balance == 250_000 - 224_000 + 198_000
    end

    test "days below zero can be found; savings and other members' accounts don't count" do
      {:ok, h} =
        Balances.add_reading(household(), :mom, :checking, %{on: "2026-09-30", balance: 100_000})

      {:ok, h} = Balances.add_reading(h, :mom, :savings, %{on: "2026-09-30", balance: 900_000})
      %{start: start, days: days} = Schedule.cash_flow(h, :mom, ~D[2026-10-01], 3)
      assert start.balance == 100_000
      assert [%{date: ~D[2026-10-01], balance: -124_000}, %{balance: 74_000}, _] = days
      # the kid can see none of it
      assert %{start: nil, days: kid_days} = Schedule.cash_flow(h, :kid, ~D[2026-10-01], 3)
      assert Enum.all?(kid_days, &(&1.entries == []))
    end

    test "two checking accounts: summed, from the most recent reading's date" do
      h = household()
      {:ok, h} = Balances.add_account(h, :dad, :dad_chk, "Dad's checking", :checking)
      {:ok, h, _} = Household.propose_grant(h, :dad, :dad_chk, :mom)
      {:ok, h} = Balances.add_reading(h, :mom, :checking, %{on: "2026-09-28", balance: 100_000})
      {:ok, h} = Balances.add_reading(h, :dad, :dad_chk, %{on: "2026-09-30", balance: 50_000})
      %{start: start} = Schedule.cash_flow(h, :mom, ~D[2026-10-01], 1)
      assert start == %{balance: 150_000, on: ~D[2026-09-30], accounts: [:checking, :dad_chk]}
    end
  end

  test "REQ-140 set-asides for money out less often than monthly" do
    # money coming in a few times a year (a yearly bonus) is never a set-aside
    {:ok, h} =
      Household.add_item(household(), :mom, :bonus, %{
        note: "Bonus",
        amount: 300_000,
        frequency: {:every, 1, :year}
      })

    %{total: total, items: items} = Schedule.set_asides(h, :mom)
    # repairs 2,400 a year = 200 a month; car insurance 1,140 twice a year = 190 a month
    assert Enum.map(items, fn {i, c} -> {i.id, c} end) == [{:repairs, 20_000}, {:car, 19_000}]
    assert total == 39_000
    assert Schedule.set_asides(household(), :kid) == %{total: 0, items: []}
  end
end
