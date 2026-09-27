defmodule Findependence.AttachTest do
  use ExUnit.Case, async: true

  alias Findependence.{Attach, Balances, Exit, Household, Plans, Projection, Schedule}

  @today ~D[2026-09-27]
  @month {:every, 1, :month}

  # Dad and Mom with joint checking and joint savings; each has a private paycheck; a joint mortgage;
  # Mom's own savings account; the kid's tuition, shared with Dad for information.
  defp h0 do
    h = Household.new(["dad", "mom", "kid"])

    add = fn h, m, id, note, amt, on ->
      {:ok, h} =
        Household.add_item(h, m, id, %{
          note: note,
          amount: amt,
          unit: :cents,
          frequency: @month,
          on: on
        })

      h
    end

    h =
      h
      |> add.("mom", "mom_pay", "Mom's paycheck", 198_000, "2026-09-29")
      |> add.("dad", "dad_pay", "Dad's paycheck", 265_000, "2026-10-06")
      |> add.("dad", "mortgage", "Mortgage", -224_000, "2026-10-01")
      |> add.("kid", "tuition", "Tuition", -680_000, "2026-10-15")

    {:ok, h, _} = Household.propose_owners(h, "dad", "mortgage", ["dad", "mom"])
    {:ok, h, _} = Household.propose_grant(h, "kid", "tuition", "dad")
    {:ok, h} = Balances.add_account(h, "dad", "chk", "Joint checking", :checking)
    {:ok, h, _} = Household.propose_owners(h, "dad", "chk", ["dad", "mom"])
    {:ok, h} = Balances.add_reading(h, "dad", "chk", %{on: "2026-09-26", balance: 85_000})
    {:ok, h} = Balances.add_account(h, "mom", "sav", "Mom's savings", :savings)
    {:ok, h} = Balances.add_reading(h, "mom", "sav", %{on: "2026-09-26", balance: 100_000})
    {:ok, h} = Balances.add_account(h, "dad", "k401", "401(k)", :retirement_401k)
    {:ok, h} = Balances.add_debt(h, "dad", "visa", "Visa", :card)
    h
  end

  defp ok({:ok, h}), do: h
  defp ok({:ok, h, _}), do: h

  defp balances(h, m), do: Schedule.cash_flow(h, m, @today, 60).days |> Enum.map(& &1.balance)

  describe "REQ-160 saying which account an item goes through" do
    test "any money item and cash account the member can see; privately; clearable" do
      h = h0()
      h = ok(Attach.attach(h, "dad", "mortgage", "chk"))
      assert Attach.attached(h, "dad") == %{"mortgage" => "chk"}
      # only Dad sees it
      assert Attach.attached(h, "mom") == %{}
      # an item shared with him can be attached too
      assert {:ok, _} = Attach.attach(h, "dad", "tuition", "chk")
      h = ok(Attach.attach(h, "dad", "mortgage", nil))
      assert Attach.attached(h, "dad") == %{}
    end

    test "not to what they can't see, not a value or balance, and not to a debt or retirement account" do
      h = h0()
      {:ok, h} = Findependence.Alignment.add_value(h, "dad", "home", "Home")
      assert Attach.attach(h, "dad", "mom_pay", "chk") == {:error, :not_found}
      assert Attach.attach(h, "dad", "mortgage", "sav") == {:error, :not_found}
      assert Attach.attach(h, "dad", "nope", "chk") == {:error, :not_found}
      assert Attach.attach(h, "dad", "home", "chk") == {:error, :not_money}
      assert Attach.attach(h, "dad", "chk", "chk") == {:error, :not_money}
      assert Attach.attach(h, "dad", "mortgage", "visa") == {:error, :not_a_cash_account}
      assert Attach.attach(h, "dad", "mortgage", "k401") == {:error, :not_a_cash_account}
    end

    test "deleting the item or the account removes it; losing sight of either stops it counting; leaving removes all" do
      h = h0() |> then(&ok(Attach.attach(&1, "dad", "tuition", "chk")))
      h2 = ok(Exit.delete(h, "kid", "tuition"))
      refute Map.has_key?(Plans.goals(h2, "dad").attached, "tuition")

      h3 = ok(Household.revoke_grant(h, "kid", "tuition", "dad"))
      assert Attach.attached(h3, "dad") == %{}

      {:ok, h4} = Balances.add_account(h, "dad", "own", "Dad's checking", :checking)
      h4 = ok(Attach.attach(h4, "dad", "dad_pay", "own"))
      h4 = ok(Exit.delete(h4, "dad", "own"))
      refute Map.has_key?(Plans.goals(h4, "dad").attached, "dad_pay")

      {:ok, h5} = Balances.add_account(h, "kid", "kidchk", "Kid's checking", :checking)
      h5 = ok(Attach.attach(h5, "kid", "tuition", "kidchk"))
      assert Attach.attached(h5, "kid") == %{"tuition" => "kidchk"}

      h5 =
        h5
        |> then(&ok(Exit.delete(&1, "kid", "tuition")))
        |> then(&ok(Exit.delete(&1, "kid", "kidchk")))

      {:ok, h5} = Exit.leave(h5, "kid")
      refute Map.has_key?(h5.goals, "kid")
    end
  end

  describe "REQ-161 the running balance" do
    test "each parent alone sees a partial, different picture of the joint account" do
      assert balances(h0(), "dad") != balances(h0(), "mom")
    end

    test "sharing and attaching every item that goes through it gives both the same balance, every day" do
      h =
        h0()
        |> then(&ok(Household.propose_grant(&1, "mom", "mom_pay", "dad")))
        |> then(&ok(Household.propose_grant(&1, "dad", "dad_pay", "mom")))
        |> then(&ok(Attach.attach(&1, "dad", "mom_pay", "chk")))
        |> then(&ok(Attach.attach(&1, "mom", "dad_pay", "chk")))

      dad = balances(h, "dad")
      assert dad == balances(h, "mom")
      # 850 + 1,980 on September 29 - 2,240 on October 1 + 2,650 on October 6
      assert Enum.at(dad, 2) == 85_000 + 198_000
      assert Enum.at(dad, 4) == 85_000 + 198_000 - 224_000
      assert Enum.at(dad, 9) == 85_000 + 198_000 - 224_000 + 265_000
    end

    test "sharing alone isn't enough, and information shared with a parent isn't their money" do
      h = h0() |> then(&ok(Household.propose_grant(&1, "mom", "mom_pay", "dad")))
      assert balances(h, "dad") == balances(h0(), "dad")

      # the kid's tuition, shared with Dad, doesn't count until Dad says it goes through his account
      refute Enum.any?(Schedule.cash_flow(h0(), "dad", @today, 60).days, fn d ->
               Enum.any?(d.entries, fn {i, _} -> i.id == "tuition" end)
             end)

      h = ok(Attach.attach(h0(), "dad", "tuition", "chk"))

      assert Enum.any?(Schedule.cash_flow(h, "dad", @today, 60).days, fn d ->
               Enum.any?(d.entries, fn {i, _} -> i.id == "tuition" end)
             end)
    end

    test "an item the member owns but says goes through another account leaves this one" do
      h = ok(Attach.attach(h0(), "mom", "mom_pay", "sav"))
      mom = Schedule.cash_flow(h, "mom", @today, 60)

      refute Enum.any?(mom.days, fn d ->
               Enum.any?(d.entries, fn {i, _} -> i.id == "mom_pay" end)
             end)

      # the next twelve months still count it, because savings is one of the accounts it starts from
      [oct | _] = Projection.project(h, "mom", @today).months
      assert oct.in == 198_000
    end
  end

  describe "REQ-162 the next twelve months" do
    test "the same months for both parents once every item through the joint account is shared and attached" do
      h =
        h0()
        |> then(&ok(Household.propose_grant(&1, "mom", "mom_pay", "dad")))
        |> then(&ok(Household.propose_grant(&1, "dad", "dad_pay", "mom")))
        |> then(&ok(Attach.attach(&1, "dad", "mom_pay", "chk")))
        |> then(&ok(Attach.attach(&1, "mom", "dad_pay", "chk")))

      flows = fn m -> Enum.map(Projection.project(h, m, @today).months, &{&1.in, &1.out}) end
      assert flows.("dad") == flows.("mom")
      assert hd(flows.("dad")) == {198_000 + 265_000, -224_000}
    end
  end
end
