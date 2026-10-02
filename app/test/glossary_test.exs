defmodule FindependenceApp.GlossaryTest do
  @moduledoc """
  UX-001 R9 (WI-023): one word per concept. Renders every page and message for representative
  states and fails if what a person reads or hears uses a synonym the glossary rules out.
  """
  use ExUnit.Case, async: true
  import FindependenceApp.TestJoint

  alias FindependenceApp.Web.{Glossary, Html}
  alias Findependence.{Alignment, Exit, Household}

  # What a person reads or hears: text, plus aria-label and placeholder values.
  defp user_text(html) do
    html = Regex.replace(~r/<style.*?<\/style>/s, html, " ")

    attrs =
      Regex.scan(~r/(?:aria-label|placeholder)="([^"]*)"/, html)
      |> Enum.map_join(" ", &List.last/1)

    (Regex.replace(~r/<[^>]+>/, html, " ") <> " " <> attrs)
    |> String.replace(["&#39;", "&quot;", "&amp;", "&lt;", "&gt;"], fn
      "&#39;" -> "'"
      "&quot;" -> "\""
      "&amp;" -> "&"
      "&lt;" -> "<"
      "&gt;" -> ">"
    end)
  end

  # A household exercising every state the pages show: sole, joint, shared-with-me, values with a
  # waiting request, links, and history with every kind of event.
  defp household do
    h = Household.new(["ana", "ben", "cy"])

    {:ok, h} =
      Household.add_item(h, "ana", "rent", %{note: "Rent", amount: -145_000, unit: :cents})

    {:ok, h} = Household.add_item(h, "ana", "car", %{note: "Car", amount: -31_000, unit: :cents})

    {:ok, h} =
      Household.add_item(h, "ben", "phone", %{note: "Phone", amount: -5_500, unit: :cents})

    h = joint!(h, "ana", "car", ["ana", "ben"])
    {:ok, h, _} = Household.propose_grant(h, "ana", "rent", "cy")
    {:ok, h, _} = Household.propose_grant(h, "ana", "rent", "ben")
    {:ok, h} = Household.revoke_grant(h, "ana", "rent", "cy")
    {:ok, h, _} = Household.propose_grant(h, "ben", "phone", "ana")
    {:ok, h, _} = Household.propose_grant(h, "ana", "car", "cy")
    {:ok, h} = Alignment.add_value(h, "ana", "home", "A safe home")
    {:ok, h} = Alignment.add_value(h, "ana", "hol", "Holiday")
    h = joint!(h, "ana", "hol", ["ana", "ben"])
    {:ok, h} = Alignment.link(h, "ana", "rent", "home")
    {:ok, h} = Household.add_item(h, "cy", "gym", %{note: "Gym", unit: :cents})
    h = joint!(h, "cy", "gym", ["cy", "ana"])
    {:ok, h} = Household.relinquish(h, "cy", "gym")
    # CAP-010/011: an account and a debt with readings, shared; dated items
    {:ok, h} = Findependence.Balances.add_account(h, "ana", "chk", "Checking", :checking)

    {:ok, h} =
      Findependence.Balances.add_reading(h, "ana", "chk", %{on: "2026-09-20", balance: 50_000})

    {:ok, h} = Findependence.Balances.add_debt(h, "ana", "visa", "Visa", :card)

    {:ok, h} =
      Findependence.Balances.add_reading(h, "ana", "visa", %{
        on: "2026-09-20",
        balance: 520_000,
        rate_bp: 2199,
        min_payment: 15_000
      })

    {:ok, h} =
      Findependence.Balances.add_reading(h, "ana", "visa", %{
        on: "2026-09-27",
        balance: 510_000,
        rate_bp: 2199,
        min_payment: 15_000
      })

    {:ok, h, _} = Household.propose_grant(h, "ana", "visa", "ben")

    {:ok, h} =
      Household.add_item(h, "ana", "pay", %{
        note: "Pay",
        amount: 10_000,
        frequency: {:every, 2, :week},
        on: "2026-10-02"
      })

    {:ok, h} =
      Household.add_item(h, "ana", "ins", %{
        note: "Insurance",
        amount: -90_000,
        frequency: {:every, 6, :month},
        on: "2026-10-05"
      })

    # v0.3: a plan with every kind of step, a mark, goals, and a shared plan waiting for ben
    {:ok, h} = Findependence.Plans.new_plan(h, "ana", "p1", "If the job stops")
    {:ok, h} = Findependence.Plans.add_step(h, "ana", "p1", {:switch_off, ["pay"], "2026-11"})

    {:ok, h} =
      Findependence.Plans.add_step(
        h,
        "ana",
        "p1",
        {:add, %{note: "Premium", amount: -60_000, frequency: {:every, 1, :month}}, "2026-11"}
      )

    {:ok, h} =
      Findependence.Plans.add_step(
        h,
        "ana",
        "p1",
        {:borrow, %{amount: 500_000, rate_bp: 900, payment: 20_000}, "2026-12"}
      )

    {:ok, h} = Findependence.Plans.set_fund_goal(h, "ana", 3)
    {:ok, h, _} = Findependence.Plans.propose_shared(h, "ana", "p1", "sp1", ["ben"])

    # v0.4: a 401(k) and a full set of retirement assumptions for ana
    {:ok, h} = Findependence.Balances.add_account(h, "ana", "k401", "401(k)", :retirement_401k)

    {:ok, h} =
      Findependence.Balances.add_reading(h, "ana", "k401", %{on: "2026-09-01", balance: 5_000_000})

    h =
      Enum.reduce(
        [
          birth_year: 1970,
          retire_age: 67,
          return_bp: 500,
          ss_monthly: 200_000,
          target_monthly: 450_000
        ],
        h,
        fn {f, v}, h ->
          {:ok, h} = Findependence.Retirement.set(h, "ana", f, v)
          h
        end
      )

    {:ok, h} = Findependence.Retirement.set_contribution(h, "ana", "k401", 50_000)
    h
  end

  test "the pages checked include a plan request as the one asked sees it" do
    assert Enum.any?(pages(), &(is_binary(&1) and &1 =~ "asked you to share this plan"))
  end

  defp pages do
    h = household()
    members = ["ana", "ben", "cy"]

    member_pages =
      for m <- members do
        items = Map.keys(Html.names(h, m))

        [
          Html.home(h, m, "", {:ok, "x"}, %{error: "x"}),
          Html.leave_page(h, m, ""),
          Html.next_60_page(h, m, ~D[2026-09-27]),
          Html.ahead_page(h, m, ~D[2026-09-27]),
          Html.plans_page(h, m, ""),
          Html.goals_page(h, m, ""),
          Html.retirement_page(h, m, "", ~D[2026-09-27]),
          Html.retirement_page(h, m, "", ~D[2026-09-27], nil, %{
            values: %{"return" => "20"},
            errors: %{"return" => "Enter a yearly return from −5 to 15, like 5 or 4.5."}
          }),
          Html.coming_up_card(h, m, ~D[2026-09-27]),
          Html.export_page(Exit.export(h, m), Html.names(h, m))
        ] ++
          Enum.map(items, &Html.item_page(h, m, &1, "")) ++
          for(
            p <- Findependence.Household.pending(h, m),
            page = Html.request_page(h, m, to_string(p.id), "", ~D[2026-09-27]),
            do: page
          )
      end

    List.flatten(member_pages) ++
      [
        Html.leave_page(Household.new(["ana", "ben"]), "ana", ""),
        # cy owns nothing after sharing and then no longer owning the gym: the leave button shows
        Html.leave_page(h, "cy", ""),
        Html.login(members, "", "x", :idle),
        Html.login(members, "", nil, :idle_action),
        Html.integrity_banner([:x]),
        Html.confirm_page("delete", %{"item" => "rent"}, "Rent", ""),
        Html.plan_page(h, "ana", "p1", "", ~D[2026-09-27]),
        Html.item_page(h, "ana", "sp1", ""),
        Html.item_page(h, "ana", "visa", "", nil, %{query: %{"extra" => "100", "rate" => "10"}}),
        Html.new_balance_page("", %{
          which: "debt",
          label: "x",
          type: "",
          error: "Choose what kind it is."
        }),
        Html.item_page(h, "ana", "visa", "", nil, %{
          error: "Enter the interest rate as a percentage, like 21.99.",
          error_field: :rate
        }),
        Html.confirm_page("relinquish", %{"item" => "car"}, "Car", "", ["ben"]),
        # v0.5: bringing a record in, and every way it can be refused
        Html.bring_in_page(""),
        Html.bring_in_page("", nil, :no_file),
        Html.bring_in_page("", nil, :too_large),
        Html.bring_in_page("", nil, :not_json),
        Html.bring_in_page("", nil, {:already_imported, "2026-09-27"}),
        Html.bring_in_page("", nil, {:problems, bring_in_problems()}),
        Html.bring_in_preview(
          %{
            items: ["Rent", "Paycheck"],
            values: ["Home"],
            accounts: ["Checking"],
            debts: ["Visa"],
            readings: 3,
            links: 1,
            plans: ["If the job stops"],
            marks: 1,
            attached: 1,
            goals: 2,
            retirement: 3,
            shared_plans: 1
          },
          "findependence-export.json",
          ""
        )
      ] ++
      Enum.map(Html.error_reasons(), &Html.error_text/1) ++
      outcomes(h)
  end

  # one problem of every kind the checker reports, where the interface words it
  defp bring_in_problems do
    whats = [
      :not_an_export,
      :unknown_version,
      :missing,
      :not_a_list,
      :not_an_object,
      {:too_many, 2_000},
      :unknown_field,
      :invalid_id,
      :invalid_amount,
      :invalid_unit,
      :invalid_frequency,
      :invalid_date,
      :invalid_month,
      :invalid_text,
      :invalid_kind,
      :readings_not_allowed,
      :invalid_rate,
      {:duplicate_id, "x"},
      :bad_reference,
      :invalid_step,
      :invalid_goal,
      :invalid_retirement
    ]

    for {w, i} <- Enum.with_index(whats),
        do: {"items[#{i}].attrs.amount", w}
  end

  defp outcomes(h) do
    for {action, params} <- [
          {"add_item", %{"note" => "Rent"}},
          {"add_value", %{"label" => "Holiday"}},
          {"grant", %{"item" => "rent", "member" => "ben"}},
          {"grant", %{"item" => "car", "member" => "cy"}},
          {"revoke", %{"item" => "rent", "member" => "ben"}},
          {"owners", %{"item" => "car", "owners" => ["ben"]}},
          {"consent", %{"proposal" => "1"}},
          {"withdraw", %{"proposal" => "1"}},
          {"relinquish", %{"item" => "car"}},
          {"delete", %{"item" => "rent"}},
          {"let_go", %{"item" => "rent", "to" => "give:ben"}},
          {"let_go", %{"item" => "rent", "to" => "delete"}},
          {"link", %{"item" => "rent", "value" => "home"}},
          {"unlink", %{"item" => "rent", "value" => "home"}},
          {"bring_in", %{}},
          {"retirement", %{}}
        ] do
      Html.outcome(action, params, h, h, "ana")
    end
  end

  test "every page and message uses the glossary's words" do
    found =
      for page <- pages(), {word, instead} <- Glossary.violations(user_text(page)) do
        "“#{word}” (use #{instead})"
      end

    assert Enum.uniq(found) == []
  end

  test "no page or message judges: no good, bad, risk, on track, over budget (ROADMAP-ALPHA section 3)" do
    found = for page <- pages(), w <- Glossary.judgments(user_text(page)), do: w
    assert Enum.uniq(found) == []
  end

  test "the judgment check catches judgments" do
    assert Glossary.judgments("You're on track. That's risky, and over budget.") ==
             ["on track", "risky", "over budget"]
  end

  test "the check catches synonyms, including in labels read aloud" do
    assert [{"proposal", "request"}] =
             Glossary.violations(
               user_text(~s(<button aria-label="Withdraw this proposal">Withdraw</button>))
             )

    assert Glossary.violations(user_text("<p>Also visible to ben. Let ben see it.</p>")) != []

    assert Glossary.violations(user_text("<p>Ben can see it. Share it, or stop owning it.</p>")) ==
             []
  end

  test "the glossary names UX-001 R9's eight terms, per month and one-off (REQ-126), the v0.2 terms, and the v0.4 terms" do
    assert Enum.map(Glossary.terms(), &elem(&1, 0)) ==
             [
               "item",
               "value",
               "owner",
               "can see",
               "share / stop sharing",
               "give away",
               "stop owning",
               "request",
               "per month",
               "one-off",
               "account",
               "debt",
               "balance",
               "interest",
               "coming up",
               "set aside",
               "retirement account",
               "return",
               "Social Security estimate",
               "target income"
             ]
  end
end
