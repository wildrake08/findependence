defmodule Findependence.RetirementTest do
  use ExUnit.Case, async: true
  import Findependence.TestJoint

  alias Findependence.{Alignment, Balances, Exit, Household, Projection, Retirement, Schedule}

  @today ~D[2026-11-15]

  # Dad's 401(k) with 10,000; joint checking with 1,000; Mom's savings; Mom's IRA, which Dad can't see.
  defp h0 do
    h = Household.new([:mom, :dad])
    {:ok, h} = Balances.add_account(h, :dad, :k401, "Dad's 401(k)", :retirement_401k)
    {:ok, h} = Balances.add_reading(h, :dad, :k401, %{on: "2026-11-01", balance: 1_000_000})
    {:ok, h} = Balances.add_account(h, :dad, :chk, "Joint checking", :checking)
    h = joint!(h, :dad, :chk, [:dad, :mom])
    {:ok, h} = Balances.add_reading(h, :dad, :chk, %{on: "2026-11-01", balance: 100_000})
    {:ok, h} = Balances.add_account(h, :mom, :sav, "Savings", :savings)
    {:ok, h} = Balances.add_reading(h, :mom, :sav, %{on: "2026-11-01", balance: 600_000})
    {:ok, h} = Balances.add_account(h, :mom, :ira, "Mom's IRA", :ira)
    {:ok, h} = Balances.add_reading(h, :mom, :ira, %{on: "2026-11-01", balance: 5_000_000})

    {:ok, h} =
      Household.add_item(h, :dad, :rent, %{
        note: "Rent",
        amount: -150_000,
        frequency: {:every, 1, :month}
      })

    h
  end

  # born 1961, retiring at 67: January 2028 is 14 months away (November 2026 to December 2027)
  defp dad(h \\ h0(), extra \\ []) do
    Enum.reduce(
      [birth_year: 1961, retire_age: 67, return_bp: 1200] ++ extra,
      h,
      fn {f, v}, h ->
        {:ok, h} = Retirement.set(h, :dad, f, v)
        h
      end
    )
    |> then(fn h ->
      {:ok, h} = Retirement.set_contribution(h, :dad, :k401, 10_000)
      h
    end)
  end

  describe "REQ-149 retirement accounts" do
    test "are accounts with readings, but never cash" do
      h = h0()
      assert Balances.retirement?(h.items[:k401]) and Balances.retirement?(h.items[:ira])
      refute Balances.retirement?(h.items[:chk]) or Balances.retirement?(h.items[:sav])
      assert Balances.latest(h, :dad, :k401).balance == 1_000_000

      # the next twelve months start from checking and savings only
      assert Projection.project(h, :mom, @today).start.cash == 100_000 + 600_000
      assert Projection.project(h, :mom, @today).start.accounts == [:chk, :sav]
      # months of cover count savings only; the running balance counts checking only
      assert Projection.cover(h, :mom).savings == 600_000
      assert Schedule.cash_flow(h, :dad, @today, 1).start.balance == 100_000
      # not money in or out
      {:ok, without} = Exit.delete(h, :dad, :k401)
      assert Alignment.distribution(h, :dad) == Alignment.distribution(without, :dad)
    end
  end

  describe "REQ-150 assumptions" do
    test "are private, validated, clearable, and never filled in" do
      h = h0()

      assert Retirement.settings(h, :dad) == %{
               birth_year: nil,
               retire_age: nil,
               return_bp: nil,
               ss_monthly: nil,
               target_monthly: nil,
               contributions: %{}
             }

      h = dad(h)
      assert Retirement.settings(h, :dad).retire_age == 67
      # Mom's are untouched: each member's are their own
      assert Retirement.settings(h, :mom).retire_age == nil

      for {f, bad} <- [
            birth_year: 1800,
            retire_age: 39,
            retire_age: 91,
            return_bp: -501,
            return_bp: 1_501,
            ss_monthly: -1,
            target_monthly: "5000",
            retire_age: 67.5
          ],
          do: assert(Retirement.set(h, :dad, f, bad) == {:error, :invalid_retirement})

      assert {:ok, _} = Retirement.set(h, :dad, :return_bp, -500)
      assert {:ok, _} = Retirement.set(h, :dad, :return_bp, 1_500)
      assert Retirement.set(h, :dad, :shoe_size, 9) == {:error, :invalid_retirement}

      {:ok, h2} = Retirement.set(h, :dad, :retire_age, nil)
      assert Retirement.settings(h2, :dad).retire_age == nil
      # other goals are kept alongside
      {:ok, h3} = Findependence.Plans.set_fund_goal(h, :dad, 3)
      assert Retirement.settings(h3, :dad).retire_age == 67
      assert Findependence.Plans.goals(h3, :dad).fund_months == 3
    end

    test "contributions go only to retirement accounts the member can see" do
      h = h0()
      assert Retirement.set_contribution(h, :dad, :chk, 5_000) == {:error, :not_found}
      assert Retirement.set_contribution(h, :dad, :ira, 5_000) == {:error, :not_found}
      assert Retirement.set_contribution(h, :dad, :nope, 5_000) == {:error, :not_found}
      assert Retirement.set_contribution(h, :dad, :k401, 0) == {:error, :invalid_retirement}
      assert Retirement.set_contribution(h, :dad, :k401, -5) == {:error, :invalid_retirement}
      {:ok, h} = Retirement.set_contribution(h, :dad, :k401, 5_000)
      assert Retirement.settings(h, :dad).contributions == %{k401: 5_000}
      {:ok, h} = Retirement.set_contribution(h, :dad, :k401, nil)
      assert Retirement.settings(h, :dad).contributions == %{}
    end

    test "deleting the account removes contributions to it; leaving removes the assumptions" do
      h = dad()
      {:ok, h2} = Exit.delete(h, :dad, :k401)
      assert Retirement.settings(h2, :dad).contributions == %{}
      assert Retirement.settings(h2, :dad).retire_age == 67

      # Mom can leave once she owns nothing; her assumptions go with her
      {:ok, h} = Retirement.set(h, :mom, :retire_age, 65)
      {:ok, h} = Exit.delete(h, :mom, :sav)
      {:ok, h} = Exit.delete(h, :mom, :ira)
      {:ok, h} = Household.relinquish(h, :mom, :chk)
      {:ok, h} = Exit.leave(h, :mom)
      refute Map.has_key?(h.goals, :mom)
    end
  end

  describe "REQ-151 the projection" do
    test "needs a birth year, a retirement age, and a return" do
      assert Retirement.project(h0(), :dad, @today) ==
               {:missing, [:birth_year, :retire_age, :return_bp]}

      {:ok, h} = Retirement.set(h0(), :dad, :birth_year, 1961)
      assert Retirement.project(h, :dad, @today) == {:missing, [:retire_age, :return_bp]}
    end

    test "month by month from the latest balances to January of the retirement year" do
      p = Retirement.project(dad(), :dad, @today)
      assert p.start == %{balance: 1_000_000, accounts: [:k401], read: [:k401]}
      assert p.monthly_contribution == 10_000
      assert p.retire_year == 2028

      # 1% a month: November 10,000.00 + 100.00 + 100.00; December 10,200.00 + 102.00 + 100.00
      assert [r26, r27] = p.rows

      assert r26 == %{
               year: 2026,
               age: 65,
               contributed: 20_000,
               growth: 20_200,
               balance: 1_040_200
             }

      # computed independently (a separate script, half-cents rounded away from zero)
      assert r27 == %{
               year: 2027,
               age: 66,
               contributed: 120_000,
               growth: 138_747,
               balance: 1_298_947
             }

      assert p.at_retirement == 1_298_947
    end

    test "only the retirement accounts the member can see, and their own contributions" do
      # Mom sees her IRA only; Dad's contribution to his 401(k) isn't hers
      {:ok, h} = Retirement.set(dad(), :mom, :birth_year, 1963)
      {:ok, h} = Retirement.set(h, :mom, :retire_age, 65)
      {:ok, h} = Retirement.set(h, :mom, :return_bp, 0)
      p = Retirement.project(h, :mom, @today)
      assert p.start.accounts == [:ira] and p.monthly_contribution == 0
      assert p.at_retirement == 5_000_000

      # once shared, Dad sees Mom's IRA too, though only Mom's contribution is hers to set
      {:ok, h, _} = Household.propose_grant(h, :mom, :ira, :dad)
      p = Retirement.project(h, :dad, @today)
      assert p.start == %{balance: 6_000_000, accounts: [:ira, :k401], read: [:ira, :k401]}

      # a contribution Dad set while he could see the IRA stops counting once it's no longer shared
      {:ok, h} = Retirement.set_contribution(h, :dad, :ira, 20_000)
      assert Retirement.project(h, :dad, @today).monthly_contribution == 30_000
      {:ok, h} = Household.revoke_grant(h, :mom, :ira, :dad)
      p = Retirement.project(h, :dad, @today)
      assert p.start.accounts == [:k401] and p.monthly_contribution == 10_000
    end

    test "an account without a balance yet counts from zero; retiring this year or earlier means no rows" do
      {:ok, h} = Balances.add_account(dad(), :dad, :new401, "New 401(k)", :retirement_401k)
      assert Retirement.project(h, :dad, @today).start.read == [:k401]

      {:ok, h} = Retirement.set(dad(), :dad, :retire_age, 65)
      p = Retirement.project(h, :dad, @today)
      assert p.rows == [] and p.at_retirement == 1_000_000
    end
  end

  describe "REQ-152 compared with the member's own target" do
    test "how long the difference could be paid" do
      h = dad(h0(), target_monthly: 300_000, ss_monthly: 200_000)
      p = Retirement.project(h, :dad, @today)
      assert p.gap == 100_000

      # from 12,989.47 at 1% a month, paying 1,000.00 a month: 13 full months (computed separately)
      assert p.lasts == {:months, 13}

      # with no growth, exactly 10 months from 10,000.00 (it reaches zero, so the tenth is paid in full)
      h0r = dad(h0(), target_monthly: 300_000, ss_monthly: 200_000)
      {:ok, h0r} = Retirement.set_contribution(h0r, :dad, :k401, nil)

      assert Retirement.project(h0r, :dad, @today, %{return_bp: 0, retire_age: 65}).lasts ==
               {:months, 10}
    end

    test "no target means no comparison; Social Security at or over the target means nothing to pay" do
      p = Retirement.project(dad(), :dad, @today)
      assert p.gap == nil and p.lasts == nil

      h = dad(h0(), target_monthly: 200_000, ss_monthly: 200_000)
      assert Retirement.project(h, :dad, @today).lasts == :covered

      # no Social Security estimate counts as none
      h = dad(h0(), target_monthly: 1_000)
      assert Retirement.project(h, :dad, @today).gap == 1_000
      # 1% a month on 12,989.47 grows faster than 10.00 a month is paid: some remains at 100
      assert Retirement.project(h, :dad, @today).lasts == :beyond
    end
  end

  describe "REQ-153 sensitivity" do
    test "the return two points either way and retiring two years either way; nothing saved" do
      h = dad(h0(), target_monthly: 300_000, ss_monthly: 200_000)
      [base | others] = s = Retirement.sensitivity(h, :dad, @today)
      assert base.change == :as_entered and base.at_retirement == 1_298_947

      assert Enum.map(others, & &1.change) == [
               return: -200,
               return: 200,
               retire_age: -2,
               retire_age: 2
             ]

      [lower, higher, earlier, later] = others
      assert lower.return_bp == 1_000 and lower.at_retirement < base.at_retirement
      assert higher.return_bp == 1_400 and higher.at_retirement > base.at_retirement
      assert earlier.retire_age == 65 and earlier.at_retirement == 1_000_000
      assert later.retire_age == 69 and later.at_retirement > base.at_retirement

      # each alternative is the projection with that one change
      assert higher.at_retirement ==
               Retirement.project(h, :dad, @today, %{return_bp: 1_400}).at_retirement

      assert length(s) == 5
      assert Retirement.settings(h, :dad).return_bp == 1_200
    end

    test "alternatives outside the allowed ranges are left out" do
      h = dad(h0(), return_bp: 1_400, retire_age: 89)
      changes = Retirement.sensitivity(h, :dad, @today) |> Enum.map(& &1.change)
      assert changes == [:as_entered, {:return, -200}, {:retire_age, -2}]

      assert Retirement.sensitivity(h0(), :dad, @today) ==
               {:missing, [:birth_year, :retire_age, :return_bp]}
    end
  end
end
