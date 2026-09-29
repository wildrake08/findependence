defmodule FindependenceHostedWeb.Pages.GoalsTest do
  @moduledoc """
  WI-076: goals, set-asides, and retirement say what the local form's pages say (REQ-106, REQ-129, REQ-146,
  REQ-150, REQ-151, REQ-153, REQ-154, REQ-174), and their forms act as the local form's do.
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceShared.{Balances, GoalWords, Items, Money, Planning, Values, Words}

  # --- the local form's checks (app/lib/findependence_app/web/glossary.ex and app/test/vv_f05_d_test.exs) ---

  # ROADMAP-ALPHA section 3: computed results carry no judgment.
  @judgment ~r/\b(good|bad|risky?|healthy|unhealthy|on track|off track|over budget|under budget|warning|danger(ous)?|too much|too little|you can afford|can.t afford)\b/i

  # UX-001 R9: synonyms of the glossary's terms.
  @banned [
    ~r/\bmoney items?\b/i,
    ~r/\bthings?\b/i,
    ~r/\bsomething\b/i,
    ~r/\bheld by\b/i,
    ~r/\bvisib(le|ility)\b/i,
    ~r/\blet (\w+ )?see\b/i,
    ~r/\bgrant(s|ed|ee|ees)?\b/i,
    ~r/\brevok\w*/i,
    ~r/\bunshar\w*/i,
    ~r/\btransfer\w*/i,
    ~r/\bhand over\b/i,
    ~r/\brelinquish\w*/i,
    ~r/\blet(ting)? go\b/i,
    ~r/\bpropos\w*/i,
    ~r/\binvit\w*/i,
    ~r/\bpending\b/i,
    ~r/\bconsent\w*/i,
    ~r/\bone[- ]time\b/i,
    ~r/\bonce-off\b/i,
    ~r/\bmonthly equivalent\b/i,
    ~r/\bentr(y|ies)\b/i
  ]

  # REQ-154 AC-3: recommending forms (the page's own disclaimer set aside).
  @recommending ~r/\b(you should|should|we recommend|recommend\w*|suggest\w*|consider|advis\w+|ought|try to|aim for|make sure|better|best|ideal|enough|too (little|low|much|high)|on track|behind|ahead of)\b/i

  # REQ-154 AC-2: investments and products.
  @products ~r/\b(index fund|mutual fund|target[- ]date|annuit\w+|ETFs?|stocks?|bonds?|Roth|brokerage|CDs?|treasur\w+|crypto\w*|real estate|gold|Vanguard|Fidelity|Schwab)\b/i

  # --- setting up through the shared contexts ----------------------------------------------------------

  defp new_id, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  defp item(h, who, note, cents, frequency, on \\ nil) do
    {:ok, _} =
      Items.add_item(scope(h, who), %{
        note: note,
        amount: {:ok, cents},
        frequency: frequency,
        on: on
      })

    Items.visible(scope(h, who)) |> Enum.find(&(&1.attrs[:note] == note)) |> Map.fetch!(:id)
  end

  defp account(h, who, label, type, cents, on) do
    id = new_id()
    {:ok, _} = Balances.add_account(scope(h, who), id, label, type)

    {:ok, _} =
      Balances.add_reading(scope(h, who), id, %{
        balance: {:ok, cents, false},
        on: {:ok, on},
        rate: nil,
        min_payment: nil
      })

    id
  end

  defp value(h, who, label) do
    {:ok, _} = Values.add_value(scope(h, who), label)

    Items.visible(scope(h, who))
    |> Enum.find(&(Values.value?(&1) and Words.title(&1) == label))
    |> Map.fetch!(:id)
  end

  # Ana: checking, and a 401(k) with $10,000.00 on September 27.
  defp retirement_household(names \\ ~w(ana ben)) do
    h = household(names)
    account(h, "ana", "Checking", :checking, 100_000, "2026-09-27")
    k401 = account(h, "ana", "Work 401(k)", :retirement_401k, 1_000_000, "2026-09-27")
    {h, k401}
  end

  defp assumptions(k401, extra \\ %{}) do
    Map.merge(
      %{
        "birth_year" => "1961",
        "retire_age" => "67",
        "return" => "12",
        ("contribution_" <> k401) => "100",
        "ss" => "",
        "target" => ""
      },
      extra
    )
  end

  # Saves the assumptions through the page's form and returns the page it goes back to.
  defp save(h, k401, extra) do
    conn = act(h, "ana", "/act/retirement", assumptions(k401, extra))
    assert redirected_to(conn) == "/retirement"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Saved your retirement assumptions."
    body(h, "ana", "/retirement")
  end

  # --- reading pages ------------------------------------------------------------------------------------

  defp body(h, who, path) do
    conn = page(h, who, path)
    assert conn.status == 200
    conn.resp_body
  end

  # What a reader hears: the page's text, without markup.
  defp text(html) do
    html
    |> String.replace(~r/<(script|style)[^>]*>.*?<\/\1>/s, " ")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace(~r/\s+/, " ")
  end

  defp rows(html, table_id) do
    [tbody] =
      Regex.run(~r/id="#{table_id}".*?<tbody>(.*?)<\/tbody>/s, html, capture: :all_but_first)

    Regex.scan(~r/<tr[^>]*>(.*?)<\/tr>/s, tbody, capture: :all_but_first)
    |> Enum.map(&String.trim(text(hd(&1))))
  end

  # The assumption fields of the retirement form: {name, tag}.
  defp inputs(html) do
    [form] = Regex.run(~r/<form[^>]*action="\/act\/retirement".*?<\/form>/s, html)

    Regex.scan(~r/<input[^>]*>/, form)
    |> Enum.map(&hd/1)
    |> Enum.reject(&(&1 =~ ~s(type="hidden")))
    |> Enum.map(fn tag ->
      {hd(Regex.run(~r/name="([^"]*)"/, tag, capture: :all_but_first)), tag}
    end)
  end

  defp normalize(html) do
    html
    |> String.replace(~r/((?:id|aria-labelledby|aria-describedby)=")(?:alert-\d+|c-[^"]*)/, "\\1")
    |> String.replace(~r/(name="_csrf_token"[^>]*value=")[^"]*/, "\\1")
    |> String.replace(~r/(name="_form"[^>]*value=")[^"]*/, "\\1")
    |> String.replace(~r/("csrf-token" content=")[^"]*/, "\\1")
  end

  # The retirement page in every state REQ-154 AC-4 names, and a retirement account's own page.
  defp retirement_states do
    {h, k401} = retirement_household()
    empty = body(h, "ana", "/retirement")
    missing = save(h, k401, %{"retire_age" => "", "return" => ""})
    full = save(h, k401, %{"target" => "3,000", "ss" => "2,000"})
    beyond = save(h, k401, %{"target" => "2,010", "ss" => "2,000"})
    covered = save(h, k401, %{"target" => "2,000", "ss" => "2,500"})
    refused = act(h, "ana", "/act/retirement", assumptions(k401, %{"return" => "99"}))
    assert refused.status == 422
    account = body(h, "ana", "/items/" <> k401)
    none = body(h, "ben", "/retirement")

    [
      empty: empty,
      missing: missing,
      full: full,
      beyond: beyond,
      covered: covered,
      refused: refused.resp_body,
      account: account,
      none: none
    ]
  end

  # The visible text: the layout's connection notices are hidden until the connection drops, and are
  # about the connection, not the household (they are also hidden on every other page).
  defp visible(html),
    do:
      html
      |> String.replace(
        ~r/<div[^>]*id="(?:client|server)-error".*?until it(?:'|&#39;)s back\./s,
        " "
      )
      |> text()

  defp judgments(t), do: Regex.scan(@judgment, t) |> Enum.map(&hd/1)
  defp violations(t), do: for(re <- @banned, [found | _] <- Regex.scan(re, t), do: found)

  defp recommending(t),
    do:
      t
      |> String.replace("nothing here is advice or a suggestion", "")
      |> then(&Regex.scan(@recommending, &1))
      |> Enum.map(&hd/1)

  # --- REQ-146: goals -----------------------------------------------------------------------------------

  test "REQ-146 AC-5: no goal until the member sets one; the field starts empty; another member sees none" do
    h = household(~w(ana ben))
    sav = account(h, "ana", "Savings", :savings, 600_000, "2026-09-27")
    item(h, "ana", "Rent", -200_000, {:every, 1, :month})

    html = body(h, "ana", "/goals")
    assert text(html) =~ "About 3.0 months"
    refute html =~ "Your goal"
    refute html =~ "You&#39;re at"
    assert html =~ ~r/<input[^>]*id="fund-months"[^>]*value=""/

    conn = act(h, "ana", "/act/fund_goal", %{"months" => "5"})
    assert redirected_to(conn) == "/goals"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Saved the goal."

    assert text(body(h, "ana", "/goals")) =~
             "Your goal: 5 months of money out. You're at 3.0 of 5."

    assert Planning.goals(scope(h, "ana")).fund_months == 5

    # Ben sees the same savings, and no goal
    {:ok, _} = Items.propose_grant(scope(h, "ana"), sav, id(h, "ben"))
    assert Items.visible?(scope(h, "ben"), sav)
    theirs = body(h, "ben", "/goals")
    refute theirs =~ "Your goal"
    refute text(theirs) =~ "of 5"
    assert theirs =~ ~r/<input[^>]*id="fund-months"[^>]*value=""/
    assert Planning.goals(scope(h, "ben")).fund_months == nil
  end

  test "REQ-146 AC-6: the page offers no suggested number of months for the goal" do
    h = household(~w(ana))
    account(h, "ana", "Savings", :savings, 600_000, "2026-09-27")
    item(h, "ana", "Rent", -200_000, {:every, 1, :month})

    html = body(h, "ana", "/goals")
    [tag] = Regex.run(~r/<input[^>]*id="fund-months"[^>]*>/, html)
    assert tag =~ ~s(value="")
    refute tag =~ ~r/\b(placeholder|list)=/
    refute html =~ "<datalist"
    [card] = Regex.run(~r/id="cover".*?<\/form>.*?<\/p>/s, html)
    assert text(card) =~ "The goal is yours; nothing here suggests one."
    # the only figures about months are the member's own cover, worked out from their accounts
    assert Regex.scan(~r/\d+(?:\.\d)? months?/, text(card)) == [["3.0 months"]]
  end

  # --- REQ-150, REQ-151 -----------------------------------------------------------------------------

  test "REQ-150 AC-8: every assumption field starts empty, with nothing offered; no recommending phrase" do
    {h, _k401} = retirement_household()
    html = body(h, "ana", "/retirement")
    fields = inputs(html)

    assert fields
           |> Enum.map(&elem(&1, 0))
           |> Enum.reject(&(&1 =~ "contribution_"))
           |> Enum.sort() ==
             Enum.sort(~w(birth_year retire_age return ss target))

    assert Enum.any?(fields, fn {n, _} -> String.starts_with?(n, "contribution_") end)

    for {name, tag} <- fields do
      assert tag =~ ~s(value=""), "#{name} is filled in: #{tag}"
      refute tag =~ ~r/\b(placeholder|list)=/, "#{name} offers a value: #{tag}"
    end

    refute html =~ ~r/<(select|datalist|textarea)\b/
    assert recommending(visible(html)) == []
  end

  test "REQ-151 AC-5: today's dollars, and the assumptions stated next to the result" do
    {h, k401} = retirement_household()

    assert text(body(h, "ana", "/retirement")) =~
             "To see a projection, enter your birth year, a retirement age, and a yearly return below."

    html = save(h, k401, %{})
    page = text(html)
    assert page =~ "In January 2028, the year you turn 67:"

    assert page =~
             "Worked out in today's dollars from assumptions you set. Only you see them, and nothing here is advice or a suggestion."

    assert page =~
             "How this is worked out: starting from Work 401(k) ($10,000.00 as of Sunday, September 27); adding $100.00 a month as you entered; growing each month at 12% a year after inflation, the return you entered; until January of the year you turn 67. Everything is in today's dollars, and estimates are rounded to the nearest $100."

    # next to the result: in the same section, after the figure and the year-by-year table
    [card] = Regex.run(~r/id="result".*?id="worked-out"/s, html)
    assert card =~ ~s(id="at-retirement")
    assert card =~ "Year by year, 2 years"
    assert text(card) =~ "Enter a target income below to compare with it."

    for label <- ["Year", "Age", "Added", "Growth", "Balance at the end"],
        do: assert(html =~ ~r/<th[^>]*scope="col"[^>]*>\s*#{label}\s*<\/th>/)
  end

  # --- REQ-153 --------------------------------------------------------------------------------------

  test "REQ-153 AC-3: the alternatives are beside the result, in one table whose first row is as entered" do
    {h, k401} = retirement_household()
    html = save(h, k401, %{"target" => "3,000", "ss" => "2,000"})

    assert text(html) =~
             "The same projection with one assumption changed at a time. Nothing here is saved."

    assert length(Regex.scan(~r/aria-label="What changes the result"/, html)) == 2
    assert length(Regex.scan(~r/<table[^>]*id="alternatives"/, html)) == 1
    alts = Planning.retirement_sensitivity(scope(h, "ana"), today())
    rows = rows(html, "alternatives")
    assert length(rows) == length(alts)
    assert hd(rows) =~ ~r/^As you entered 12% 67 /

    for {r, row} <- Enum.zip(alts, rows) do
      assert row ==
               Enum.join(
                 [
                   GoalWords.change_label(r.change),
                   GoalWords.pct_text(r.return_bp),
                   r.retire_age,
                   GoalWords.about(r.at_retirement),
                   GoalWords.lasts_short(r)
                 ],
                 " "
               )
    end

    # the result as entered is the page's own result
    p = Planning.retirement_projection(scope(h, "ana"), today())
    assert hd(rows) =~ GoalWords.about(p.at_retirement)
    assert text(html) =~ GoalWords.lasts_sentence(p)

    for label <- ["If", "Return", "Retiring at", "At retirement", "Paying the difference"],
        do: assert(html =~ ~r/<th[^>]*scope="col"[^>]*>\s*#{label}\s*<\/th>/)
  end

  # --- REQ-154 --------------------------------------------------------------------------------------

  test "REQ-154 AC-1: no assumption field is prefilled or offers values, for every retirement account" do
    {h, _k401} = retirement_household()
    account(h, "ana", "My IRA", :ira, 50_000, "2026-09-27")

    for who <- ~w(ana ben) do
      html = body(h, who, "/retirement")

      for {name, tag} <- inputs(html) do
        assert tag =~ ~s(value=""), "#{name} is filled in: #{tag}"
        refute tag =~ ~r/\b(placeholder|list)=/, "#{name} offers a value: #{tag}"
      end

      refute html =~ ~r/<(select|datalist|textarea)\b/
    end

    assert length(for {"contribution_" <> _, _} <- inputs(body(h, "ana", "/retirement")), do: 1) ==
             2

    # every field has its label
    for {name, _} <- inputs(body(h, "ana", "/retirement")),
        do: assert(body(h, "ana", "/retirement") =~ ~r/<label[^>]*for="#{name}"/)
  end

  test "REQ-154 AC-2: no retirement page names an investment or a product" do
    for {state, html} <- retirement_states() do
      assert Regex.scan(@products, visible(html)) == [],
             "#{state}: names an investment or product"
    end
  end

  test "REQ-154 AC-3: no retirement page contains a recommending sentence" do
    for {state, html} <- retirement_states() do
      assert recommending(visible(html)) == [], "#{state}: a recommending phrase"
    end
  end

  test "REQ-154 AC-4: the judgment-word and glossary checks pass on every retirement page" do
    states = retirement_states()

    assert Keyword.keys(states) ==
             ~w(empty missing full beyond covered refused account none)a

    for {state, html} <- states do
      t = visible(html)
      assert judgments(t) == [], "#{state}: #{inspect(judgments(t))}"
      assert violations(t) == [], "#{state}: #{inspect(violations(t))}"
    end

    # the states are the ones named
    assert text(states[:missing]) =~ "To see a projection"
    assert text(states[:beyond]) =~ "some would remain at age 100"
    assert text(states[:covered]) =~ "is at least your target income"
    assert text(states[:account]) =~ "A retirement account: it isn't counted as cash."
    assert text(states[:none]) =~ "Contributions go with a retirement account."
  end

  # --- REQ-174 --------------------------------------------------------------------------------------

  test "REQ-174 AC-6: no result is scored or labelled, in any of the comparison's states" do
    {h, k401} = retirement_household()
    none = save(h, k401, %{})
    assert text(none) =~ "Enter a target income below to compare with it."
    lasts = save(h, k401, %{"target" => "3,000", "ss" => "2,000"})

    assert text(lasts) =~
             ~r/Paying the difference between your target income and Social Security, \$1,000\.00 a month, from these accounts would last \d+ years?( and \d+ months?)?, to about age \d+\./

    beyond = save(h, k401, %{"target" => "2,010", "ss" => "2,000"})

    assert text(beyond) =~
             "Paying the difference between your target income and Social Security, $10.00 a month, from these accounts, some would remain at age 100."

    refute text(beyond) =~ "would last"
    assert text(beyond) =~ "Some remains at 100"
    covered = save(h, k401, %{"target" => "2,000", "ss" => "2,500"})

    assert text(covered) =~
             "The Social Security estimate you entered is at least your target income, so there's no difference to pay from these accounts."

    for {state, html} <- [none: none, lasts: lasts, beyond: beyond, covered: covered] do
      t = visible(html)
      assert judgments(t) == [], "#{state}"
      assert violations(t) == [], "#{state}"
      assert recommending(t) == [], "#{state}"
    end
  end

  test "REQ-174 AC-7: every figure on the page is one the member set, one worked out from them, or an alternative" do
    {h, k401} = retirement_household()
    html = save(h, k401, %{"target" => "3,000", "ss" => "2,000"})

    sc = scope(h, "ana")
    s = Planning.retirement_settings(sc)
    p = Planning.retirement_projection(sc, today())
    alts = Planning.retirement_sensitivity(sc, today())

    plain = fn c -> c |> Money.format() |> String.replace_prefix("+", "") end
    round = fn c -> div(c + 5_000, 10_000) * 10_000 end
    about = fn c -> c |> round.() |> plain.() |> String.replace_suffix(".00", "") end
    about_signed = fn c -> c |> round.() |> Money.format() |> String.replace_suffix(".00", "") end

    set = [s.ss_monthly, s.target_monthly | Map.values(s.contributions)]

    worked =
      [p.start.balance, p.monthly_contribution, p.gap] ++
        for(id <- p.start.read, do: Balances.latest(sc, id).balance) ++
        Enum.map(p.rows, & &1.contributed)

    allowed =
      MapSet.new(
        Enum.map(set ++ worked, plain) ++
          Enum.map([p.at_retirement | Enum.map(p.rows, & &1.balance)], about) ++
          Enum.map(p.rows, &about_signed.(&1.growth)) ++
          Enum.map(alts, &about.(&1.at_retirement)) ++
          ["$100"]
      )

    t = text(html)
    amounts = Regex.scan(~r/[−+]?\$[\d,]+(?:\.\d\d)?/u, t) |> Enum.map(&hd/1)
    assert amounts != []
    for a <- amounts, do: assert(a in allowed, "#{a} isn't a figure the member set")

    rates = Regex.scan(~r/[−-]?\d+(?:\.\d+)?%/u, t) |> Enum.map(&hd/1) |> Enum.uniq()
    allowed_rates = alts |> Enum.map(&Words.rate_text(&1.return_bp)) |> Enum.uniq()
    assert Enum.sort(rates) == Enum.sort(allowed_rates)
  end

  # --- REQ-129 AC-6 -----------------------------------------------------------------------------------

  test "REQ-129 AC-6: the set-aside list shows how often beside each amount" do
    h = household(~w(ana))

    shown = [
      {"every_2_months", {:every, 2, :month}, "−$10.00 every two months"},
      {"every_3_months", {:every, 3, :month}, "−$10.00 every three months"},
      {"twice_a_year", {:every, 6, :month}, "−$10.00 twice a year"},
      {"yearly", {:every, 1, :year}, "−$10.00 a year"},
      {"irregular", :irregular, "−$10.00 a year, irregular"}
    ]

    for {value, frequency, _} <- shown, do: item(h, "ana", "Item " <> value, -1_000, frequency)
    item(h, "ana", "Item monthly", -1_000, {:every, 1, :month})

    next = body(h, "ana", "/next-60-days")

    for {value, _, words} <- shown,
        do: assert(text(next) =~ "Item #{value} : #{words},", value)

    refute text(next) =~ "Item monthly :"

    # the goals page's set-aside is from money in each month, and says so beside its amount
    shop = value(h, "ana", "Side business")
    sales = item(h, "ana", "Shop sales", 50_000, {:every, 1, :month})
    {:ok, _} = Values.link(scope(h, "ana"), sales, shop)
    {:ok, _} = Planning.set_aside(scope(h, "ana"), shop, 2_500)

    assert text(body(h, "ana", "/goals")) =~
             "25% of money in for Side business ($500.00 a month): set aside $125.00 a month"
  end

  # --- REQ-106 --------------------------------------------------------------------------------------

  test "REQ-106 AC-2: another member's private entries change neither the goals nor the retirement page" do
    h = household(~w(ana ben cy))
    account(h, "ben", "Ben savings", :savings, 300_000, "2026-09-27")
    k = account(h, "ben", "Ben 401(k)", :retirement_401k, 500_000, "2026-09-27")
    item(h, "ben", "Bus", -2_000, {:every, 1, :month})
    {:ok, _} = Planning.set_fund_goal(scope(h, "ben"), 4)

    {:ok, _} =
      Planning.save_retirement(scope(h, "ben"), %{
        birth_year: {:ok, 1980},
        retire_age: {:ok, 65},
        return_bp: {:ok, 500},
        ss_monthly: {:ok, nil},
        target_monthly: {:ok, 200_000},
        contributions: [{k, {:ok, 10_000}}]
      })

    pages = fn -> Map.new(~w(/goals /retirement), &{&1, normalize(body(h, "ben", &1))}) end
    before = pages.()
    assert text(before["/goals"]) =~ "Your goal: 4 months"
    assert text(before["/retirement"]) =~ "Ben 401(k) ($5,000.00 as of Sunday, September 27)"

    # everything Ana adds is hers alone, or shared with Cy only
    account(h, "ana", "Ana savings", :savings, 900_000, "2026-09-20")
    k401 = account(h, "ana", "Ana 401(k)", :retirement_401k, 2_000_000, "2026-09-20")
    rent = item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    pay = item(h, "ana", "Pay", 480_000, {:every, 2, :week}, "2026-10-02")
    biz = value(h, "ana", "Security")
    {:ok, _} = Values.link(scope(h, "ana"), pay, biz)
    {:ok, _} = Planning.set_aside(scope(h, "ana"), biz, 2_000)
    {:ok, _} = Planning.set_fund_goal(scope(h, "ana"), 6)
    {:ok, _} = Planning.new_plan(scope(h, "ana"), new_id(), "Ana's plan")
    {:ok, _} = Items.propose_grant(scope(h, "ana"), rent, id(h, "cy"))
    {:ok, _} = Items.propose_grant(scope(h, "ana"), k401, id(h, "cy"))

    assert act(h, "ana", "/act/retirement", assumptions(k401)) |> redirected_to() ==
             "/retirement"

    assert pages.() == before
  end

  # --- the forms: success and refusal ----------------------------------------------------------------

  test "the goal is saved and cleared, and a goal out of range is refused on the goals page" do
    h = household(~w(ana))
    account(h, "ana", "Savings", :savings, 600_000, "2026-09-27")
    item(h, "ana", "Rent", -200_000, {:every, 1, :month})

    assert redirected_to(act(h, "ana", "/act/fund_goal", %{"months" => "3"})) == "/goals"
    assert body(h, "ana", "/goals") =~ ~r/<input[^>]*id="fund-months"[^>]*value="3"/

    conn = act(h, "ana", "/act/fund_goal", %{"months" => "99"})
    assert conn.status == 422
    assert text(conn.resp_body) =~ "Enter a number of months from 1 to 60"
    assert text(conn.resp_body) =~ "How long savings would last"
    assert Planning.goals(scope(h, "ana")).fund_months == 3

    conn = act(h, "ana", "/act/fund_goal", %{"months" => "three"})
    assert conn.status == 422

    conn = act(h, "ana", "/act/fund_goal", %{"months" => " "})
    assert redirected_to(conn) == "/goals"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Cleared the goal."
    assert Planning.goals(scope(h, "ana")).fund_months == nil

    html = body(h, "ana", "/goals")
    assert html =~ ~r/<label[^>]*for="fund-months"/
    assert html =~ ~r/<h1[^>]*>\s*Goals\s*<\/h1>/
    assert length(Regex.scan(~r/<h2/, html)) >= 2
  end

  test "a set-aside rate is saved and removed; a rate out of range or for a value the member can't see is refused" do
    h = household(~w(ana ben))

    assert text(body(h, "ana", "/goals")) =~
             "Add a value, and link income to it, to set a rate here."

    shop = value(h, "ana", "Side business")
    sales = item(h, "ana", "Shop sales", 50_000, {:every, 1, :month})
    {:ok, _} = Values.link(scope(h, "ana"), sales, shop)

    html = body(h, "ana", "/goals")
    assert html =~ ~r/<label[^>]*for="aside-value"/
    assert html =~ ~r/<label[^>]*for="aside-rate"/

    conn = act(h, "ana", "/act/set_aside", %{"value" => shop, "rate" => "25"})
    assert redirected_to(conn) == "/goals"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Saved the rate."
    html = body(h, "ana", "/goals")
    assert text(html) =~ "set aside $125.00 a month"
    assert html =~ ~s(aria-label="Remove the set-aside for Side business")

    conn = act(h, "ana", "/act/set_aside", %{"value" => shop, "rate" => "250"})
    assert conn.status == 422
    assert text(conn.resp_body) =~ "Setting aside from income"
    assert text(body(h, "ana", "/goals")) =~ "set aside $125.00 a month"

    # Ben can't see Ana's value
    conn = act(h, "ben", "/act/set_aside", %{"value" => shop, "rate" => "10"})
    assert conn.status == 422
    assert conn.resp_body =~ ~s(role="alert")

    conn = act(h, "ana", "/act/set_aside", %{"value" => shop, "rate" => ""})
    assert redirected_to(conn) == "/goals"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Removed the set-aside."
    refute text(body(h, "ana", "/goals")) =~ "set aside $125.00"
  end

  test "the assumptions are saved together and cleared; a mistake is refused at its field with what was typed kept" do
    {h, k401} = retirement_household()

    conn = act(h, "ana", "/act/retirement", assumptions(k401))
    assert redirected_to(conn) == "/retirement"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Saved your retirement assumptions."
    s = Planning.retirement_settings(scope(h, "ana"))
    assert s.return_bp == 1200 and s.contributions == %{k401 => 10_000}

    # what was saved is shown in its field
    fields = Map.new(inputs(body(h, "ana", "/retirement")))
    assert fields["birth_year"] =~ ~s(value="1961")
    assert fields["return"] =~ ~s(value="12")
    assert fields["contribution_" <> k401] =~ ~s(value="100.00")

    # Ben's page doesn't show them
    refute body(h, "ben", "/retirement") =~ "1961"

    conn =
      act(
        h,
        "ana",
        "/act/retirement",
        assumptions(k401, %{
          "return" => "20",
          "retire_age" => "sixty",
          "target" => "5,00",
          ("contribution_" <> k401) => "abc",
          "birth_year" => "1970"
        })
      )

    assert conn.status == 422
    html = conn.resp_body
    assert text(html) =~ "Nothing was saved. Check the fields marked in your assumptions."
    assert html =~ ~s(href="#assumptions")
    assert text(html) =~ "Nothing was saved. Check the fields marked below."
    assert text(html) =~ "Enter a yearly return from −5 to 15, like 5 or 4.5."
    assert text(html) =~ "Enter an age from 40 to 90."

    fields = Map.new(inputs(html))

    for {name, typed} <- [
          {"retire_age", "sixty"},
          {"return", "20"},
          {"target", "5,00"},
          {"contribution_" <> k401, "abc"}
        ] do
      assert fields[name] =~ ~s(value="#{typed}"), name
      assert fields[name] =~ ~s(aria-invalid="true"), name
      assert fields[name] =~ ~s(aria-describedby="#{name}-error"), name
      assert html =~ ~s(id="#{name}-error")
    end

    # the valid field is kept as typed, and nothing was saved
    assert fields["birth_year"] =~ ~s(value="1970")
    refute fields["birth_year"] =~ "aria-invalid"
    assert Planning.retirement_settings(scope(h, "ana")).birth_year == 1961

    # an empty field clears that assumption
    act(h, "ana", "/act/retirement", assumptions(k401, %{"return" => ""}))
    assert Planning.retirement_settings(scope(h, "ana")).return_bp == nil

    html = body(h, "ana", "/retirement")
    assert html =~ ~r/<h1[^>]*>\s*Retirement\s*<\/h1>/
    assert html =~ ~r/<h2[^>]*>\s*Your assumptions\s*<\/h2>/
  end
end
