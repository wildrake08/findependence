defmodule Findependence.VVF05DTest do
  @moduledoc """
  VV-001 F-05/F-08, batch D (WI-057): tests for acceptance criteria of REQ-149, REQ-150, REQ-153,
  REQ-155, REQ-156, and REQ-164 that no earlier test asserted. The criteria are in
  project/assurance/vv/acceptance-d.yaml. Fixtures are copied from import_test.exs and
  retirement_test.exs.
  """
  use ExUnit.Case, async: true

  alias Findependence.{
    Alignment,
    Attach,
    Balances,
    Exit,
    Household,
    Import,
    Ledger,
    Plans,
    Retirement,
    View
  }

  @month {:every, 1, :month}

  # ---------------------------------------------------------------------------
  # REQ-149: retirement accounts under the same rules as other accounts (REQ-171, REQ-131..133)

  describe "REQ-149 retirement accounts follow the account rules" do
    for type <- [:retirement_401k, :ira] do
      @type_ type

      test "#{type}: created owned by the creator alone, private, with name and kind fixed" do
        h = Household.new([:mom, :dad, :kid])
        {:ok, h} = Balances.add_account(h, :dad, :ret, "Dad's plan", @type_)

        assert {:ok, %{owners: [:dad], grantees: [], attrs: attrs}} = View.get(h, :dad, :ret)
        assert attrs == %{kind: :account, label: "Dad's plan", account_type: @type_}
        refute View.visible?(h, :mom, :ret) or View.visible?(h, :kid, :ret)

        # nothing re-creates it under the same id, and nothing done to it changes its name or kind
        assert Balances.add_account(h, :dad, :ret, "Renamed", :checking) == {:error, :item_exists}
        {:ok, h} = Balances.add_reading(h, :dad, :ret, %{on: "2026-09-01", balance: 100})
        {:ok, h, _} = Household.propose_grant(h, :dad, :ret, :kid)
        {:ok, h, _} = Household.propose_owners(h, :dad, :ret, [:dad, :mom])
        {:ok, h} = Household.revoke_grant(h, :mom, :ret, :kid)
        {:ok, h} = Household.relinquish(h, :dad, :ret)
        assert h.items[:ret].attrs == attrs
      end

      test "#{type}: any owner adds a dated reading without consent; append-only and in the history" do
        h = Household.new([:mom, :dad, :kid])
        {:ok, h} = Balances.add_account(h, :mom, :ret, "Joint", @type_)
        {:ok, h, _} = Household.propose_owners(h, :mom, :ret, [:mom, :dad])
        assert h.items[:ret].owners == MapSet.new([:mom, :dad])

        {:ok, h} = Balances.add_reading(h, :mom, :ret, %{on: "2026-08-31", balance: 4_000_000})
        # the other owner adds one without anyone's consent: nothing is pending afterwards
        {:ok, h} = Balances.add_reading(h, :dad, :ret, %{on: "2026-09-30", balance: 4_100_000})
        assert Household.pending(h, :mom) == [] and Household.pending(h, :dad) == []

        assert {:ok,
                [
                  %{seq: 1, by: :mom, on: "2026-08-31", balance: 4_000_000},
                  %{seq: 2, by: :dad, on: "2026-09-30", balance: 4_100_000}
                ]} = Balances.readings(h, :dad, :ret)

        # a later reading adds to the list; the earlier one is kept unchanged
        {:ok, h2} = Balances.add_reading(h, :mom, :ret, %{on: "2026-10-31", balance: 1})
        {:ok, rs} = Balances.readings(h2, :mom, :ret)
        assert Enum.take(rs, 2) == elem(Balances.readings(h, :mom, :ret), 1)

        {:ok, ledger} = Ledger.read(h, :mom, :ret)

        assert [%{event: :reading_added, by: [:mom]}, %{event: :reading_added, by: [:dad]}] =
                 Enum.filter(ledger, &(&1.event == :reading_added))

        # a reading needs a valid date and a balance in cents, like any account
        assert Balances.add_reading(h, :mom, :ret, %{on: "2026-02-30", balance: 1}) ==
                 {:error, :invalid_reading}
      end

      test "#{type}: someone it's shared with can't add a reading; someone who can't see it is told it isn't there" do
        h = Household.new([:mom, :dad, :kid])
        {:ok, h} = Balances.add_account(h, :dad, :ret, "Dad's plan", @type_)
        {:ok, h, _} = Household.propose_grant(h, :dad, :ret, :mom)
        r = %{on: "2026-09-30", balance: 100}
        assert Balances.add_reading(h, :mom, :ret, r) == {:error, :not_owner}
        assert Balances.add_reading(h, :kid, :ret, r) == {:error, :not_found}
        assert Map.get(h.readings, :ret, []) == []
      end

      test "#{type}: owners read every reading; someone it's shared with only the latest; nobody else any" do
        h = Household.new([:mom, :dad, :kid])
        {:ok, h} = Balances.add_account(h, :dad, :ret, "Dad's plan", @type_)
        {:ok, h} = Balances.add_reading(h, :dad, :ret, %{on: "2026-08-31", balance: 4_000_000})
        {:ok, h} = Balances.add_reading(h, :dad, :ret, %{on: "2026-09-30", balance: 4_100_000})
        {:ok, h, _} = Household.propose_grant(h, :dad, :ret, :mom)

        assert {:ok, [%{balance: 4_000_000}, %{balance: 4_100_000}]} =
                 Balances.readings(h, :dad, :ret)

        assert {:ok, [%{balance: 4_100_000}]} = Balances.readings(h, :mom, :ret)
        assert Balances.latest(h, :mom, :ret).balance == 4_100_000
        assert Balances.readings(h, :kid, :ret) == {:error, :not_found}
        assert Balances.latest(h, :kid, :ret) == nil

        {:ok, h} = Household.revoke_grant(h, :dad, :ret, :mom)
        assert Balances.readings(h, :mom, :ret) == {:error, :not_found}
      end

      test "#{type}: deletion, export, leaving, and withdrawing apply as to any item" do
        h = Household.new([:mom, :dad])
        {:ok, h} = Balances.add_account(h, :dad, :ret, "Dad's plan", @type_)
        {:ok, h} = Balances.add_reading(h, :dad, :ret, %{on: "2026-09-30", balance: 100})
        {:ok, h, _} = Household.propose_grant(h, :dad, :ret, :mom)

        # the owner's export carries it with its readings; someone it's shared with doesn't get it
        assert [%{id: :ret, readings: [%{balance: 100}]}] = Exit.export(h, :dad).items
        assert Exit.export(h, :mom).items == []

        # an owner can't leave while owning it
        assert Exit.leave(h, :dad) == {:error, :still_owner}

        # joint: neither owner can delete it alone; a pending proposal can be withdrawn
        {:ok, j, _} = Household.propose_owners(h, :dad, :ret, [:dad, :mom])
        assert Exit.delete(j, :dad, :ret) == {:error, :not_sole_owner}
        {:ok, j, pid} = Household.propose_owners(j, :mom, :ret, [:mom])
        {:ok, j} = Household.withdraw(j, :dad, pid)
        assert Household.pending(j, :dad) == []

        # the sole owner deletes it, and its readings go with it
        {:ok, h} = Exit.delete(h, :dad, :ret)
        refute Map.has_key?(h.items, :ret) or Map.has_key?(h.readings, :ret)
        refute View.visible?(h, :mom, :ret)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # REQ-150: every assumption can be cleared

  describe "REQ-150 every assumption can be cleared" do
    test "birth year, retirement age, return, Social Security, target, and a contribution" do
      h = Household.new([:dad])
      {:ok, h} = Balances.add_account(h, :dad, :k401, "401(k)", :retirement_401k)

      h =
        Enum.reduce(
          [
            birth_year: 1961,
            retire_age: 67,
            return_bp: 400,
            ss_monthly: 200_000,
            target_monthly: 300_000
          ],
          h,
          fn {f, v}, h ->
            {:ok, h} = Retirement.set(h, :dad, f, v)
            h
          end
        )

      {:ok, h} = Retirement.set_contribution(h, :dad, :k401, 10_000)
      assert Retirement.settings(h, :dad).ss_monthly == 200_000

      cleared =
        Enum.reduce([:birth_year, :retire_age, :return_bp, :ss_monthly, :target_monthly], h, fn
          f, h ->
            {:ok, h} = Retirement.set(h, :dad, f, nil)
            h
        end)

      {:ok, cleared} = Retirement.set_contribution(cleared, :dad, :k401, nil)

      assert Retirement.settings(cleared, :dad) == %{
               birth_year: nil,
               retire_age: nil,
               return_bp: nil,
               ss_monthly: nil,
               target_monthly: nil,
               contributions: %{}
             }
    end
  end

  # ---------------------------------------------------------------------------
  # REQ-153: how long it would last, for each alternative

  describe "REQ-153 how long each alternative would last" do
    # Dad's 401(k) with 10,000.00; born 1961, retiring at 67, 12% a year, 100.00 a month
    defp dad(extra) do
      h = Household.new([:mom, :dad])
      {:ok, h} = Balances.add_account(h, :dad, :k401, "Dad's 401(k)", :retirement_401k)
      {:ok, h} = Balances.add_reading(h, :dad, :k401, %{on: "2026-11-01", balance: 1_000_000})

      h =
        Enum.reduce([birth_year: 1961, retire_age: 67, return_bp: 1200] ++ extra, h, fn {f, v},
                                                                                        h ->
          {:ok, h} = Retirement.set(h, :dad, f, v)
          h
        end)

      {:ok, h} = Retirement.set_contribution(h, :dad, :k401, 10_000)
      h
    end

    test "each alternative says how long it would last, worked out with that one change" do
      today = ~D[2026-11-15]
      h = dad(target_monthly: 300_000, ss_monthly: 200_000)
      before = Retirement.settings(h, :dad)
      [base | others] = Retirement.sensitivity(h, :dad, today)
      assert base.lasts == Retirement.project(h, :dad, today).lasts

      overrides = %{
        {:return, -200} => %{return_bp: 1_000},
        {:return, 200} => %{return_bp: 1_400},
        {:retire_age, -2} => %{retire_age: 65},
        {:retire_age, 2} => %{retire_age: 69}
      }

      assert length(others) == 4

      for alt <- others do
        p = Retirement.project(h, :dad, today, overrides[alt.change])
        assert {:months, n} = alt.lasts
        assert alt.lasts == p.lasts and n > 0, "#{inspect(alt.change)}"
      end

      # they differ from the result as entered where the change matters
      [lower, higher, _earlier, later] = others
      {:months, b} = base.lasts
      {:months, lo} = lower.lasts
      {:months, hi} = higher.lasts
      {:months, la} = later.lasts
      assert lo <= b and hi >= b and la > b

      # a target Social Security covers, and one never used up, are said as such for every row
      covered = dad(target_monthly: 200_000, ss_monthly: 250_000)
      assert Enum.all?(Retirement.sensitivity(covered, :dad, today), &(&1.lasts == :covered))
      small = dad(target_monthly: 1_000)
      assert Enum.all?(Retirement.sensitivity(small, :dad, today), &(&1.lasts == :beyond))

      # nothing about the alternatives is saved
      assert Retirement.settings(h, :dad) == before
    end
  end

  # ---------------------------------------------------------------------------
  # REQ-155 and REQ-156: the file and bringing it in (fixtures from import_test.exs)

  # Dad's record in the old household (as in import_test.exs), with a mark and a plan step that name
  # a bill he no longer owns, and a link from Mom's item shared with him.
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
      Household.add_item(h, "dad", "rent", %{
        note: "Rent",
        amount: -150_000,
        unit: :cents,
        frequency: @month
      })

    {:ok, h, _} = Household.propose_owners(h, "dad", "rent", ["dad", "mom"])

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
    {:ok, h} = Plans.add_step(h, "dad", "p1", {:switch_off, ["pay", "health"], "2026-11"})
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
    {:ok, h} = Attach.attach(h, "dad", "pay", "chk")
    h
  end

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

  # every reference the file makes to an entry, as {where, id}
  defp references(data) do
    for(l <- data["links"], do: [{"link", l["item"]}, {"link", l["value"]}]) ++
      for(m <- data["marks"], do: [{"mark", m["item"]}, {"mark", m["job"]}]) ++
      for(a <- data["attached"], do: [{"attached", a["item"]}, {"attached", a["account"]}]) ++
      for(
        p <- data["plans"],
        s <- p["steps"],
        s["kind"] == "switch_off",
        do: Enum.map(s["items"], &{"plan step", &1})
      ) ++
      for(s <- data["goals"]["set_aside"], do: [{"set-aside", s["value"]}]) ++
      for(c <- data["retirement"]["contributions"], do: [{"contribution", c["account"]}])
  end

  describe "REQ-155 the file keeps only references to what it contains" do
    test "marks, plan steps, and links naming entries the member doesn't own are left out" do
      # Dad gives up his share of nothing yet: first, Mom's phone shared with him, linked to his value
      {:ok, h} = Alignment.link(old(), "dad", "moms", "home")

      # the health plan becomes joint, then Dad relinquishes it: his mark and plan step still name it
      {:ok, h, _} = Household.propose_owners(h, "dad", "health", ["dad", "mom"])
      {:ok, h} = Household.relinquish(h, "dad", "health")
      refute "dad" in h.items["health"].owners
      assert {"health", "pay"} in h.depends["dad"]
      # and an item he deleted is still named by a plan step (REQ-142 keeps the step)
      {:ok, h} =
        Household.add_item(h, "dad", "gone", %{note: "Gone", amount: -1, frequency: @month})

      {:ok, h} = Plans.add_step(h, "dad", "p1", {:switch_off, ["gone"], "2026-12"})
      {:ok, h} = Exit.delete(h, "dad", "gone")

      data = h |> Exit.export("dad") |> Import.to_data()
      ids = MapSet.new(data["items"], & &1["id"])
      refute "health" in ids or "moms" in ids or "gone" in ids

      assert data["links"] == [%{"item" => "rent", "value" => "home"}]
      assert data["marks"] == []
      assert [%{"steps" => [step]}] = data["plans"]
      assert step == %{"kind" => "switch_off", "items" => ["pay"], "from" => "2026-11"}

      # every reference left in the file names an entry in it, and the file passes the checks
      for {where, id} <- List.flatten(references(data)),
          do: assert(id in ids, "#{where} names #{id}, which isn't in the file")

      assert {:ok, _} = Import.check(data)
    end

    test "nothing in it belongs to anyone else" do
      # Mom has her own private record too, some of it naming Dad's items she can see
      h = old()
      {:ok, h, _} = Household.propose_grant(h, "dad", "pay", "mom")
      {:ok, h} = Alignment.add_value(h, "mom", "mv", "Mom's value")
      {:ok, h} = Alignment.link(h, "mom", "pay", "mv")
      {:ok, h} = Alignment.link(h, "mom", "rent", "mv")

      {:ok, h} =
        Household.add_item(h, "mom", "mpay", %{note: "Mom's pay", amount: 1, frequency: @month})

      {:ok, h} = Plans.mark(h, "mom", "moms", "mpay")
      {:ok, h} = Plans.new_plan(h, "mom", "mp", "Mom's plan")
      {:ok, h} = Plans.add_step(h, "mom", "mp", {:switch_off, ["rent"], "2026-11"})
      {:ok, h} = Plans.set_fund_goal(h, "mom", 9)
      {:ok, h} = Plans.set_aside(h, "mom", "mv", 700)
      {:ok, h} = Retirement.set(h, "mom", :retire_age, 55)
      {:ok, h} = Balances.add_account(h, "mom", "mchk", "Mom's checking", :checking)
      {:ok, h} = Attach.attach(h, "mom", "rent", "mchk")

      export = Exit.export(h, "dad")
      data = Import.to_data(export)

      # only items Dad owns (including the bill he owns with Mom), with their own owners
      assert Enum.all?(export.items, &("dad" in &1.owners))

      assert Enum.sort(Enum.map(export.items, & &1.id)) ==
               Enum.sort(for {id, i} <- h.items, "dad" in i.owners, do: id)

      # Dad's own private record, and none of Mom's
      assert data["links"] == [%{"item" => "rent", "value" => "home"}]
      assert data["marks"] == [%{"item" => "health", "job" => "pay"}]
      assert Enum.map(data["plans"], & &1["name"]) == ["If the job stops"]
      assert data["goals"]["fund_months"] == 3
      assert data["goals"]["set_aside"] == [%{"value" => "home", "rate_bp" => 2500}]
      assert data["attached"] == [%{"item" => "pay", "account" => "chk"}]

      assert Map.drop(data["retirement"], ["contributions"]) == %{
               "birth_year" => 1976,
               "retire_age" => 67,
               "return_bp" => 400,
               "ss_monthly" => 230_000,
               "target_monthly" => 550_000
             }

      text = IO.iodata_to_binary(:json.encode(data))

      for other <- [
            "Mom's value",
            "Mom's pay",
            "Mom's plan",
            "Mom's checking",
            "Mom's phone",
            "\"mv\"",
            "\"mchk\""
          ],
          do: refute(text =~ other, "#{other} is in Dad's file")

      refute data["goals"]["fund_months"] == 9
      refute data["retirement"]["retire_age"] == 55
    end
  end

  describe "REQ-156 what comes in refers to the new entries, with no old history" do
    defp bring_in do
      data = old() |> Exit.export("dad") |> Import.to_data()
      {:ok, bundle} = Import.check(data)
      {:ok, h, _} = Import.apply(new_household(), "kid", bundle, ids(), "fp1", ~D[2026-09-27])
      # the new entry for each name in the file
      new =
        for {id, i} <- h.items,
            "kid" in i.owners,
            into: %{},
            do: {i.attrs[:note] || i.attrs[:label], id}

      {h, new}
    end

    test "links, marks, plan steps, set-asides, contributions, and readings name the new entries" do
      {h, new} = bring_in()

      # every entry is new: none keeps an id from the file
      for old_id <- ["pay", "health", "rent", "home", "chk", "visa", "k401"],
          do: refute(Map.has_key?(h.items, old_id))

      assert MapSet.to_list(h.links["kid"]) == [{new["Rent"], new["A safe home"]}]
      assert Plans.depends(h, "kid") == [{new["Health plan"], new["Paycheck"]}]

      assert [%{name: "If the job stops", steps: [%{step: step}]}] =
               Map.values(Plans.plans(h, "kid"))

      assert step == {:switch_off, [new["Paycheck"], new["Health plan"]], "2026-11"}

      assert Plans.goals(h, "kid").set_aside == %{new["A safe home"] => 2500}
      assert Retirement.settings(h, "kid").contributions == %{new["401(k)"] => 40_000}
      assert Attach.attached(h, "kid") == %{new["Paycheck"] => new["Checking"]}

      assert {:ok,
              [
                %{on: "2026-09-01", balance: 50_000, by: "kid"},
                %{on: "2026-09-26", balance: -2_500, by: "kid"}
              ]} =
               Balances.readings(h, "kid", new["Checking"])

      assert {:ok, [%{balance: 620_000, rate_bp: 2499, min_payment: 19_000, by: "kid"}]} =
               Balances.readings(h, "kid", new["Visa"])
    end

    test "no history, owners, or sharing from the old household: each history starts with the bringing in" do
      {h, new} = bring_in()
      assert map_size(new) == 7

      for {name, id} <- new do
        item = h.items[id]
        assert item.owners == MapSet.new(["kid"]) and MapSet.size(item.grantees) == 0, name
        {:ok, [first | rest]} = Ledger.read(h, "kid", id)
        assert first.event == :created and first.by == ["kid"] and first.details.imported == true
        # after that, only the readings the member brought in, recorded as theirs
        assert Enum.all?(rest, &(&1.event == :reading_added and &1.by == ["kid"])), name
      end

      # the jointly owned bill arrives without its owner change or its co-owner
      {:ok, rent} = Ledger.read(h, "kid", new["Rent"])
      assert Enum.map(rent, & &1.event) == [:created]
      refute inspect(rent) =~ "mom" or inspect(rent) =~ "dad"
    end
  end

  # ---------------------------------------------------------------------------
  # REQ-164: a file of an earlier version comes in, without attachments

  describe "REQ-164 an earlier version still comes in" do
    test "a version 2 file (no attachments) is brought in whole, with no attachments" do
      data =
        old()
        |> Exit.export("dad")
        |> Import.to_data()
        |> Map.put("version", 2)
        |> Map.delete("attached")

      assert {:ok, bundle} = Import.check(data)

      assert {:ok, h, summary} =
               Import.apply(new_household(), "kid", bundle, ids(), "v2", ~D[2026-09-27])

      assert summary.attached == 0 and length(summary.items) == 3
      assert Attach.attached(h, "kid") == %{}
      assert map_size(Plans.plans(h, "kid")) == 1
    end
  end
end
