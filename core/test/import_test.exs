defmodule Findependence.ImportTest do
  use ExUnit.Case, async: true
  import Findependence.TestJoint

  alias Findependence.{
    Alignment,
    Balances,
    Exit,
    Household,
    Import,
    Ledger,
    Plans,
    Projection,
    Retirement,
    View
  }

  @today ~D[2026-09-27]
  @month {:every, 1, :month}

  # Dad's record in the old household: money items of several kinds, a value and a link, a joint bill,
  # an account and a debt with readings, a 401(k), a plan with every kind of step, a mark, goals,
  # retirement assumptions; plus Mom's item shared with him and a shared plan he owns.
  defp old do
    h = Household.new(["dad", "mom"])

    {:ok, h} =
      Household.add_item(h, "dad", "pay", %{
        note: "Paycheck",
        amount: 265_000,
        unit: :cents,
        frequency: {:every, 2, :week},
        on: "2026-10-02"
      })

    {:ok, h} =
      Household.add_item(h, "dad", "health", %{
        note: "Health plan",
        amount: -9_000,
        unit: :cents,
        frequency: @month
      })

    {:ok, h} =
      Household.add_item(h, "dad", "repair", %{
        note: "Car repair",
        amount: -80_000,
        unit: :cents,
        frequency: :one_off,
        on: "2026-11-10"
      })

    {:ok, h} =
      Household.add_item(h, "dad", "gym", %{
        note: "Gym",
        amount: -4_000,
        unit: :cents,
        frequency: :monthly
      })

    {:ok, h} =
      Household.add_item(h, "dad", "idea", %{note: "Maybe a boat", amount: nil, unit: :cents})

    {:ok, h} =
      Household.add_item(h, "dad", "rent", %{
        note: "Rent",
        amount: -150_000,
        unit: :cents,
        frequency: @month
      })

    h = joint!(h, "dad", "rent", ["dad", "mom"])

    {:ok, h} =
      Household.add_item(h, "mom", "moms", %{
        note: "Mom's phone",
        amount: -5_000,
        unit: :cents,
        frequency: @month
      })

    {:ok, h, _} = Household.propose_grant(h, "mom", "moms", "dad")
    {:ok, h} = Alignment.add_value(h, "dad", "home", "A safe home")
    {:ok, h} = Alignment.link(h, "dad", "rent", "home")
    {:ok, h} = Balances.add_account(h, "dad", "chk", "Checking", :checking)
    {:ok, h} = Balances.add_reading(h, "dad", "chk", %{on: "2026-09-01", balance: 50_000})
    {:ok, h} = Balances.add_reading(h, "dad", "chk", %{on: "2026-09-26", balance: -2_500})
    {:ok, h} = Balances.add_debt(h, "dad", "visa", "Visa", :card)

    {:ok, h} =
      Balances.add_reading(h, "dad", "visa", %{
        on: "2026-09-26",
        balance: 620_000,
        rate_bp: 2499,
        min_payment: 19_000
      })

    {:ok, h} = Balances.add_account(h, "dad", "k401", "401(k)", :retirement_401k)
    {:ok, h} = Balances.add_reading(h, "dad", "k401", %{on: "2026-09-26", balance: 4_820_000})
    {:ok, h} = Plans.mark(h, "dad", "health", "pay")
    {:ok, h} = Plans.new_plan(h, "dad", "p1", "If the job stops")
    {:ok, h} = Plans.add_step(h, "dad", "p1", {:switch_off, ["pay"], "2026-11"})

    {:ok, h} =
      Plans.add_step(
        h,
        "dad",
        "p1",
        {:add, %{note: "Premium", amount: -48_000, frequency: @month}, "2026-11"}
      )

    {:ok, h} =
      Plans.add_step(
        h,
        "dad",
        "p1",
        {:add, %{note: "Tools", amount: -150_000, frequency: :one_off}, "2026-12"}
      )

    {:ok, h} =
      Plans.add_step(
        h,
        "dad",
        "p1",
        {:borrow, %{amount: 600_000, rate_bp: 875, payment: 25_000}, "2026-12"}
      )

    {:ok, h} = Plans.set_fund_goal(h, "dad", 3)
    {:ok, h} = Plans.set_aside(h, "dad", "home", 2500)

    h =
      Enum.reduce(
        [
          birth_year: 1976,
          retire_age: 67,
          return_bp: 400,
          ss_monthly: 230_000,
          target_monthly: 550_000
        ],
        h,
        fn {f, v}, h ->
          {:ok, h} = Retirement.set(h, "dad", f, v)
          h
        end
      )

    {:ok, h} = Retirement.set_contribution(h, "dad", "k401", 40_000)
    # REQ-164: Dad says his paycheck goes into checking, and Mom's phone (shared with him) too
    {:ok, h} = Findependence.Attach.attach(h, "dad", "pay", "chk")
    {:ok, h} = Findependence.Attach.attach(h, "dad", "moms", "chk")
    {:ok, h, _} = Plans.propose_shared(h, "dad", "p1", "sp1", ["mom"])
    h
  end

  defp file, do: old() |> Exit.export("dad") |> Import.to_data()

  defp ids do
    counter = :counters.new(1, [])

    fn ->
      :counters.add(counter, 1, 1)
      "n#{:counters.get(counter, 1)}"
    end
  end

  defp new_household do
    h = Household.new(["kid", "roommate"])

    {:ok, h} =
      Household.add_item(h, "roommate", "wifi", %{
        note: "Wi-Fi",
        amount: -6_000,
        unit: :cents,
        frequency: @month
      })

    {:ok, h, _} = Household.propose_grant(h, "roommate", "wifi", "kid")
    h
  end

  defp bring_in(h \\ new_household(), data \\ file()) do
    {:ok, bundle} = Import.check(data)
    Import.apply(h, "kid", bundle, ids(), "fp1", @today)
  end

  describe "REQ-155 the file" do
    test "carries the member's own plans, marks, goals, and retirement, and nothing of anyone else's" do
      data = file()
      assert data["format"] == "findependence-export" and data["version"] == 3
      notes = Enum.map(data["items"], &(&1["attrs"]["note"] || &1["attrs"]["label"]))
      refute "Mom's phone" in notes
      assert "Rent" in notes

      assert [%{"name" => "If the job stops", "steps" => [s1, s2, s3, s4]}] = data["plans"]
      assert s1 == %{"kind" => "switch_off", "items" => ["pay"], "from" => "2026-11"}
      assert s2["frequency"] == %{"every" => 1, "unit" => "month"}
      assert s3["frequency"] == "one_off"

      assert s4 == %{
               "kind" => "borrow",
               "amount" => 600_000,
               "rate_bp" => 875,
               "payment" => 25_000,
               "from" => "2026-12"
             }

      assert data["marks"] == [%{"item" => "health", "job" => "pay"}]

      assert data["goals"] == %{
               "fund_months" => 3,
               "set_aside" => [%{"value" => "home", "rate_bp" => 2500}]
             }

      assert data["retirement"]["return_bp"] == 400
      assert data["retirement"]["contributions"] == [%{"account" => "k401", "cents" => 40_000}]
      # nothing is written as the string "nil"; a shared plan's steps are written like a plan's
      idea = Enum.find(data["items"], &(&1["id"] == "idea"))
      assert idea["attrs"]["amount"] == :null
      sp = Enum.find(data["items"], &(&1["id"] == "sp1"))
      assert [%{"kind" => "switch_off"} | _] = sp["attrs"]["steps"]
    end

    test "leaves out set-asides and contributions for what the member doesn't own" do
      h = old()
      {:ok, h} = Alignment.add_value(h, "mom", "hers", "Mom's value")
      {:ok, h, _} = Household.propose_grant(h, "mom", "hers", "dad")
      {:ok, h} = Plans.set_aside(h, "dad", "hers", 1000)
      {:ok, h} = Balances.add_account(h, "mom", "ira", "IRA", :ira)
      {:ok, h, _} = Household.propose_grant(h, "mom", "ira", "dad")
      {:ok, h} = Retirement.set_contribution(h, "dad", "ira", 5_000)
      data = h |> Exit.export("dad") |> Import.to_data()
      assert data["goals"]["set_aside"] == [%{"value" => "home", "rate_bp" => 2500}]
      assert data["retirement"]["contributions"] == [%{"account" => "k401", "cents" => 40_000}]
    end
  end

  describe "REQ-156 bringing it in" do
    test "everything becomes the member's alone, and works the same as before" do
      before = new_household()
      {:ok, h, summary} = bring_in(before)

      mine = for {_, i} <- h.items, "kid" in i.owners, do: i

      assert Enum.all?(
               mine,
               &(MapSet.new(["kid"]) == &1.owners and MapSet.size(&1.grantees) == 0)
             )

      assert length(mine) == 10
      assert summary.shared_plans == 1

      assert Enum.sort(summary.items) == [
               "Car repair",
               "Gym",
               "Health plan",
               "Maybe a boat",
               "Paycheck",
               "Rent"
             ]

      assert summary.values == ["A safe home"] and
               summary.accounts |> Enum.sort() == ["401(k)", "Checking"]

      assert summary.debts == ["Visa"] and summary.readings == 4 and summary.links == 1
      assert summary.plans == ["If the job stops"] and summary.marks == 1

      # the same attributes as the originals, under new ids
      # Mom's phone is shared with Dad and attached by him, but it isn't his, so it stays out of his file
      {:ok, o} = Findependence.Attach.attach(old(), "dad", "moms", nil)

      # (an empty amount is simply absent once brought in)
      # and a frequency stored by its old name reads as its interval
      present = fn attrs ->
        attrs
        |> Enum.reject(fn {_, v} -> v == nil end)
        |> Map.new()
        |> then(fn a ->
          if Map.has_key?(a, :frequency),
            do: %{a | frequency: Alignment.frequency(%{attrs: a})},
            else: a
        end)
      end

      for {_, oi} <- o.items, "dad" in oi.owners, oi.attrs[:kind] != :plan do
        assert Enum.any?(mine, &(&1.attrs == present.(oi.attrs))), "missing #{inspect(oi.attrs)}"
      end

      # each new entry's history starts with being brought in by the member
      for i <- mine do
        {:ok, [first | _]} = Ledger.read(h, "kid", i.id)
        assert first.event == :created and first.by == ["kid"] and first.details.imported == true
      end

      # the projections, the plan, cover, set-asides, and retirement come out the same
      plan = fn h, m -> h |> Plans.plans(m) |> Map.values() |> hd() end

      assert Projection.project(h, "kid", @today).months ==
               Projection.project(o, "dad", @today).months

      assert Projection.project(h, "kid", @today, plan.(h, "kid")).months ==
               Projection.project(o, "dad", @today, plan.(o, "dad")).months

      assert Enum.map(Projection.project(h, "kid", @today).debts, & &1.months) ==
               Enum.map(Projection.project(o, "dad", @today).debts, & &1.months)

      assert Projection.set_asides(h, "kid") |> Enum.map(& &1.set_aside) ==
               Projection.set_asides(o, "dad") |> Enum.map(& &1.set_aside)

      assert Map.drop(Retirement.project(h, "kid", @today), [:start]) ==
               Map.drop(Retirement.project(o, "dad", @today), [:start])

      assert length(Plans.depends(h, "kid")) == 1
      assert Plans.goals(h, "kid").fund_months == 3

      # nothing anyone else owns or can see changed (REQ-159)
      assert View.visible_items(h, "roommate") == View.visible_items(before, "roommate")
      assert h.items["wifi"] == before.items["wifi"]
    end

    test "goals and assumptions already set are kept; only unset ones are filled" do
      h = new_household()
      {:ok, h} = Plans.set_fund_goal(h, "kid", 6)
      {:ok, h} = Retirement.set(h, "kid", :retire_age, 60)
      {:ok, h, _} = bring_in(h)
      assert Plans.goals(h, "kid").fund_months == 6
      s = Retirement.settings(h, "kid")
      assert s.retire_age == 60 and s.birth_year == 1976 and s.return_bp == 400
    end
  end

  describe "REQ-164 attachments in the file" do
    test "only those where the member owns both come out, and they come back on the new entries" do
      data = file()
      assert data["attached"] == [%{"item" => "pay", "account" => "chk"}]

      {:ok, h, summary} = bring_in()
      assert summary.attached == 1
      pay = Enum.find_value(h.items, fn {id, i} -> i.attrs[:note] == "Paycheck" && id end)
      chk = Enum.find_value(h.items, fn {id, i} -> i.attrs[:label] == "Checking" && id end)
      assert Findependence.Attach.attached(h, "kid") == %{pay => chk}
    end

    test "a version 2 file has none, and an attachment must name a money item and a cash account in the file" do
      d = file()
      assert {"attached", :unknown_field} in problems(Map.put(d, "version", 2))
      assert {:ok, _} = Import.check(d |> Map.put("version", 2) |> Map.delete("attached"))

      assert {"attached[0].account", :bad_reference} in problems(
               at(d, ["attached", 0, "account"], "visa")
             )

      assert {"attached[0].account", :bad_reference} in problems(
               at(d, ["attached", 0, "account"], "k401")
             )

      assert {"attached[0].item", :bad_reference} in problems(
               at(d, ["attached", 0, "item"], "home")
             )
    end
  end

  describe "REQ-159 the same file twice" do
    test "is refused with the date it was brought in, and changes nothing" do
      {:ok, h, _} = bring_in()
      {:ok, bundle} = Import.check(file())

      assert Import.apply(h, "kid", bundle, ids(), "fp1", ~D[2026-10-01]) ==
               {:error, {:already_imported, "2026-09-27"}}

      assert Import.imported_on(h, "kid", "fp1") == "2026-09-27"
      # another file, or another member, is not refused
      assert {:ok, _, _} =
               Import.apply(
                 h,
                 "kid",
                 bundle,
                 fn -> "x#{System.unique_integer([:positive])}" end,
                 "fp2",
                 @today
               )

      assert {:ok, _, _} =
               Import.apply(
                 h,
                 "roommate",
                 bundle,
                 fn -> "y#{System.unique_integer([:positive])}" end,
                 "fp1",
                 @today
               )
    end
  end

  describe "REQ-157 an untrusted file" do
    defp at(data, path, value), do: put_in(data, Enum.map(path, &access/1), value)
    defp access(i) when is_integer(i), do: Access.at(i)
    defp access(k), do: k

    defp problems(data) do
      assert {:error, ps} = Import.check(data)
      ps
    end

    defp item_index(data, id), do: Enum.find_index(data["items"], &(&1["id"] == id))

    test "anything wrong refuses the whole file, saying what and where" do
      d = file()
      pay = item_index(d, "pay")
      chk = item_index(d, "chk")
      visa = item_index(d, "visa")
      home = item_index(d, "home")

      cases = [
        {"not an object", fn _ -> [1, 2] end, {"", :not_an_export}},
        {"another format", fn d -> Map.put(d, "format", "other") end, {"", :not_an_export}},
        {"a later version", fn d -> Map.put(d, "version", 4) end, {"version", :unknown_version}},
        {"no items", fn d -> Map.delete(d, "items") end, {"items", :missing}},
        {"items not a list", fn d -> Map.put(d, "items", %{}) end, {"items", :not_a_list}},
        {"too many items", fn d -> Map.put(d, "items", List.duplicate(hd(d["items"]), 2_001)) end,
         {"items", {:too_many, 2_000}}},
        {"an unknown field", fn d -> at(d, ["items", pay, "attrs", "script"], "x") end,
         {"items[#{pay}].attrs.script", :unknown_field}},
        {"a fractional amount", fn d -> at(d, ["items", pay, "attrs", "amount"], 1.5) end,
         {"items[#{pay}].attrs.amount", :invalid_amount}},
        {"an amount as text", fn d -> at(d, ["items", pay, "attrs", "amount"], "100") end,
         {"items[#{pay}].attrs.amount", :invalid_amount}},
        {"a huge amount", fn d -> at(d, ["items", pay, "attrs", "amount"], 100_000_000_001) end,
         {"items[#{pay}].attrs.amount", :invalid_amount}},
        {"an unknown frequency", fn d -> at(d, ["items", pay, "attrs", "frequency"], "daily") end,
         {"items[#{pay}].attrs.frequency", :invalid_frequency}},
        {"every zero weeks",
         fn d ->
           at(d, ["items", pay, "attrs", "frequency"], %{"every" => 0, "unit" => "week"})
         end, {"items[#{pay}].attrs.frequency", :invalid_frequency}},
        {"every 2 days",
         fn d ->
           at(d, ["items", pay, "attrs", "frequency"], %{"every" => 2, "unit" => "day"})
         end, {"items[#{pay}].attrs.frequency", :invalid_frequency}},
        {"no such date", fn d -> at(d, ["items", pay, "attrs", "on"], "2026-02-30") end,
         {"items[#{pay}].attrs.on", :invalid_date}},
        {"an empty name", fn d -> at(d, ["items", pay, "attrs", "note"], "  ") end,
         {"items[#{pay}].attrs.note", :invalid_text}},
        {"a name too long",
         fn d -> at(d, ["items", pay, "attrs", "note"], String.duplicate("a", 201)) end,
         {"items[#{pay}].attrs.note", :invalid_text}},
        {"a name not UTF-8", fn d -> at(d, ["items", pay, "attrs", "note"], <<0xFF, 0xFE>>) end,
         {"items[#{pay}].attrs.note", :invalid_text}},
        {"an unknown kind", fn d -> at(d, ["items", pay, "attrs", "kind"], "admin") end,
         {"items[#{pay}].attrs.kind", :invalid_kind}},
        {"an unknown account type",
         fn d -> at(d, ["items", chk, "attrs", "account_type"], "crypto") end,
         {"items[#{chk}].attrs.account_type", :invalid_kind}},
        {"readings on a value",
         fn d ->
           at(d, ["items", home, "readings"], [%{"on" => "2026-09-01", "balance" => 1}])
         end, {"items[#{home}].readings", :readings_not_allowed}},
        {"a debt owing less than nothing",
         fn d -> at(d, ["items", visa, "readings", 0, "balance"], -1) end,
         {"items[#{visa}].readings[0].balance", :invalid_amount}},
        {"a rate over 100%", fn d -> at(d, ["items", visa, "readings", 0, "rate_bp"], 10_001) end,
         {"items[#{visa}].readings[0].rate_bp", :invalid_rate}},
        {"a duplicate id", fn d -> at(d, ["items", chk, "id"], "pay") end,
         {"items", {:duplicate_id, "pay"}}},
        {"a link to nothing", fn d -> at(d, ["links", 0, "value"], "nope") end,
         {"links[0].value", :bad_reference}},
        {"a link from a value", fn d -> at(d, ["links", 0, "item"], "home") end,
         {"links[0].item", :bad_reference}},
        {"a step naming nothing", fn d -> at(d, ["plans", 0, "steps", 0, "items"], ["nope"]) end,
         {"plans[0].steps[0].items", :bad_reference}},
        {"an unknown step", fn d -> at(d, ["plans", 0, "steps", 0, "kind"], "sell") end,
         {"plans[0].steps[0]", :invalid_step}},
        {"a month 13", fn d -> at(d, ["plans", 0, "steps", 1, "from"], "2026-13") end,
         {"plans[0].steps[1].from", :invalid_month}},
        {"borrowing nothing", fn d -> at(d, ["plans", 0, "steps", 3, "amount"], 0) end,
         {"plans[0].steps[3].amount", :invalid_amount}},
        {"a mark naming nothing", fn d -> at(d, ["marks", 0, "job"], "nope") end,
         {"marks[0].job", :bad_reference}},
        {"a fund goal of 61 months", fn d -> at(d, ["goals", "fund_months"], 61) end,
         {"goals.fund_months", :invalid_goal}},
        {"a set-aside of 0", fn d -> at(d, ["goals", "set_aside", 0, "rate_bp"], 0) end,
         {"goals.set_aside[0].rate_bp", :invalid_rate}},
        {"a return of 16%", fn d -> at(d, ["retirement", "return_bp"], 1_600) end,
         {"retirement.return_bp", :invalid_retirement}},
        {"a contribution to checking",
         fn d -> at(d, ["retirement", "contributions", 0, "account"], "chk") end,
         {"retirement.contributions[0].account", :bad_reference}},
        {"an unknown top-level field", fn d -> Map.put(d, "admin", true) end,
         {"admin", :unknown_field}}
      ]

      for {name, change, expected} <- cases do
        ps =
          case Import.check(change.(d)) do
            {:error, ps} -> ps
            {:ok, _} -> flunk("#{name}: accepted")
          end

        assert expected in ps, "#{name}: got #{inspect(ps)}"
      end
    end

    test "a fault is reported once, where it is, and not again at what refers to it" do
      d = file()
      rent = item_index(d, "rent")

      assert problems(at(d, ["items", rent, "attrs", "amount"], 1.5)) == [
               {"items[#{rent}].attrs.amount", :invalid_amount}
             ]
    end

    test "a file can't create atoms, and at most 20 problems are reported" do
      key = "zz_not_an_atom_#{System.unique_integer([:positive])}"
      d = file()
      pay = item_index(d, "pay")
      _ = Import.check(at(d, ["items", pay, "attrs", key], "x"))
      _ = Import.check(at(d, ["items", pay, "attrs", "frequency"], key))
      _ = Import.check(Map.put(d, key, 1))
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end

      many =
        Map.put(d, "items", for(i <- 1..50, do: %{"id" => "i#{i}", "attrs" => %{"note" => ""}}))

      assert length(problems(many)) == 20
    end

    test "files from before version 2 still come in, where an empty amount was written as \"nil\"" do
      old_file = %{
        "member" => "dad",
        "items" => [
          %{
            "id" => "a",
            "attrs" => %{
              "note" => "Rent",
              "amount" => -150_000,
              "unit" => "cents",
              "frequency" => "monthly"
            },
            "owners" => ["dad"],
            "grantees" => [],
            "history" => ["Created by dad"]
          },
          %{"id" => "b", "attrs" => %{"note" => "Someday", "amount" => "nil"}},
          %{"id" => "v", "attrs" => %{"kind" => "value", "label" => "Home"}}
        ],
        "links" => [%{"item" => "a", "value" => "v"}]
      }

      assert {:ok, bundle} = Import.check(old_file)
      assert bundle.version == 1
      assert Enum.find(bundle.items, &(&1.ref == "a")).attrs.frequency == {:every, 1, :month}
      refute Map.has_key?(Enum.find(bundle.items, &(&1.ref == "b")).attrs, :amount)

      assert {:ok, _, %{links: 1}} =
               Import.apply(new_household(), "kid", bundle, ids(), "old", @today)

      # plans and the like belong to version 2
      assert {"plans", :unknown_field} in problems(Map.put(old_file, "plans", []))
    end
  end
end
