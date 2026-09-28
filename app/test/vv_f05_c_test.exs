defmodule FindependenceApp.VVF05CTest do
  @moduledoc """
  VV-001 F-05/F-08 batch C (WI-057): acceptance criteria of REQ-136, 140, 143, 145, 146, 160, 161,
  162, 172, and 173 that no earlier test asserted, at the interface, with today fixed at Sunday,
  September 27, 2026. Criteria are recorded in project/assurance/vv/acceptance-c.yaml.
  """
  use ExUnit.Case, async: false
  import Plug.Test

  alias Findependence.{Attach, Balances, Household, Plans, Projection}
  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}
  alias FindependenceApp.Web.{Glossary, Html}

  @today ~D[2026-09-27]
  @month {:every, 1, :month}

  setup do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-vvc-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana pass 1"}, {"ben", "ben pass 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  # --- helpers copied from v03_web_test.exs and cp014_web_test.exs

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  # the page's one-time form token, as a browser sends it with the form (REQ-165, DEF-041)
  defp form_id(page), do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp post(prev, path, params) do
    page = request(:get, "/", %{}, prev)

    request(
      :post,
      path,
      Map.merge(params, %{"_csrf_token" => token(page), "_form" => form_id(page)}),
      page
    )
  end

  defp login(m, p), do: post(request(:get, "/"), "/login", %{"member" => m, "passphrase" => p})
  defp loc(resp), do: resp |> Plug.Conn.get_resp_header("location") |> hd()
  defp new_id(resp), do: resp |> loc() |> String.split("/") |> List.last()
  defp follow(resp), do: request(:get, loc(resp), %{}, resp).resp_body

  defp household(path, m \\ "ana", p \\ "ana pass 1") do
    {:ok, s} = Session.open(Vault.read!(path), m, p)
    s.household
  end

  defp id_of(path, note),
    do:
      Enum.find_value(household(path).items, fn {id, i} ->
        (i.attrs[:note] || i.attrs[:label]) == note && id
      end)

  defp text(html),
    do:
      html
      |> String.replace(~r/<style>.*?<\/style>/s, "")
      |> String.replace(~r/<[^>]+>/, " ")
      |> String.replace("&#39;", "'")
      |> String.replace(~r/\s+/, " ")

  # --- core households, for pages rendered directly (as ux002_test.exs does)

  defp ok({:ok, h}), do: h
  defp ok({:ok, h, _}), do: h

  defp add(h, m, id, note, amount, f, on \\ nil) do
    attrs = %{note: note, amount: amount, unit: :cents, frequency: f}
    attrs = if on, do: Map.put(attrs, :on, on), else: attrs
    ok(Household.add_item(h, m, id, attrs))
  end

  defp with_checking(h, m, balance) do
    h = ok(Balances.add_account(h, m, "chk", "Checking", :checking))
    ok(Balances.add_reading(h, m, "chk", %{on: "2026-09-27", balance: balance}))
  end

  defp one_offs(dates) do
    dates
    |> Enum.with_index()
    |> Enum.reduce(Household.new(["ana"]), fn {on, k}, h ->
      add(h, "ana", "i#{k}", "Item #{k}", -1_000, :one_off, on)
    end)
    |> with_checking("ana", 100_000)
  end

  defp flow_dates(html),
    do:
      Regex.scan(~r/<td role=cell class=fdate data-label="Date"><b>([^<]+)<\/b>/, html,
        capture: :all_but_first
      )
      |> List.flatten()

  # ---------------------------------------------------------------------------

  test "REQ-136: the add-item form offers exactly one date, and it is optional" do
    [form] =
      Regex.run(
        ~r/<form method=post action="\/act\/add_item".*?<\/form>/s,
        Html.home(Household.new(["ana"]), "ana", "")
      )

    assert length(Regex.scan(~r/name=on\b/, form)) == 1
    [input] = Regex.run(~r/<input id=on name=on type=date[^>]*>/, form)
    refute input =~ "required"
  end

  test "REQ-140: every 2 months, every 3 months, and yearly money out are set aside for; more frequent and one-off money out aren't" do
    h =
      Household.new(["ana"])
      |> add("ana", "water", "Water", -9_000, {:every, 2, :month}, "2026-10-05")
      |> add("ana", "trash", "Trash", -12_000, {:every, 3, :month})
      |> add("ana", "domain", "Domain", -2_400, {:every, 1, :year})
      |> add("ana", "groceries", "Groceries", -15_000, {:every, 1, :week})
      |> add("ana", "sitter", "Sitter", -20_000, {:every, 2, :week})
      |> add("ana", "rent", "Rent", -200_000, @month)
      |> add("ana", "tv", "TV", -50_000, :one_off, "2026-10-10")

    page = Html.next_60_page(h, "ana", @today)
    [card] = Regex.run(~r/<h2>Setting aside for bills.*?<\/section>/s, page)
    assert card =~ "Setting aside <b>$87.00 a month</b> covers these:"
    assert card =~ "Water</a>: −$90.00 every two months, $45.00 a month"
    assert card =~ "Trash</a>: −$120.00 every three months, $40.00 a month"
    assert card =~ "Domain</a>: −$24.00 a year, $2.00 a month"

    for name <- ["Groceries", "Sitter", "Rent", "TV"], do: refute(card =~ name)
  end

  describe "REQ-143" do
    defp plan_h do
      h =
        Household.new(["ana", "ben"])
        |> add("ana", "pay", "Paycheck", 300_000, @month, "2026-10-01")
        |> with_checking("ana", 100_000)
        |> then(&ok(Plans.new_plan(&1, "ana", "p1", "Trip")))

      h =
        ok(
          Plans.add_step(
            h,
            "ana",
            "p1",
            {:borrow, %{amount: 500_000, rate_bp: 900, payment: 20_000}, "2026-11"}
          )
        )

      ok(Plans.add_step(h, "ana", "p1", {:switch_off, ["pay"], "2027-01"}))
    end

    test "the twelve months side by side, with and without, and the interest on the borrowing stated" do
      h = plan_h()
      page = Html.plan_page(h, "ana", "p1", "", @today)
      assert length(Regex.scan(~r/data-label="Without this plan"/, page)) == 12
      assert length(Regex.scan(~r/data-label="With this plan"/, page)) == 12
      assert page =~ "October 2026" and page =~ "September 2027"

      [loan] =
        Enum.filter(
          Projection.project(h, "ana", @today, Plans.plans(h, "ana")["p1"]).debts,
          & &1.planned
        )

      assert loan.interest > 0
      interest = Html.format_amount(loan.interest) |> String.replace_prefix("+", "")
      assert page =~ "Interest on the planned borrowing over these months: #{interest}."
    end

    test "the places a plan appears that say it is a plan: plans list, plan page, request, shared plan page, the asked member's home" do
      h = plan_h()
      plans = text(Html.plans_page(h, "ana", ""))
      assert plans =~ "Trip 2 steps, private to you"
      assert text(Html.plan_page(h, "ana", "p1", "", @today)) =~ "A plan, private to you."

      assert text(Html.plan_page(h, "ana", "p1", "", @today)) =~
               "This is a plan, not what's real."

      {:ok, h, pid} = Plans.propose_shared(h, "ana", "p1", "sp", ["ben"])
      assert text(Html.home(h, "ben", "")) =~ "Request: share the plan “Trip” with ana."
      assert text(Html.request_page(h, "ben", "#{pid}", "", @today)) =~ "share this plan"
      h = ok(Household.consent(h, "ben", pid))

      for m <- ["ana", "ben"] do
        assert text(Html.item_page(h, m, "sp", "")) =~ "A shared plan, owned by"
        assert text(Html.plans_page(h, m, "")) =~ "Trip shared plan, owned by"
      end
    end
  end

  describe "REQ-145" do
    setup %{path: path} do
      ana = login("ana", "ana pass 1")
      visa = new_id(post(ana, "/act/add_debt", %{"label" => "Visa", "type" => "card"}))
      car = new_id(post(ana, "/act/add_debt", %{"label" => "Car loan", "type" => "loan"}))

      for {id, bal, rate, min, on} <- [
            {visa, "8,000", "19.99", "250", "2026-08-27"},
            {visa, "6,200", "24.99", "190", "2026-09-27"},
            {car, "9,000", "5", "300", "2026-09-27"}
          ],
          do:
            post(ana, "/act/add_reading", %{
              "item" => id,
              "balance" => bal,
              "rate" => rate,
              "min_payment" => min,
              "on" => on
            })

      post(ana, "/act/grant", %{"item" => visa, "member" => "ben"})
      %{path: path, ana: ana, visa: visa, car: car}
    end

    test "a member it's shared with sees the what-ifs, worked out from the latest reading", %{
      visa: visa
    } do
      ben = login("ben", "ben pass 2")
      page = request(:get, "/items/#{visa}", %{"extra" => "100", "rate" => "10"}, ben).resp_body
      {:ok, n, int} = Projection.payoff(620_000, 2499, 19_000)
      {:ok, n2, int2} = Projection.payoff(620_000, 2499, 29_000)
      body = text(page)
      assert body =~ "Paying the minimum of $190.00, it would take"

      assert body =~
               "with #{Html.format_amount(int) |> String.replace_prefix("+", "")} of interest"

      assert body =~ "With $100.00 more a month:"
      assert body =~ "#{Html.format_amount(int2) |> String.replace_prefix("+", "")} of interest"
      assert body =~ "At 10%: a month's interest on $6,200.00 would be $51.67."
      assert n > n2
    end

    test "for an owner too, the what-ifs are worked out from the latest of several readings", %{
      ana: ana,
      visa: visa
    } do
      body = text(request(:get, "/items/#{visa}", %{"extra" => "100"}, ana).resp_body)
      {:ok, _, int} = Projection.payoff(620_000, 2499, 19_000)
      assert body =~ "Paying the minimum of $190.00, it would take"

      assert body =~
               "with #{Html.format_amount(int) |> String.replace_prefix("+", "")} of interest"

      refute body =~ "minimum of $250.00"
    end

    test "no payment order is suggested: a debt's what-if names no other debt and no order to pay in",
         %{ana: ana, visa: visa, car: car} do
      for {id, other} <- [{visa, "Car loan"}, {car, "Visa"}] do
        page = request(:get, "/items/#{id}", %{"extra" => "100", "rate" => "10"}, ana).resp_body
        [section] = Regex.run(~r/<section class=card><h2>What if<\/h2>.*?<\/section>/s, page)
        t = text(section)
        refute t =~ other

        assert Regex.scan(
                 ~r/\b(first|before|next|priorit\w*|avalanche|snowball|should|recommend\w*|instead|highest|lowest|focus|target)\b/i,
                 t
               ) == []

        assert Glossary.judgments(t) == []
      end
    end
  end

  test "REQ-146: no goal is supplied; one member's goal isn't shown to another", %{path: path} do
    ana = login("ana", "ana pass 1")
    sav = new_id(post(ana, "/act/add_account", %{"label" => "Savings", "type" => "savings"}))
    post(ana, "/act/add_reading", %{"item" => sav, "balance" => "6,000", "on" => "2026-09-27"})

    post(ana, "/act/add_item", %{
      "note" => "Rent",
      "amount" => "2,000",
      "direction" => "out",
      "frequency" => "monthly"
    })

    page = request(:get, "/goals", %{}, ana).resp_body
    assert page =~ "About 3.0 months"
    refute page =~ "Your goal"

    assert page =~
             ~s(name=months inputmode=numeric autocomplete=off placeholder="e.g. 3" value="")

    follow(post(ana, "/act/fund_goal", %{"months" => "5"}))
    assert request(:get, "/goals", %{}, ana).resp_body =~ "Your goal: 5 months"
    assert Plans.goals(household(path), "ana").fund_months == 5

    post(ana, "/act/grant", %{"item" => sav, "member" => "ben"})
    ben = login("ben", "ben pass 2")
    theirs = request(:get, "/goals", %{}, ben).resp_body
    refute theirs =~ "Your goal"
    refute theirs =~ "of 5"
    assert theirs =~ ~s(placeholder="e.g. 3" value="")
    assert Plans.goals(household(path, "ben", "ben pass 2"), "ben").fund_months == nil
  end

  test "REQ-160: an 'other' account is offered, and choosing a different account replaces the first",
       %{path: path} do
    ana = login("ana", "ana pass 1")

    post(ana, "/act/add_item", %{
      "note" => "Rent",
      "amount" => "2,000",
      "direction" => "out",
      "frequency" => "monthly",
      "on" => "2026-10-01"
    })

    rent = id_of(path, "Rent")
    chk = new_id(post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"}))
    box = new_id(post(ana, "/act/add_account", %{"label" => "Cash box", "type" => "other"}))
    page = request(:get, "/items/#{rent}", %{}, ana).resp_body
    assert page =~ ~s(<option value="#{box}">Cash box</option>)

    follow(
      post(ana, "/act/attach", %{"item" => rent, "account" => chk, "return" => "/items/#{rent}"})
    )

    assert Attach.attached(household(path), "ana") == %{rent => chk}

    page =
      follow(
        post(ana, "/act/attach", %{"item" => rent, "account" => box, "return" => "/items/#{rent}"})
      )

    assert page =~ "“Rent” now goes through “Cash box” in your Coming up and the next 12 months."
    assert page =~ ~s(<option value="#{box}" selected>Cash box</option>)
    refute page =~ ~s(<option value="#{chk}" selected>)
    assert Attach.attached(household(path), "ana") == %{rent => box}
  end

  describe "REQ-161 Coming up on home" do
    test "at most the first four days with something on them, in date order, then how many more days" do
      h = one_offs(~w(2026-10-08 2026-09-28 2026-10-04 2026-09-30 2026-10-06 2026-10-02))
      card = Html.coming_up_card(h, "ana", @today)

      assert flow_dates(card) == [
               "Monday, September 28",
               "Wednesday, September 30",
               "Friday, October 2",
               "Sunday, October 4"
             ]

      assert card =~ "And 2 more days with something on them in the next 14."

      one_more =
        Html.coming_up_card(
          one_offs(~w(2026-09-28 2026-09-30 2026-10-02 2026-10-04 2026-10-06)),
          "ana",
          @today
        )

      assert length(flow_dates(one_more)) == 4
      assert one_more =~ "And 1 more day with something on them in the next 14."

      four =
        Html.coming_up_card(
          one_offs(~w(2026-09-28 2026-09-30 2026-10-02 2026-10-04)),
          "ana",
          @today
        )

      assert length(flow_dates(four)) == 4
      refute four =~ "more day"
    end

    test "a way to the full view" do
      card = Html.coming_up_card(one_offs(~w(2026-09-28)), "ana", @today)
      assert card =~ ~s(<a href="/next-60-days">The next 60 days</a>)
      assert request(:get, "/next-60-days", %{}, login("ana", "ana pass 1")).status == 200
    end

    test "the next fourteen days: the thirteenth day after today is in, the fourteenth isn't" do
      card = Html.coming_up_card(one_offs(~w(2026-10-10 2026-10-11)), "ana", @today)
      assert flow_dates(card) == ["Saturday, October 10"]
      refute card =~ "more day"
    end
  end

  test "REQ-162: a debt paid off within the twelve months shows the month and nothing owed after" do
    h = Household.new(["ana"])
    h = ok(Balances.add_debt(h, "ana", "loan", "Small loan", :loan))

    h =
      ok(
        Balances.add_reading(h, "ana", "loan", %{
          on: "2026-09-27",
          balance: 50_000,
          rate_bp: 1200,
          min_payment: 20_000
        })
      )

    page = Html.ahead_page(h, "ana", @today)
    [row] = Regex.run(~r/<tr role=row><td role=cell data-label="Debt">.*?<\/tr>/s, page)
    assert row =~ "Small loan"
    assert row =~ ~s(data-short="In 12 months">$0.00<)
    assert row =~ ~s(data-label="Interest over 12 months" data-short="Interest">$9.13<)
    assert row =~ ~s(data-short="Paid off">December 2026<)
  end

  describe "REQ-172 account and debt pages, and home's list" do
    defp balances_h do
      h = Household.new(["ana", "ben"]) |> with_checking("ana", 124_050)
      h = ok(Balances.add_reading(h, "ana", "chk", %{on: "2026-09-26", balance: 99_000}))
      h = ok(Balances.add_debt(h, "ana", "visa", "Visa", :card))

      h =
        ok(
          Balances.add_reading(h, "ana", "visa", %{
            on: "2026-08-27",
            balance: 600_000,
            rate_bp: 2199,
            min_payment: 15_000
          })
        )

      ok(
        Balances.add_reading(h, "ana", "visa", %{
          on: "2026-09-25",
          balance: 520_000,
          rate_bp: 2199,
          min_payment: 15_000
        })
      )
    end

    test "home lists each account and debt in one row that links to its page, with no account or debt forms" do
      home = Html.home(balances_h(), "ana", "")

      [card] =
        Regex.run(~r/<section class=card><h2>Balances and debts<\/h2>.*?<\/section>/s, home)

      rows = Regex.scan(~r/<tr role=row><td role=cell data-label="Account or debt">/, card)
      assert length(rows) == 2
      assert card =~ ~s(<a href="/items/chk"><b>Checking</b></a>)
      assert card =~ ~s(<a href="/items/visa"><b>Visa</b></a>)
      assert card =~ "Credit card, as of Friday, September 25"

      for action <- ~w(/act/add_account /act/add_debt /act/add_reading),
          do: refute(home =~ ~s(action="#{action}"))
    end

    test "a debt's page gives the date its latest reading is as of" do
      page = Html.item_page(balances_h(), "ana", "visa", "")

      assert page =~
               ~s(<p class="amount-big">$5,200.00 owed</p><p class=hint>As of Friday, September 25.</p>)
    end

    test "owners see what they can do and the earlier readings and history; someone it's shared with sees neither" do
      h = balances_h()

      for id <- ["chk", "visa"] do
        page = Html.item_page(h, "ana", id, "")

        for action <- ~w(/act/add_reading /act/grant /act/owners /confirm/delete),
            do: assert(page =~ ~s(action="#{action}"), "#{id} #{action}")

        assert page =~ "<h2>Earlier balances</h2>"
        assert page =~ "<h2>History</h2>"
      end

      h =
        h
        |> then(&ok(Household.propose_grant(&1, "ana", "chk", "ben")))
        |> then(&ok(Household.propose_grant(&1, "ana", "visa", "ben")))

      for id <- ["chk", "visa"] do
        page = Html.item_page(h, "ben", id, "")
        refute page =~ ~s(action="/act/)
        refute page =~ ~s(action="/confirm/)
        refute page =~ "Earlier balances"
        refute page =~ "<h2>History</h2>"
        assert page =~ "As of"
      end
    end
  end

  describe "REQ-173 the next sixty days" do
    test "the fifty-ninth day after today is in, the sixtieth isn't; a day below zero on the last day is marked" do
      h =
        Household.new(["ana"])
        |> add("ana", "a", "Last day", -1_000, :one_off, "2026-11-25")
        |> add("ana", "b", "Day after", -1_000, :one_off, "2026-11-26")
        |> with_checking("ana", 500)

      page = Html.next_60_page(h, "ana", @today)
      assert flow_dates(page) == ["Wednesday, November 25"]
      refute page =~ "Day after"
      assert page =~ "<b>Below zero:</b> Wednesday, November 25."
      assert page =~ "−$5.00 <span class=below>Below zero</span>"
    end
  end
end
