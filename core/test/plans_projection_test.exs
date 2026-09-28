defmodule Findependence.PlansProjectionTest do
  use ExUnit.Case, async: true

  alias Findependence.{Alignment, Balances, Exit, Household, Plans, Projection, Schedule}

  @today ~D[2026-09-27]
  @month {:every, 1, :month}

  # Dad and Mom; Dad's paycheck, a health premium that depends on his job, a joint mortgage, a dated
  # one-off repair; joint checking with 1,000; Mom's savings; Dad's Visa.
  defp h0 do
    h = Household.new([:mom, :dad, :kid])

    add = fn h, m, id, note, amt, f, on ->
      attrs = %{note: note, amount: amt, frequency: f}
      attrs = if on, do: Map.put(attrs, :on, on), else: attrs
      {:ok, h} = Household.add_item(h, m, id, attrs)
      h
    end

    h =
      h
      |> add.(:dad, :pay, "Dad's paycheck", 265_000, {:every, 2, :week}, "2026-10-02")
      |> add.(:dad, :health, "Health premium", -40_000, @month, nil)
      |> add.(:dad, :mortgage, "Mortgage", -224_000, @month, "2026-10-01")
      |> add.(:dad, :repair, "Car repair", -80_000, :one_off, "2026-11-10")

    {:ok, h, _} = Household.propose_owners(h, :dad, :mortgage, [:dad, :mom])
    {:ok, h} = Balances.add_account(h, :dad, :chk, "Joint checking", :checking)
    {:ok, h, _} = Household.propose_owners(h, :dad, :chk, [:dad, :mom])
    {:ok, h} = Balances.add_reading(h, :dad, :chk, %{on: "2026-09-27", balance: 100_000})
    {:ok, h} = Balances.add_account(h, :mom, :sav, "Savings", :savings)
    {:ok, h} = Balances.add_reading(h, :mom, :sav, %{on: "2026-09-27", balance: 600_000})
    {:ok, h} = Balances.add_debt(h, :dad, :visa, "Visa", :card)

    {:ok, h} =
      Balances.add_reading(h, :dad, :visa, %{
        on: "2026-09-27",
        balance: 620_000,
        rate_bp: 2499,
        min_payment: 19_000
      })

    {:ok, h} = Plans.mark(h, :dad, :health, :pay)
    h
  end

  describe "REQ-141 the next twelve months" do
    test "months start after this one; cash runs from the account balances; one-offs land in their month" do
      p = Projection.project(h0(), :dad, @today)
      assert Enum.map(p.months, & &1.month) |> Enum.take(2) == ["2026-10", "2026-11"]
      assert length(p.months) == 12
      assert p.start == %{cash: 100_000, on: "2026-09-27", accounts: [:chk]}
      # paycheck 2,650 every two weeks = 5,741.67 a month; out 2,240 + 400
      [oct, nov | _] = p.months
      assert oct == %{month: "2026-10", in: 574_167, out: -264_000, net: 310_167, cash: 410_167}
      assert nov.out == -344_000 and nov.cash == 410_167 + 230_167
    end

    test "debts grow by a month's interest and fall by the minimum" do
      [visa] = Projection.project(h0(), :dad, @today).debts
      # 6,200 at 24.99%: interest 129.115, rounded half away to 129.12, minus 190 = 6,139.12
      assert hd(visa.months) == 613_912
      assert visa.paid_off == nil and visa.interest > 0 and visa.planned == false
    end

    test "only what the member owns counts, and what they can see; the kid sees nothing" do
      p = Projection.project(h0(), :kid, @today)
      assert p.start == nil and p.debts == []
      assert Enum.all?(p.months, &(&1.in == 0 and &1.out == 0 and &1.cash == nil))
    end
  end

  describe "REQ-142..144 plans, marks, and switching off a job" do
    test "a plan: the job stops (taking the marked premium with it), a new cost, and borrowing" do
      {:ok, h} = Plans.new_plan(h0(), :dad, :p1, "If Dad's job stops")
      {:ok, h} = Plans.add_step(h, :dad, :p1, {:switch_off, [:pay], "2026-11"})

      {:ok, h} =
        Plans.add_step(
          h,
          :dad,
          :p1,
          {:add, %{note: "Marketplace premium", amount: -60_000, frequency: @month}, "2026-11"}
        )

      {:ok, h} =
        Plans.add_step(
          h,
          :dad,
          :p1,
          {:borrow, %{amount: 500_000, rate_bp: 900, payment: 20_000}, "2026-12"}
        )

      plan = Plans.plans(h, :dad)[:p1]
      [oct, nov, dec, jan | _] = Projection.project(h, :dad, @today, plan).months
      assert oct.cash == 410_167
      # no paycheck; the premium stops too (marked); mortgage, new premium, repair
      assert nov.net == -224_000 - 60_000 - 80_000 and nov.cash == 46_167
      # 5,000 borrowed, no payment in its first month
      assert dec.net == 500_000 - 224_000 - 60_000 and dec.cash == 262_167
      # first payment of 200
      assert jan.net == -224_000 - 60_000 - 20_000 and jan.cash == -41_833
      loan = Enum.find(Projection.project(h, :dad, @today, plan).debts, & &1.planned)
      # 5,000 at 9%: 37.50 of interest, then 200 paid
      assert Enum.at(loan.months, 3) == 483_750

      # the plan leaves real totals alone
      assert Projection.project(h, :dad, @today) == Projection.project(h0(), :dad, @today)
      assert Alignment.distribution(h, :dad) == Alignment.distribution(h0(), :dad)
    end

    test "a planned one-off happens once, in the month it's planned from" do
      {:ok, h} = Plans.new_plan(h0(), :dad, :p1, "Tools")

      {:ok, h} =
        Plans.add_step(
          h,
          :dad,
          :p1,
          {:add, %{note: "Tools", amount: -150_000, frequency: :one_off}, "2026-11"}
        )

      [b_oct, b_nov, b_dec | _] = Projection.project(h, :dad, @today).months
      [oct, nov, dec | _] = Projection.project(h, :dad, @today, Plans.plans(h, :dad)[:p1]).months
      assert oct.net == b_oct.net
      assert nov.net == b_nov.net - 150_000 and nov.cash == b_nov.cash - 150_000
      assert dec.net == b_dec.net and dec.cash == b_dec.cash - 150_000
    end

    test "steps are checked, removable, and plans are private" do
      {:ok, h} = Plans.new_plan(h0(), :dad, :p1, "Plan")

      assert {:error, :invalid_step} =
               Plans.add_step(h, :dad, :p1, {:switch_off, [:sav], "2026-11"})

      # another member can't add a step to Dad's plan, or tell that it exists (VV-001 F-06: this was vacuous)
      assert {:error, :not_found} = Plans.add_step(h, :mom, :p1, {:switch_off, [:pay], "2026-11"})

      assert {:error, :invalid_step} = Plans.add_step(h, :dad, :p1, {:switch_off, [:pay], "Nov"})

      assert {:error, :invalid_step} =
               Plans.add_step(
                 h,
                 :dad,
                 :p1,
                 {:add, %{note: "", amount: -1, frequency: @month}, "2026-11"}
               )

      assert {:error, :invalid_step} =
               Plans.add_step(
                 h,
                 :dad,
                 :p1,
                 {:borrow, %{amount: 1, rate_bp: 20_000, payment: 1}, "2026-11"}
               )

      assert {:error, :not_found} =
               Plans.add_step(h, :mom, :p1, {:switch_off, [:mortgage], "2026-11"})

      {:ok, h} = Plans.add_step(h, :dad, :p1, {:switch_off, [:mortgage], "2026-11"})
      assert [%{n: 1}] = Plans.plans(h, :dad)[:p1].steps
      assert Plans.plans(h, :mom) == %{}
      {:ok, h} = Plans.remove_step(h, :dad, :p1, 1)
      assert Plans.plans(h, :dad)[:p1].steps == []
      {:ok, h} = Plans.delete_plan(h, :dad, :p1)
      assert Plans.plans(h, :dad) == %{}
      assert {:error, :invalid_plan} = Plans.new_plan(h, :dad, :p2, "  ")
    end

    test "marks: only between items the member owns, on an income, private" do
      h = h0()
      assert Plans.depends(h, :dad) == [{:health, :pay}]
      assert Plans.depends(h, :mom) == []
      assert {:error, :not_income} = Plans.mark(h, :dad, :pay, :health)
      assert {:error, :already_marked} = Plans.mark(h, :dad, :health, :pay)
      assert {:error, :not_found} = Plans.mark(h, :mom, :health, :pay)
      {:ok, h} = Plans.unmark(h, :dad, :health, :pay)
      assert Plans.depends(h, :dad) == []
    end

    test "deleting an item removes marks naming it; leaving removes the leaver's plans, marks, and goals" do
      {:ok, h} = Exit.delete(h0(), :dad, :health)
      assert Plans.depends(h, :dad) == []
      h = h0()
      {:ok, h} = Plans.new_plan(h, :mom, :p, "Mom's plan")
      {:ok, h} = Plans.set_fund_goal(h, :mom, 3)
      {:ok, h} = Exit.delete(h, :mom, :sav)
      {:ok, h} = Household.relinquish(h, :mom, :mortgage)
      {:ok, h} = Household.relinquish(h, :mom, :chk)
      {:ok, h} = Exit.leave(h, :mom)
      refute Map.has_key?(h.plans, :mom) or Map.has_key?(h.goals, :mom)
    end
  end

  describe "REQ-145 debt payoff" do
    test "months and interest at a payment; an extra amount clears it sooner for less; too little never clears" do
      {:ok, m1, i1} = Projection.payoff(620_000, 2499, 19_000)
      {:ok, m2, i2} = Projection.payoff(620_000, 2499, 29_000)
      assert m2 < m1 and i2 < i1 and m1 > 12
      assert Projection.payoff(620_000, 2499, 12_000) == :never
      assert Projection.payoff(0, 2499, 100) == {:ok, 0, 0}
      assert Projection.payoff(100_000, 0, 30_000) == {:ok, 4, 0}
    end
  end

  describe "REQ-146/147 goals" do
    test "how long savings would cover money out, against the member's own goal" do
      {:ok, h} = Plans.set_fund_goal(h0(), :mom, 3)
      # Mom's savings 6,000; her money out: the joint mortgage, 2,240 a month
      assert Projection.cover(h, :mom) == %{
               savings: 600_000,
               monthly_out: 224_000,
               months: 2.7,
               goal: 3,
               accounts: [:sav]
             }

      # Dad can't see the savings
      assert Projection.cover(h, :dad).months == nil
      # a one-off doesn't recur, so it isn't part of monthly money out
      {:ok, h} =
        Household.add_item(h, :mom, :tv, %{note: "TV", amount: -120_000, frequency: :one_off})

      assert Projection.cover(h, :mom).monthly_out == 224_000
      assert {:error, :invalid_goal} = Plans.set_fund_goal(h, :mom, 0)
    end

    test "a set-aside rate on money in linked to a value; one-offs and other members' links don't count" do
      h = h0()
      {:ok, h} = Alignment.add_value(h, :dad, :biz, "Side business")

      {:ok, h} =
        Household.add_item(h, :dad, :etsy, %{
          note: "Shop sales",
          amount: 50_000,
          frequency: @month
        })

      {:ok, h} =
        Household.add_item(h, :dad, :fair, %{
          note: "Craft fair",
          amount: 90_000,
          frequency: :one_off
        })

      {:ok, h} = Alignment.link(h, :dad, :etsy, :biz)
      {:ok, h} = Alignment.link(h, :dad, :fair, :biz)
      {:ok, h} = Plans.set_aside(h, :dad, :biz, 2500)

      assert [%{value_id: :biz, rate_bp: 2500, monthly_in: 50_000, set_aside: 12_500}] =
               Projection.set_asides(h, :dad)

      assert Projection.set_asides(h, :mom) == []
      assert {:error, :not_found} = Plans.set_aside(h, :mom, :biz, 2500)
      {:ok, h} = Plans.set_aside(h, :dad, :biz, nil)
      assert Projection.set_asides(h, :dad) == []
    end
  end

  describe "REQ-148 shared plans by consent" do
    test "a snapshot item; the named member joins only by agreeing; it isn't money" do
      {:ok, h} = Plans.new_plan(h0(), :dad, :p1, "Side business")

      {:ok, h} =
        Plans.add_step(
          h,
          :dad,
          :p1,
          {:add, %{note: "Shop sales", amount: 50_000, frequency: @month}, "2026-11"}
        )

      {:ok, h, pid} = Plans.propose_shared(h, :dad, :p1, :sp1, [:mom])
      assert h.items[:sp1].owners == MapSet.new([:dad])

      assert [%{attrs: %{kind: :plan, label: "Side business", steps: [%{n: 1}]}}] =
               Household.pending(h, :mom)

      {:ok, h} = Household.consent(h, :mom, pid)
      assert h.items[:sp1].owners == MapSet.new([:dad, :mom])

      assert Alignment.distribution(h, :mom).unlinked.count ==
               Alignment.distribution(h0(), :mom).unlinked.count

      assert Schedule.set_asides(h, :dad).items |> Enum.all?(fn {i, _} -> i.id != :sp1 end)

      assert {:error, :cannot_link_a_plan} =
               (fn ->
                  {:ok, h} = Alignment.add_value(h, :dad, :v, "V")
                  Alignment.link(h, :dad, :sp1, :v)
                end).()

      assert {:error, :not_a_member} = Plans.propose_shared(h, :dad, :p1, :sp2, [:dad])
    end
  end
end
