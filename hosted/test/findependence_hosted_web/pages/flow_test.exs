defmodule FindependenceHostedWeb.Pages.FlowTest do
  @moduledoc """
  WI-075: the next sixty days, the next twelve months, and adding an account or a debt say what the local
  form's pages say (REQ-106, REQ-161, REQ-162, REQ-173).
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceShared.{Balances, Items, Planning, Values}

  # --- setting up through the shared contexts ----------------------------------------------------------

  defp new_id, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  defp item(h, who, note, cents, frequency, on) do
    {:ok, _} =
      Items.add_item(scope(h, who), %{
        note: note,
        amount: {:ok, cents},
        frequency: frequency,
        on: on
      })

    Items.visible(scope(h, who)) |> Enum.find(&(&1.attrs[:note] == note)) |> Map.fetch!(:id)
  end

  defp account(h, who, label, cents, on) do
    id = new_id()
    {:ok, _} = Balances.add_account(scope(h, who), id, label, :checking)
    reading(h, who, id, %{balance: {:ok, abs(cents), cents < 0}, on: {:ok, on}})
    id
  end

  defp reading(h, who, id, input) do
    input = Map.merge(%{rate: nil, min_payment: nil}, input)
    {:ok, _} = Balances.add_reading(scope(h, who), id, input)
  end

  defp debt(h, who, label, cents, on) do
    id = new_id()
    {:ok, _} = Balances.add_debt(scope(h, who), id, label, :card)

    reading(h, who, id, %{
      balance: {:ok, cents, false},
      on: {:ok, on},
      rate: {:ok, 2199},
      min_payment: {:ok, 3_000}
    })

    id
  end

  # Ana and Ben both own the account: Ana proposes it, and Ben agrees if it waits for him.
  defp share_ownership(h, id) do
    {:ok, _} = Items.propose_owners(scope(h, "ana"), id, [id(h, "ana"), id(h, "ben")])

    for p <- Items.pending(scope(h, "ben")), p.item_id == id, id(h, "ben") not in p.consents do
      {:ok, _} = Items.consent(scope(h, "ben"), p.id)
    end

    assert id(h, "ben") in Items.lookup(scope(h, "ana"), id).owners
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

  # The rows of a table (its <tbody>), each as its text.
  defp rows(html, table_id) do
    [tbody] =
      Regex.run(~r/id="#{table_id}".*?<tbody>(.*?)<\/tbody>/s, html, capture: :all_but_first)

    Regex.scan(~r/<tr[^>]*>(.*?)<\/tr>/s, tbody, capture: :all_but_first)
    |> Enum.map(&text(hd(&1)))
  end

  defp row_dates(html, table_id) do
    [tbody] =
      Regex.run(~r/id="#{table_id}".*?<tbody>(.*?)<\/tbody>/s, html, capture: :all_but_first)

    Regex.scan(~r/<th[^>]*scope="row"[^>]*>(.*?)<\/th>/s, tbody, capture: :all_but_first)
    |> Enum.map(&String.trim(text(hd(&1))))
  end

  # The per-request tokens are the only part of a page that may differ between two visits. The layout's
  # connection notices (Petal alerts) also get fresh element ids on each request: set aside here, as they
  # carry nothing about the household.
  defp normalize(html) do
    html
    |> String.replace(~r/((?:id|aria-labelledby|aria-describedby)=")(?:alert-\d+|c-[^"]*)/, "\\1")
    |> String.replace(~r/(name="_csrf_token"[^>]*value=")[^"]*/, "\\1")
    |> String.replace(~r/(name="_form"[^>]*value=")[^"]*/, "\\1")
    |> String.replace(~r/("csrf-token" content=")[^"]*/, "\\1")
  end

  @pages ["/next-60-days", "/ahead", "/balances/new"]

  defp pages(h, who), do: Map.new(@pages, &{&1, normalize(body(h, who, &1))})

  # --- REQ-106 ------------------------------------------------------------------------------------------

  test "REQ-106 AC-2: another member's private entries change none of the next-60-days, next-12-months, and new-balance pages" do
    h = household(~w(ana ben cy))
    item(h, "ben", "Bus", -2_000, {:every, 1, :month}, "2026-10-05")
    bens = account(h, "ben", "Ben checking", 80_000, "2026-09-27")
    before = pages(h, "ben")
    assert text(before["/next-60-days"]) =~ "Starting from Ben checking: $800.00"
    assert text(before["/ahead"]) =~ "Cash starts from Ben checking: $800.00."

    # everything Ana adds is hers alone, or shared with Cy only
    item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    pay = item(h, "ana", "Pay", 480_000, {:every, 2, :week}, "2026-10-02")
    item(h, "ana", "Car insurance", -114_000, {:every, 6, :month}, "2027-01-15")
    {:ok, _} = Values.add_value(scope(h, "ana"), "Security")
    chk = account(h, "ana", "Ana checking", 350_000, "2026-09-20")
    debt(h, "ana", "Ana visa", 90_000, "2026-09-20")
    {:ok, _} = Balances.attach(scope(h, "ana"), pay, chk)
    {:ok, _} = Planning.new_plan(scope(h, "ana"), new_id(), "Ana's plan")
    {:ok, _} = Items.propose_grant(scope(h, "ana"), pay, id(h, "cy"))

    assert pages(h, "ben") == before
    assert Items.visible?(scope(h, "ben"), bens)
  end

  # --- REQ-161 on the next 60 days --------------------------------------------------------------------

  test "REQ-161 AC-8: the page says which accounts and which date the balance starts from" do
    h = household(~w(ana ben))
    item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    account(h, "ana", "Checking", 50_000, "2026-09-27")
    account(h, "ana", "Second checking", 10_000, "2026-09-20")

    page = text(body(h, "ana", "/next-60-days"))

    assert page =~
             "Starting from Checking and Second checking: $600.00 as of Sunday, September 27."

    assert page =~
             "Counts items you own, and items shared with you that you've said go through these accounts; anything others keep private isn't included."
  end

  test "REQ-161 AC-9: for an account others also own, the page names them and says their items may not be counted" do
    h = household(~w(ana ben))
    item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    chk = account(h, "ana", "Joint checking", 500_000, "2026-09-27")
    share_ownership(h, chk)

    html = body(h, "ana", "/next-60-days")

    assert text(html) =~
             "Ben also owns Joint checking, so this is your part: items Ben owns count only once they're shared with you and you say they go through it."

    # the figure is labelled as her part, and Ben is named, never by his membership id
    assert html =~ ~r/<th[^>]*scope="col"[^>]*>\s*Your part after\s*<\/th>/
    refute html =~ "Balance after"
    refute html =~ id(h, "ben")

    # Ben's view names Ana the same way
    item(h, "ben", "Bus", -2_000, {:every, 1, :month}, "2026-10-05")

    assert text(body(h, "ben", "/next-60-days")) =~
             "Ana also owns Joint checking, so this is your part: items Ana owns count only once"

    # an account only the member owns keeps the general note
    h2 = household(~w(cy))
    item(h2, "cy", "Rent", -500, {:every, 1, :month}, "2026-10-01")
    account(h2, "cy", "Checking", 1_000, "2026-09-26")
    own = body(h2, "cy", "/next-60-days")

    assert text(own) =~
             "Counts items you own, and items shared with you that you've said go through"

    assert own =~ ~r/<th[^>]*scope="col"[^>]*>\s*Balance after\s*<\/th>/
    refute own =~ "Your part"
  end

  # --- REQ-162: the next 12 months ------------------------------------------------------------------------

  test "REQ-162 AC-7: the page states its assumptions next to the results, and they match what is counted" do
    h = household(~w(ana ben))
    chk = account(h, "ana", "Checking", 700_000, "2026-09-27")
    item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    debt(h, "ana", "Visa", 90_000, "2026-09-27")
    # Ben's paycheck, shared with Ana, counts once she says it goes through her checking
    pay = item(h, "ben", "Paycheck", 198_000, {:every, 1, :month}, "2026-10-15")
    {:ok, _} = Items.propose_grant(scope(h, "ben"), pay, id(h, "ana"))
    {:ok, _} = Balances.attach(scope(h, "ana"), pay, chk)

    html = body(h, "ana", "/ahead")
    page = text(html)

    assert page =~
             "How this is worked out: repeating items count at their per-month amount; one-off items count in their month when they have a date; cash starts from the latest balances of the accounts you can see; each debt grows by a month's interest and falls by its minimum payment. It counts items you own, and items shared with you that you've said go through your accounts, and nothing is advice."

    refute page =~ "It counts only items you own"
    assert page =~ "Cash starts from Checking: $7,000.00."

    # next to the results: in the same section as the months, after them
    [card] = Regex.run(~r/id="months".*?id="assumptions"/s, html)
    assert card =~ "October 2026"

    # what it says is counted is what is counted: Ana's rent and Ben's shared paycheck, from October
    [october | _] = rows(html, "months")
    assert october =~ "October 2026"
    assert october =~ "+$1,980.00"
    assert october =~ "−$2,150.00"
    assert List.last(rows(html, "months")) =~ "September 2027"

    # and the debts, as stated: a month's interest on, the minimum payment off
    assert page =~ "Debts over the next 12 months"
    assert page =~ "Paying each debt's minimum payment, at its latest rate."
    [visa] = rows(html, "debts")
    assert visa =~ "Visa" and visa =~ "$900.00"
  end

  test "REQ-162 AC-8: for an account others also own, the page names them and says their items may not be counted" do
    h = household(~w(ana ben))
    chk = account(h, "ana", "Joint checking", 500_000, "2026-09-27")
    item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    share_ownership(h, chk)

    html = body(h, "ana", "/ahead")

    assert text(html) =~
             "Ben also owns Joint checking, so this is your part: items Ben owns count only once they're shared with you and you say they go through it."

    assert html =~ ~r/<th[^>]*scope="col"[^>]*>\s*Your part at the end\s*<\/th>/
    refute html =~ "Cash at the end"
    refute html =~ id(h, "ben")

    h2 = household(~w(cy))
    account(h2, "cy", "Checking", 1_000, "2026-09-26")
    own = body(h2, "cy", "/ahead")
    assert own =~ ~r/<th[^>]*scope="col"[^>]*>\s*Cash at the end\s*<\/th>/
    refute own =~ "Your part"
  end

  # --- REQ-173: the next sixty days -------------------------------------------------------------------

  test "REQ-173 AC-1: the page covers today to today + 59; something dated today + 60 is not shown" do
    h = household(~w(ana))
    item(h, "ana", "Today", -100, :one_off, Date.to_iso8601(today()))
    item(h, "ana", "Last day", -1_000, :one_off, Date.to_iso8601(Date.add(today(), 59)))
    item(h, "ana", "Day after", -1_000, :one_off, Date.to_iso8601(Date.add(today(), 60)))

    html = body(h, "ana", "/next-60-days")
    assert row_dates(html, "flow") == ["Tuesday, September 29", "Friday, November 27"]
    assert html =~ "Last day"
    refute html =~ "Day after"
    assert text(html) =~ "What's dated, day by day, from Tuesday, September 29."
  end

  test "REQ-173 AC-2: the days are in date order, each with what is dated on it and the balance after it" do
    h = household(~w(ana))
    item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    item(h, "ana", "Paycheck", 198_000, {:every, 2, :week}, "2026-10-09")
    item(h, "ana", "Phone", -5_000, {:every, 1, :month}, "2026-10-09")
    account(h, "ana", "Checking", 100_000, "2026-09-27")

    html = body(h, "ana", "/next-60-days")
    dates = row_dates(html, "flow")

    assert Enum.take(dates, 3) == [
             "Thursday, October 1",
             "Friday, October 9",
             "Friday, October 23"
           ]

    [oct1, oct9 | _] = rows(html, "flow")
    # 1,000 - 2,150 = -1,150; then + 1,980 - 50 = 780
    assert oct1 =~ "Rent −$2,150.00"
    assert oct1 =~ "−$1,150.00 Below zero"
    assert oct9 =~ "Paycheck +$1,980.00" and oct9 =~ "Phone −$50.00"
    assert oct9 =~ "+$1,930.00"
    assert oct9 =~ "$780.00"
    assert html =~ ~s(href="/items/)

    # headers name each column, for each row
    for label <- ["Date", "What", "Net", "Balance after"],
        do: assert(html =~ ~r/<th[^>]*scope="col"[^>]*>\s*#{label}\s*<\/th>/)
  end

  test "REQ-173 AC-4: each day below zero is marked, including days with nothing dated and the sixtieth day" do
    h = household(~w(ana))
    item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    item(h, "ana", "Paycheck", 198_000, {:every, 2, :week}, "2026-10-09")
    account(h, "ana", "Checking", 100_000, "2026-09-27")

    page = text(body(h, "ana", "/next-60-days"))
    # below zero from the rent until the paycheck, the days between with nothing dated included
    assert page =~ "Below zero: Thursday, October 1 to Thursday, October 8"
    assert page =~ "−$1,150.00 Below zero"

    # the sixtieth day
    h2 = household(~w(cy))
    item(h2, "cy", "Last day", -1_000, :one_off, Date.to_iso8601(Date.add(today(), 59)))
    account(h2, "cy", "Checking", 500, "2026-09-27")
    last = text(body(h2, "cy", "/next-60-days"))
    assert last =~ "Below zero: Friday, November 27."
    assert last =~ "−$5.00 Below zero"
  end

  test "REQ-173 AC-5: no other label or judgment is attached" do
    h = household(~w(ana))
    item(h, "ana", "Rent", -215_000, {:every, 1, :month}, "2026-10-01")
    item(h, "ana", "Paycheck", 198_000, {:every, 2, :week}, "2026-10-09")
    item(h, "ana", "Car insurance", -114_000, {:every, 6, :month}, "2027-01-15")
    account(h, "ana", "Checking", 100_000, "2026-09-27")

    html = body(h, "ana", "/next-60-days")
    page = text(html)

    judgment =
      ~r/\b(good|bad|risky?|healthy|unhealthy|on track|off track|over budget|under budget|warning|danger(ous)?|too much|too little|you can afford|can.t afford|shortfall|overdrawn|alert)\b/i

    assert Regex.scan(judgment, page) == []

    # the rows carry the figures and, below zero, only the mark
    for row <- rows(html, "flow") do
      labels =
        row
        |> String.replace(~r/[+−]?\$[\d,]+\.\d\d/u, "")
        |> String.replace(~r/[A-Z][a-z]+day, [A-Z][a-z]+ \d+/, "")
        |> String.split()

      assert labels -- ~w(Rent Paycheck Below zero) == []
    end

    assert page =~ "Setting aside $190.00 a month covers these:"
    assert page =~ "Car insurance : −$1,140.00 twice a year, $190.00 a month"
  end

  # --- adding an account or a debt (the local form's add_balance) ----------------------------------------

  test "adding an account goes to its page with the outcome; a mistake keeps what was typed, at the field" do
    h = household(~w(ana))
    new = body(h, "ana", "/balances/new")
    assert new =~ ~r/<label[^>]*for="account-label"/
    assert new =~ ~r/<label[^>]*for="debt-type"/

    conn = act(h, "ana", "/act/add_account", %{"label" => "Checking", "type" => "checking"})
    assert "/items/" <> id = redirected_to(conn)

    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Added “Checking”. Add its balance below."

    assert Items.lookup(scope(h, "ana"), id).attrs.label == "Checking"

    conn = act(h, "ana", "/act/add_debt", %{"label" => "Visa card", "type" => ""})
    assert conn.status == 422
    assert conn.resp_body =~ ~s(value="Visa card")
    assert conn.resp_body =~ ~s(id="debt-type-error")
    assert conn.resp_body =~ "Choose what kind it is."
    assert conn.resp_body =~ ~s(aria-describedby="debt-type-error")

    conn = act(h, "ana", "/act/add_account", %{"label" => " ", "type" => "savings"})
    assert conn.status == 422
    assert conn.resp_body =~ ~s(id="account-label-error")
    assert conn.resp_body =~ ~r/<option selected value="savings"|<option value="savings" selected/
  end
end
