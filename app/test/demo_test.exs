defmodule FindependenceApp.DemoTest do
  @moduledoc "WI-035: the made-up roadmap family (ROADMAP-ALPHA §1), as each member sees it."
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias FindependenceApp.{Session, Vault}
  alias Findependence.{Alignment, Household, View}
  alias Mix.Tasks.Findependence.Demo

  setup_all do
    path = Path.join(System.tmp_dir!(), "fv-demo-#{System.unique_integer([:positive])}.vault")
    :ok = Demo.build(path, iterations: 1_000, unsafe_test: true, today: ~D[2026-09-27])
    on_exit(fn -> File.rm(path) end)

    views =
      Map.new(Demo.members(), fn {m, p} ->
        {:ok, s} = Session.open(Vault.read!(path), m, p)
        {m, s.household}
      end)

    %{views: views}
  end

  defp titles(h, m),
    do:
      View.visible_items(h, m) |> Enum.map(&(&1.attrs[:note] || &1.attrs[:label])) |> Enum.sort()

  test "every member can unlock with the printed demo passphrase", %{views: views} do
    assert Map.keys(views) |> Enum.sort() == ["Alex", "Blake", "Casey", "Dad", "Mom"]
  end

  test "the parents own the household bills together; the kids see only the phone plan of those",
       %{views: views} do
    h = views["Dad"]
    assert h.items["mortgage"].owners == MapSet.new(["Dad", "Mom"])
    assert h.items["phone"].grantees == MapSet.new(["Alex", "Blake", "Casey"])
    assert "Family phone plan" in titles(views["Casey"], "Casey")
    refute "Mortgage" in titles(views["Casey"], "Casey")
  end

  test "each parent's paycheck is private to them", %{views: views} do
    assert "Dad's paycheck" in titles(views["Dad"], "Dad")
    refute "Dad's paycheck" in titles(views["Mom"], "Mom")
    refute "Mom's paycheck" in titles(views["Dad"], "Dad")
  end

  test "Grandma's support is recorded both ways by each college kid, and cancels out per month",
       %{views: views} do
    h = views["Alex"]
    %{by_value: bv, unlinked: u} = Alignment.distribution(h, "Alex")
    college = bv["alex_college"]
    # tuition 6,800 twice a year = 1,133.33 a month each way; books 300 twice a year = 50
    assert college.per_month == %{in: 113_333, out: -113_333 - 5_000}
    assert college.count == 3
    # the campus job (480 every two weeks = 1,040 a month) and the phone plan the parents shared
    assert u.per_month == %{in: 104_000, out: -15_000}
    # both parents can see the college kids' tuition and Grandma's support
    assert "Grandma pays Alex's tuition" in titles(views["Mom"], "Mom")
    assert "Grandma pays Blake's tuition" in titles(views["Dad"], "Dad")
  end

  test "Casey, 16, is a full member with private items", %{views: views} do
    assert titles(views["Casey"], "Casey") ==
             ["Allowance", "Family phone plan", "Saving for a car", "Summer job"]

    refute "Summer job" in titles(views["Mom"], "Mom")
  end

  test "one request is waiting: Mom asked Dad to own 'A secure home' with her", %{views: views} do
    waiting_for_dad = Enum.reject(Household.pending(views["Dad"], "Dad"), &("Dad" in &1.consents))
    assert [%{change: {:owners, owners}}] = waiting_for_dad
    assert owners == MapSet.new(["Dad", "Mom"])
    assert Household.pending(views["Casey"], "Casey") == []
  end

  test "balances and debts: joint checking and a HELOC, each parent's own card, none for the kids",
       %{views: views} do
    alias Findependence.Balances
    assert %{balance: 85_000, on: "2026-09-26"} = Balances.latest(views["Dad"], "Dad", "checking")
    assert %{rate_bp: 875} = Balances.latest(views["Mom"], "Mom", "heloc_debt")
    assert Balances.latest(views["Mom"], "Mom", "dad_visa") == nil
    assert Balances.latest(views["Dad"], "Dad", "mom_mc") == nil
    refute "Joint checking" in titles(views["Casey"], "Casey")
  end

  test "the next two weeks run low before a paycheck, from the joint checking balance", %{
    views: views
  } do
    %{start: start, days: days} =
      Findependence.Schedule.cash_flow(views["Dad"], "Dad", ~D[2026-09-27], 14)

    assert start.balance == 85_000 and start.accounts == ["checking"]
    assert Enum.any?(days, &(&1.balance != nil and &1.balance < 0))
  end

  test "the task prints the alpha rule and the passphrases, and refuses to overwrite" do
    path = Path.join(System.tmp_dir!(), "fv-demo-run-#{System.unique_integer([:positive])}.vault")
    on_exit(fn -> File.rm(path) end)
    out = capture_io(fn -> Demo.run([path]) end)
    assert out =~ "Alpha: use made-up data only."
    assert out =~ "Casey: casey demo passphrase"
    assert {:ok, _} = Session.open(Vault.read!(path), "Casey", "casey demo passphrase")
    assert Vault.read!(path).iterations >= 600_000
    assert_raise Mix.Error, ~r/already exists/, fn -> Demo.run([path]) end
  end

  test "v0.3: Dad's private plans, his job mark and set-aside, Mom's goal, and a shared plan waiting for Mom",
       %{views: views} do
    alias Findependence.{Household, Plans, Projection}
    dad = views["Dad"]
    assert Plans.plans(dad, "Dad") |> Map.keys() |> Enum.sort() == ["job_stops", "side_plan"]
    assert Plans.plans(views["Mom"], "Mom") == %{}
    assert Plans.depends(dad, "Dad") == [{"dad_health", "dad_pay"}]
    assert [%{set_aside: 10_000}] = Projection.set_asides(dad, "Dad")
    assert Plans.goals(views["Mom"], "Mom").fund_months == 3
    plan = Plans.plans(dad, "Dad")["job_stops"]
    [_, nov | _] = Projection.project(dad, "Dad", ~D[2026-09-27], plan).months
    [_, nov0 | _] = Projection.project(dad, "Dad", ~D[2026-09-27]).months
    assert nov.in < nov0.in

    assert Enum.any?(
             Household.pending(views["Mom"], "Mom"),
             &match?(%{attrs: %{kind: :plan}}, &1)
           )
  end

  test "v0.4: Dad's 401(k) and his own assumptions; Mom's IRA, shared with Dad; none of it is cash",
       %{views: views} do
    alias Findependence.{Balances, Projection, Retirement}
    dad = views["Dad"]
    mom = views["Mom"]
    today = ~D[2026-09-27]

    p = Retirement.project(dad, "Dad", today)
    assert p.start.accounts == ["dad_401k", "mom_ira"]
    assert p.start.balance == 4_820_000 + 2_150_000
    assert p.retire_year == 2043 and p.monthly_contribution == 40_000
    assert p.gap == 550_000 - 230_000
    # checked against the annuity formulas: about 244,200 at 4% a year (monthly) over 196 months,
    # and about 88.2 months paying 3,200 a month from it
    assert p.at_retirement == 24_419_537 and p.lasts == {:months, 88}

    # Mom has entered nothing; her IRA is hers, and the kids see neither account
    assert Retirement.project(mom, "Mom", today) ==
             {:missing, [:birth_year, :retire_age, :return_bp]}

    assert Balances.latest(mom, "Mom", "mom_ira").balance == 2_150_000

    for kid <- ["Alex", "Blake", "Casey"],
        do: refute(Enum.any?(View.visible_items(views[kid], kid), &Balances.retirement?/1))

    # the next twelve months still start from cash only
    refute "dad_401k" in Projection.project(dad, "Dad", today).start.accounts
  end
end
