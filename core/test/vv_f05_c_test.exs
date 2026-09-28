defmodule Findependence.VVF05CTest do
  @moduledoc """
  VV-001 F-05/F-08 batch C (WI-057): acceptance criteria of REQ-137, 140, 142, 146, 148, 160, 161,
  162, and 173 that no earlier test asserted. Criteria are recorded in
  project/assurance/vv/acceptance-c.yaml.
  """
  use ExUnit.Case, async: true

  alias Findependence.{Attach, Balances, Exit, Household, Plans, Projection, Schedule}

  @today ~D[2026-09-27]
  @month {:every, 1, :month}

  defp ok({:ok, h}), do: h
  defp ok({:ok, h, _}), do: h

  defp item(on, frequency, amount \\ -100),
    do: %{attrs: %{note: "x", amount: amount, on: on, frequency: frequency}}

  defp add(h, m, id, note, amount, f, on \\ nil) do
    attrs = %{note: note, amount: amount, frequency: f}
    attrs = if on, do: Map.put(attrs, :on, on), else: attrs
    ok(Household.add_item(h, m, id, attrs))
  end

  describe "REQ-137 every N weeks, months, and years, for N other than those tested before" do
    test "every 3 weeks is every 21 days from the date" do
      assert Schedule.occurrences(
               item("2026-10-02", {:every, 3, :week}),
               ~D[2026-10-01],
               ~D[2026-12-01]
             ) == [~D[2026-10-02], ~D[2026-10-23], ~D[2026-11-13]]
    end

    test "every 2 months from the 31st: the same day, or the month's last day when shorter" do
      assert Schedule.occurrences(
               item("2026-08-31", {:every, 2, :month}),
               ~D[2026-08-01],
               ~D[2027-08-31]
             ) ==
               [
                 ~D[2026-08-31],
                 ~D[2026-10-31],
                 ~D[2026-12-31],
                 ~D[2027-02-28],
                 ~D[2027-04-30],
                 ~D[2027-06-30],
                 ~D[2027-08-31]
               ]
    end

    test "every 3 months from the 30th keeps the 30th, and February's last day" do
      assert Schedule.occurrences(
               item("2026-11-30", {:every, 3, :month}),
               ~D[2026-11-01],
               ~D[2027-12-31]
             ) == [~D[2026-11-30], ~D[2027-02-28], ~D[2027-05-30], ~D[2027-08-30], ~D[2027-11-30]]
    end

    test "every 2 years from February 29" do
      assert Schedule.occurrences(
               item("2024-02-29", {:every, 2, :year}),
               ~D[2024-01-01],
               ~D[2032-12-31]
             ) == [~D[2024-02-29], ~D[2026-02-28], ~D[2028-02-29], ~D[2030-02-28], ~D[2032-02-29]]
    end
  end

  describe "REQ-140 which money-out items the set-aside covers" do
    test "every 2 months, every 3 months, and yearly are covered at their monthly amounts; weekly, every 2 weeks, monthly, and one-off are not" do
      h =
        Household.new(["mom", "dad"])
        |> add("mom", "water", "Water", -9_000, {:every, 2, :month}, "2026-10-05")
        |> add("mom", "trash", "Trash", -12_000, {:every, 3, :month})
        |> add("mom", "domain", "Domain", -2_400, {:every, 1, :year})
        |> add("mom", "groceries", "Groceries", -15_000, {:every, 1, :week})
        |> add("mom", "sitter", "Sitter", -20_000, {:every, 2, :week})
        |> add("mom", "rent", "Rent", -200_000, @month)
        |> add("mom", "tv", "TV", -50_000, :one_off, "2026-10-10")

      %{total: total, items: items} = Schedule.set_asides(h, "mom")
      # 90 / 2 = 45; 120 / 3 = 40; 24 / 12 = 2
      assert Enum.map(items, fn {i, c} -> {i.id, c} end) ==
               [{"water", 4_500}, {"trash", 4_000}, {"domain", 200}]

      assert total == 8_700
    end
  end

  describe "REQ-142 plans are never counted in real totals" do
    test "a plan with every kind of step leaves the running balance, set-asides, and savings cover as they were" do
      h =
        Household.new(["dad"])
        |> add("dad", "pay", "Paycheck", 265_000, {:every, 2, :week}, "2026-10-02")
        |> add("dad", "rent", "Rent", -200_000, @month, "2026-10-01")

      h = ok(Balances.add_account(h, "dad", "chk", "Checking", :checking))
      h = ok(Balances.add_reading(h, "dad", "chk", %{on: "2026-09-27", balance: 100_000}))
      h = ok(Balances.add_account(h, "dad", "sav", "Savings", :savings))
      h = ok(Balances.add_reading(h, "dad", "sav", %{on: "2026-09-27", balance: 500_000}))

      with_plan =
        h
        |> then(&ok(Plans.new_plan(&1, "dad", "p", "What if")))
        |> then(&ok(Plans.add_step(&1, "dad", "p", {:switch_off, ["pay"], "2026-10"})))
        |> then(
          &ok(
            Plans.add_step(
              &1,
              "dad",
              "p",
              {:add, %{note: "Roof", amount: -900_000, frequency: {:every, 1, :year}}, "2026-10"}
            )
          )
        )
        |> then(
          &ok(
            Plans.add_step(
              &1,
              "dad",
              "p",
              {:borrow, %{amount: 500_000, rate_bp: 900, payment: 20_000}, "2026-10"}
            )
          )
        )

      assert Schedule.cash_flow(with_plan, "dad", @today, 60) ==
               Schedule.cash_flow(h, "dad", @today, 60)

      assert Schedule.set_asides(with_plan, "dad") == Schedule.set_asides(h, "dad")
      assert Projection.cover(with_plan, "dad") == Projection.cover(h, "dad")
    end
  end

  describe "REQ-146 the emergency fund" do
    defp fund_household do
      h =
        Household.new(["mom", "dad"])
        |> add("mom", "rent", "Rent", -100_000, @month)
        |> add("dad", "gym", "Gym", -50_000, @month)

      h = ok(Balances.add_account(h, "dad", "sav", "Dad's savings", :savings))
      ok(Balances.add_reading(h, "dad", "sav", %{on: "2026-09-27", balance: 300_000}))
    end

    test "a savings account shared with the member counts; money out they don't own doesn't" do
      h = fund_household()
      assert Projection.cover(h, "mom").months == nil
      h = ok(Household.propose_grant(h, "dad", "sav", "mom"))
      h = ok(Household.propose_grant(h, "dad", "gym", "mom"))
      c = Projection.cover(h, "mom")
      # 3,000 of savings she can see, against her own 1,000 a month; Dad's gym isn't hers
      assert c.savings == 300_000 and c.monthly_out == 100_000 and c.months == 3.0
      assert c.accounts == ["sav"]
    end

    test "no goal is supplied: none until the member sets one, and one member's goal is theirs alone" do
      h = fund_household()
      assert Plans.goals(h, "mom").fund_months == nil
      assert Projection.cover(h, "dad").goal == nil
      h = ok(Plans.set_fund_goal(h, "mom", 4))
      assert Plans.goals(h, "mom").fund_months == 4
      assert Plans.goals(h, "dad").fund_months == nil
      assert Projection.cover(h, "dad").goal == nil
    end
  end

  describe "REQ-148 shared plans" do
    defp plan_household do
      h =
        Household.new(["ana", "ben", "cy"])
        |> add("ana", "gym", "Gym", -5_000, @month)

      h = ok(Plans.new_plan(h, "ana", "p1", "Trip"))

      h =
        ok(
          Plans.add_step(
            h,
            "ana",
            "p1",
            {:add, %{note: "Hotel", amount: -50_000, frequency: :one_off}, "2026-11"}
          )
        )

      ok(Plans.add_step(h, "ana", "p1", {:switch_off, ["gym"], "2026-12"}))
    end

    test "proposed to two members: each becomes an owner only once both have agreed; each sees the plan meanwhile" do
      {:ok, h, pid} = Plans.propose_shared(plan_household(), "ana", "p1", "sp", ["ben", "cy"])
      assert h.items["sp"].owners == MapSet.new(["ana"])

      for m <- ["ben", "cy"] do
        assert [%{id: ^pid, attrs: %{kind: :plan, label: "Trip", steps: [_, _]}}] =
                 Household.pending(h, m)
      end

      h = ok(Household.consent(h, "ben", pid))
      assert h.items["sp"].owners == MapSet.new(["ana"])
      assert [%{attrs: %{kind: :plan}}] = Household.pending(h, "cy")
      h = ok(Household.consent(h, "cy", pid))
      assert h.items["sp"].owners == MapSet.new(["ana", "ben", "cy"])
    end

    test "with two owners, a member joins only with their own agreement and every current owner's" do
      {:ok, h, pid} = Plans.propose_shared(plan_household(), "ana", "p1", "sp", ["ben"])
      h = ok(Household.consent(h, "ben", pid))
      {:ok, h, pid2} = Household.propose_owners(h, "ana", "sp", ["ana", "ben", "cy"])
      # ben, a current owner, hasn't agreed: cy doesn't see it and can't agree yet
      assert Household.pending(h, "cy") == []
      assert {:error, :not_found} = Household.consent(h, "cy", pid2)
      h = ok(Household.consent(h, "ben", pid2))
      assert h.items["sp"].owners == MapSet.new(["ana", "ben"])
      # now cy sees the proposal and the plan, and joins only by agreeing
      assert [%{attrs: %{kind: :plan, steps: [_, _]}}] = Household.pending(h, "cy")
      h = ok(Household.consent(h, "cy", pid2))
      assert h.items["sp"].owners == MapSet.new(["ana", "ben", "cy"])
    end

    test "only the member's own plan can be proposed" do
      assert {:error, :not_found} =
               Plans.propose_shared(plan_household(), "ben", "p1", "sp", ["cy"])
    end

    test "a shared plan's steps never change" do
      {:ok, h, pid} = Plans.propose_shared(plan_household(), "ana", "p1", "sp", ["ben"])
      steps = h.items["sp"].attrs.steps
      assert length(steps) == 2

      h = ok(Household.consent(h, "ben", pid))
      assert h.items["sp"].attrs.steps == steps

      # changing, or deleting, the plan it was made from
      h =
        ok(
          Plans.add_step(
            h,
            "ana",
            "p1",
            {:borrow, %{amount: 100_000, rate_bp: 500, payment: 10_000}, "2026-12"}
          )
        )

      h = ok(Plans.remove_step(h, "ana", "p1", 1))
      assert h.items["sp"].attrs.steps == steps
      h = ok(Plans.delete_plan(h, "ana", "p1"))
      assert h.items["sp"].attrs.steps == steps

      # deleting an item a step names
      h = ok(Exit.delete(h, "ana", "gym"))
      assert h.items["sp"].attrs.steps == steps

      # no member can add or remove a step of it, as a plan of their own
      for m <- ["ana", "ben"] do
        assert {:error, :not_found} =
                 Plans.add_step(h, m, "sp", {:switch_off, ["gym"], "2026-12"})

        assert {:error, :not_found} = Plans.remove_step(h, m, "sp", 1)
      end

      # an owner leaving it
      h = ok(Household.relinquish(h, "ana", "sp"))
      assert h.items["sp"].attrs.steps == steps
    end
  end

  describe "REQ-160 which cash account an item goes through" do
    defp attach_household do
      h =
        Household.new(["dad", "mom", "kid"])
        |> add("dad", "rent", "Rent", -200_000, @month, "2026-10-01")
        |> add("mom", "pay", "Mom's paycheck", 198_000, @month, "2026-10-02")

      h = ok(Balances.add_account(h, "dad", "chk", "Checking", :checking))
      h = ok(Balances.add_account(h, "dad", "box", "Cash box", :other))
      h = ok(Balances.add_account(h, "dad", "ira", "IRA", :ira))
      ok(Balances.add_account(h, "mom", "msav", "Mom's savings", :savings))
    end

    test "an 'other' account can be chosen; an IRA can't" do
      h = ok(Attach.attach(attach_household(), "dad", "rent", "box"))
      assert Attach.attached(h, "dad") == %{"rent" => "box"}

      assert Attach.attach(attach_household(), "dad", "rent", "ira") ==
               {:error, :not_a_cash_account}
    end

    test "an account someone shares with the member can be chosen" do
      h = ok(Household.propose_grant(attach_household(), "mom", "msav", "dad"))
      h = ok(Attach.attach(h, "dad", "rent", "msav"))
      assert Attach.attached(h, "dad") == %{"rent" => "msav"}
    end

    test "changing to a different account replaces the first" do
      h = ok(Attach.attach(attach_household(), "dad", "rent", "chk"))
      h = ok(Attach.attach(h, "dad", "rent", "box"))
      assert Attach.attached(h, "dad") == %{"rent" => "box"}
    end

    test "leaving removes all of the member's own, even where the item and account remain" do
      h = attach_household()
      h = ok(Household.propose_grant(h, "mom", "pay", "kid"))
      h = ok(Household.propose_grant(h, "mom", "msav", "kid"))
      h = ok(Attach.attach(h, "kid", "pay", "msav"))
      assert Attach.attached(h, "kid") == %{"pay" => "msav"}
      {:ok, h} = Exit.leave(h, "kid")
      refute Map.has_key?(h.goals, "kid")
      assert Map.has_key?(h.items, "pay") and Map.has_key?(h.items, "msav")
    end
  end

  describe "REQ-161 and REQ-173 horizons" do
    defp dated(on), do: add(Household.new(["ana"]), "ana", "x", "X", -100, :one_off, on)

    test "fourteen days: today to today + 13" do
      days = Schedule.cash_flow(dated("2026-10-10"), "ana", @today, 14).days
      assert hd(days).date == @today and List.last(days).date == ~D[2026-10-10]
      assert List.last(days).entries != []

      assert Schedule.cash_flow(dated("2026-10-11"), "ana", @today, 14).days
             |> Enum.all?(&(&1.entries == []))
    end

    test "sixty days: today to today + 59" do
      days = Schedule.cash_flow(dated("2026-11-25"), "ana", @today, 60).days
      assert length(days) == 60 and List.last(days).date == ~D[2026-11-25]
      assert List.last(days).entries != []
    end
  end

  describe "REQ-162 the next twelve months" do
    test "a debt reaching payoff stops: it falls to zero and stays there, with no more interest" do
      h = Household.new(["dad"])
      h = ok(Balances.add_debt(h, "dad", "loan", "Small loan", :loan))

      h =
        ok(
          Balances.add_reading(h, "dad", "loan", %{
            on: "2026-09-27",
            balance: 50_000,
            rate_bp: 1200,
            min_payment: 20_000
          })
        )

      [d] = Projection.project(h, "dad", @today).debts
      # 500 at 12%: +5.00 -200 = 305.00; +3.05 -200 = 108.05; +1.08, then the last 109.13
      assert Enum.take(d.months, 3) == [30_500, 10_805, 0]
      assert Enum.drop(d.months, 3) == List.duplicate(0, 9)
      assert d.paid_off == "2026-12"
      assert d.interest == 500 + 305 + 108
    end

    test "a debt someone shares with the member is one of their debts; one they can't see isn't" do
      h = Household.new(["dad", "mom"])
      h = ok(Balances.add_debt(h, "dad", "loan", "Car loan", :loan))

      h =
        ok(
          Balances.add_reading(h, "dad", "loan", %{
            on: "2026-09-27",
            balance: 900_000,
            rate_bp: 500,
            min_payment: 30_000
          })
        )

      assert Projection.project(h, "mom", @today).debts == []
      h = ok(Household.propose_grant(h, "dad", "loan", "mom"))
      assert [%{id: "loan"} = d] = Projection.project(h, "mom", @today).debts
      assert d == hd(Projection.project(h, "dad", @today).debts)
    end

    test "an undated one-off is in no month; a dated one-off only in its own" do
      h =
        Household.new(["dad"])
        |> add("dad", "tv", "TV", -50_000, :one_off)
        |> add("dad", "sofa", "Sofa", -80_000, :one_off, "2027-01-15")

      months = Projection.project(h, "dad", @today).months

      assert Enum.map(months, & &1.out) ==
               [0, 0, 0, -80_000, 0, 0, 0, 0, 0, 0, 0, 0]
    end
  end
end
