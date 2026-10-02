defmodule Mix.Tasks.Findependence.Demo do
  @shortdoc "Create the alpha's made-up demo family (ROADMAP-ALPHA)"
  @moduledoc """
    mix findependence.demo PATH

  Creates a household vault at PATH holding the roadmap family (ROADMAP-ALPHA §1): Dad, Mom, and
  three kids (Alex 20 and Blake 18 in college, Casey 16 in high school), with Grandma's support for
  college recorded both ways (REV-038), and v0.2's balances, debts, and dates. Every name, figure,
  and relationship is invented; dates are set relative to the day it is created. The passphrases
  are printed, because this household is for testing only; never use them anywhere else.
  """
  use Mix.Task

  alias FindependenceApp.{Session, Vault}
  alias Findependence.{Alignment, Balances, Household}

  @members [
    {"Dad", "dad demo passphrase"},
    {"Mom", "mom demo passphrase"},
    {"Alex", "alex demo passphrase"},
    {"Blake", "blake demo passphrase"},
    {"Casey", "casey demo passphrase"}
  ]

  @week {:every, 1, :week}
  @two_weeks {:every, 2, :week}
  @month {:every, 1, :month}
  @twice_a_year {:every, 6, :month}

  @doc "The demo's members and passphrases."
  def members, do: @members

  @impl true
  def run([path]) do
    if File.exists?(path), do: Mix.raise("#{path} already exists")
    Mix.shell().info(FindependenceApp.Web.release_notice())

    Mix.shell().info(
      "Creating the demo family. Every name, figure, and relationship is invented."
    )

    build(path)

    Mix.shell().info("""

    Created #{path}. Members and their demo passphrases:
    #{Enum.map_join(@members, "\n", fn {m, p} -> "  #{m}: #{p}" end)}

    Start it with:  ERL_CRASH_DUMP_SECONDS=0 mix findependence.serve #{path} 4848
    """)
  end

  def run(_), do: Mix.raise("usage: mix findependence.demo PATH")

  @doc """
  Builds the demo household at `path`. `opts` go to `Vault.create/2` (tests pass fewer
  iterations), except `:today`, the date the demo's dates are set around.
  """
  def build(path, opts \\ []) do
    {today, opts} = Keyword.pop(opts, :today, FindependenceApp.Web.today())
    vault = Vault.create(@members, opts)

    # day `d` of this month, and `k` days from today, as ISO dates
    on = fn d ->
      Date.new!(today.year, today.month, min(d, Date.days_in_month(today))) |> Date.to_iso8601()
    end

    soon = fn k -> today |> Date.add(k) |> Date.to_iso8601() end
    yesterday = soon.(-1)

    sessions =
      Map.new(@members, fn {m, p} ->
        {:ok, s} = Session.open(vault, m, p)
        {m, s}
      end)

    st = %{vault: vault, sessions: sessions}

    # Dad and Mom pay the household's bills together.
    st =
      Enum.reduce(
        [
          {"mortgage", "Mortgage", -224_000, @month, on.(1)},
          {"groceries", "Groceries", -21_000, @week, soon.(2)},
          {"utilities", "Utilities", -26_000, @month, on.(15)},
          {"phone", "Family phone plan", -15_000, @month, on.(5)},
          {"internet", "Internet", -8_000, @month, on.(12)},
          {"car_ins", "Car insurance", -114_000, @twice_a_year, soon.(40)},
          {"card_min", "Credit card payments", -18_000, @month, on.(20)},
          {"heloc", "HELOC payment", -32_000, @month, on.(10)},
          {"repairs", "Home repairs", -240_000, :irregular, nil},
          {"allowance_out", "Casey's allowance", -10_000, @month, on.(1)}
        ],
        st,
        fn {id, note, amount, f, date}, st ->
          st
          |> add("Dad", id, note, amount, f, date)
          |> joint("Dad", id, "Mom")
        end
      )

    # The kids can see the phone plan.
    st =
      Enum.reduce(["Alex", "Blake", "Casey"], st, fn kid, st ->
        {st, pid} = act_p(st, "Dad", &Household.propose_grant(&1, "Dad", "phone", kid))
        act(st, "Mom", &Household.consent(&1, "Mom", pid))
      end)

    # Each parent's own paycheck and private spending.
    st =
      st
      |> add("Dad", "dad_pay", "Dad's paycheck", 265_000, @two_weeks, soon.(9))
      |> add("Dad", "dad_gym", "Gym", -4_500, @month, on.(3))
      |> add("Mom", "mom_pay", "Mom's paycheck", 198_000, @two_weeks, soon.(2))
      |> add("Mom", "mom_lunch", "Work lunches", -6_000, @month, on.(25))

    # The college kids own their tuition and Grandma's support for it (REV-038).
    st =
      Enum.reduce(
        [{"Alex", 680_000, 48_000}, {"Blake", 590_000, 30_000}],
        st,
        fn {kid, tuition, wages}, st ->
          k = String.downcase(kid)

          st
          |> add(kid, "#{k}_tuition", "#{kid}'s tuition", -tuition, @twice_a_year, soon.(60))
          |> add(
            kid,
            "#{k}_grandma",
            "Grandma pays #{kid}'s tuition",
            tuition,
            @twice_a_year,
            soon.(60)
          )
          |> add(kid, "#{k}_books", "#{kid}'s books", -30_000, @twice_a_year, soon.(55))
          |> add(kid, "#{k}_wages", "#{kid}'s campus job", wages, @two_weeks, soon.(4))
          |> value(kid, "#{k}_college", "Finishing college")
          |> link(kid, "#{k}_tuition", "#{k}_college")
          |> link(kid, "#{k}_grandma", "#{k}_college")
          |> link(kid, "#{k}_books", "#{k}_college")
          |> act(kid, &Household.propose_grant(&1, kid, "#{k}_tuition", "Mom"))
          |> act(kid, &Household.propose_grant(&1, kid, "#{k}_grandma", "Mom"))
          |> act(kid, &Household.propose_grant(&1, kid, "#{k}_tuition", "Dad"))
          |> act(kid, &Household.propose_grant(&1, kid, "#{k}_grandma", "Dad"))
        end
      )

    # Casey, 16: a full member with the same privacy as everyone (REV-038).
    st =
      st
      |> add("Casey", "casey_allowance", "Allowance", 10_000, @month, on.(1))
      |> add("Casey", "casey_summer", "Summer job", 120_000, :irregular)
      |> value("Casey", "casey_car", "Saving for a car")
      |> link("Casey", "casey_summer", "casey_car")

    # The parents' values. Mom has asked Dad to own "A secure home" with her: a request for him.
    st =
      st
      |> value("Mom", "secure_home", "A secure home")
      |> link("Mom", "mortgage", "secure_home")
      |> link("Mom", "utilities", "secure_home")
      |> value("Mom", "retire", "Retiring without worry")

    {st, _pid} =
      act_p(st, "Mom", &Household.propose_owners(&1, "Mom", "secure_home", ["Dad", "Mom"]))

    # v0.2 balances and debts (CAP-010). Checking runs low before the next paycheck.
    st =
      st
      |> balance(
        "Dad",
        "checking",
        "Joint checking",
        :account,
        :checking,
        %{balance: 85_000},
        yesterday
      )
      |> balance("Mom", "savings", "Savings", :account, :savings, %{balance: 120_000}, yesterday)
      |> balance(
        "Dad",
        "heloc_debt",
        "HELOC",
        :debt,
        :heloc,
        debt(3_850_000, 875, 32_000),
        yesterday
      )

    st =
      st
      |> act("Dad", &Balances.add_debt(&1, "Dad", "dad_visa", "Visa", :card))
      |> act(
        "Dad",
        &Balances.add_reading(
          &1,
          "Dad",
          "dad_visa",
          Map.put(debt(620_000, 2499, 19_000), :on, yesterday)
        )
      )
      |> act("Mom", &Balances.add_debt(&1, "Mom", "mom_mc", "Mastercard", :card))
      |> act(
        "Mom",
        &Balances.add_reading(
          &1,
          "Mom",
          "mom_mc",
          Map.put(debt(340_000, 2249, 11_000), :on, yesterday)
        )
      )

    # v0.3 (from what the roadmap family is dealing with): Dad's employer health plan depends on his
    # job; his private plan for if the job stops; his side business with a set-aside rate, proposed to
    # Mom as a shared plan; and an emergency fund goal for Mom.
    next = fn k -> Findependence.Projection.months(today) |> Enum.at(k) end

    st =
      st
      |> add("Dad", "dad_health", "Employer health plan", -9_000, @month, on.(1))
      |> act("Dad", &Findependence.Plans.mark(&1, "Dad", "dad_health", "dad_pay"))
      |> add("Dad", "dad_side", "Weekend repair jobs", 40_000, @month)
      |> value("Dad", "side_business", "Side business")
      |> link("Dad", "dad_side", "side_business")
      |> act("Dad", &Findependence.Plans.set_aside(&1, "Dad", "side_business", 2500))
      |> act("Dad", &Findependence.Plans.new_plan(&1, "Dad", "job_stops", "If Dad's job stops"))
      |> act(
        "Dad",
        &Findependence.Plans.add_step(
          &1,
          "Dad",
          "job_stops",
          {:switch_off, ["dad_pay"], next.(1)}
        )
      )
      |> act(
        "Dad",
        &Findependence.Plans.add_step(
          &1,
          "Dad",
          "job_stops",
          {:add, %{note: "Marketplace health premium", amount: -48_000, frequency: @month},
           next.(1)}
        )
      )
      |> act(
        "Dad",
        &Findependence.Plans.add_step(
          &1,
          "Dad",
          "job_stops",
          {:borrow, %{amount: 600_000, rate_bp: 875, payment: 25_000}, next.(2)}
        )
      )
      |> act(
        "Dad",
        &Findependence.Plans.new_plan(&1, "Dad", "side_plan", "Grow the side business")
      )
      |> act(
        "Dad",
        &Findependence.Plans.add_step(
          &1,
          "Dad",
          "side_plan",
          {:add, %{note: "More repair jobs", amount: 80_000, frequency: @month}, next.(2)}
        )
      )
      |> act(
        "Dad",
        &Findependence.Plans.add_step(
          &1,
          "Dad",
          "side_plan",
          {:add, %{note: "Tools", amount: -150_000, frequency: :one_off}, next.(1)}
        )
      )
      |> act("Mom", &Findependence.Plans.set_fund_goal(&1, "Mom", 3))

    {st, _pid} =
      act_p(
        st,
        "Dad",
        &Findependence.Plans.propose_shared(&1, "Dad", "side_plan", "shared_side_plan", ["Mom"])
      )

    # v0.4 (the family isn't sure they're saving enough): Dad's 401(k) and Mom's IRA, which she shares
    # with him; Dad's own assumptions, all invented. Mom hasn't entered any, so her page shows how to
    # start.
    st =
      st
      |> act(
        "Dad",
        &Balances.add_account(&1, "Dad", "dad_401k", "Dad's 401(k)", :retirement_401k)
      )
      |> act(
        "Dad",
        &Balances.add_reading(&1, "Dad", "dad_401k", %{balance: 4_820_000, on: yesterday})
      )
      |> act("Mom", &Balances.add_account(&1, "Mom", "mom_ira", "Mom's IRA", :ira))
      |> act(
        "Mom",
        &Balances.add_reading(&1, "Mom", "mom_ira", %{balance: 2_150_000, on: yesterday})
      )
      |> act("Mom", &Household.propose_grant(&1, "Mom", "mom_ira", "Dad"))

    st =
      [
        birth_year: 1976,
        retire_age: 67,
        return_bp: 400,
        ss_monthly: 230_000,
        target_monthly: 550_000
      ]
      |> Enum.reduce(st, fn {f, v}, st ->
        act(st, "Dad", &Findependence.Retirement.set(&1, "Dad", f, v))
      end)
      |> act("Dad", &Findependence.Retirement.set_contribution(&1, "Dad", "dad_401k", 40_000))

    Vault.write!(st.vault, path)
    :ok
  end

  defp debt(balance, rate_bp, min), do: %{balance: balance, rate_bp: rate_bp, min_payment: min}

  # A joint account or debt of Dad and Mom, with one reading.
  defp balance(st, m, id, label, kind, type, reading, on) do
    add =
      if kind == :account,
        do: &Balances.add_account(&1, m, id, label, type),
        else: &Balances.add_debt(&1, m, id, label, type)

    st
    |> act(m, add)
    |> joint(m, id, if(m == "Dad", do: "Mom", else: "Dad"))
    |> act(m, &Balances.add_reading(&1, m, id, Map.put(reading, :on, on)))
  end

  # The other parent becomes a joint owner, agreeing as every new owner does (WI-086, CP-029).
  defp joint(st, owner, id, joiner) do
    {st, pid} =
      act_p(st, owner, &Household.propose_owners(&1, owner, id, Enum.sort([owner, joiner])))

    act(st, joiner, &Household.consent(&1, joiner, pid))
  end

  defp add(st, m, id, note, cents, frequency, date \\ nil) do
    attrs = %{note: note, amount: cents, unit: :cents, frequency: frequency}
    attrs = if date, do: Map.put(attrs, :on, date), else: attrs
    act(st, m, &Household.add_item(&1, m, id, attrs))
  end

  defp value(st, m, id, label), do: act(st, m, &Alignment.add_value(&1, m, id, label))
  defp link(st, m, item, value), do: act(st, m, &Alignment.link(&1, m, item, value))

  # Runs one core operation as `m` on the latest vault and saves it.
  defp act(st, m, fun) do
    {st, _} = act_p(st, m, fun)
    st
  end

  defp act_p(st, m, fun) do
    s = Session.refresh(st.sessions[m], st.vault)

    {h, pid} =
      case fun.(s.household) do
        {:ok, h} -> {h, nil}
        {:ok, h, pid} -> {h, pid}
        {:error, reason} -> raise "demo step failed for #{m}: #{inspect(reason)}"
      end

    saved = Session.save(%{s | household: h})
    {%{st | vault: saved.vault, sessions: Map.put(st.sessions, m, saved)}, pid}
  end
end
