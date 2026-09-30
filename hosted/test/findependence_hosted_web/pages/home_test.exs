defmodule FindependenceHostedWeb.Pages.HomeTest do
  @moduledoc """
  WI-075: the hosted household page says what the local form's home says. One test per criterion, each
  asserting it on the hosted page (the local form's asserting tests are cited in VV-002).
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceShared.{Balances, Decode, Items, Money, Planning, Values}

  # --- helpers

  defp ok({:ok, saved}), do: saved

  defp add(h, who, note, cents, frequency, on \\ nil) do
    ok(
      Items.add_item(scope(h, who), %{
        note: note,
        amount: {:ok, cents},
        frequency: frequency,
        on: on
      })
    )
  end

  defp item_id(h, who, note) do
    scope(h, who) |> Items.visible() |> Enum.find(&(&1.attrs[:note] == note)) |> Map.fetch!(:id)
  end

  defp uid(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp home(h, who) do
    conn = page(h, who, "/")
    assert conn.status == 200
    conn.resp_body
  end

  defp doc(html), do: LazyHTML.from_document(html)

  defp texts(lazy), do: Enum.map(lazy, &(LazyHTML.text(&1) |> squish()))

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  # the dates of Coming up's rows
  defp coming_up_dates(html),
    do: html |> doc() |> LazyHTML.query("#coming-up tbody tr td:first-child") |> texts()

  defp coming_up_text(html),
    do: html |> doc() |> LazyHTML.query("#coming-up") |> LazyHTML.text() |> squish()

  defp one_offs(h, dates) do
    for {d, n} <- Enum.with_index(dates), do: add(h, "ana", "Thing #{n}", -1_000, :one_off, d)
    h
  end

  # per-request form tokens (the one-time `_form` token and the CSRF token) are the only allowed difference
  defp without_tokens(html) do
    html
    |> String.replace(~r/(name="(?:_form|_csrf_token)"[^>]*?value=")[^"]*"/, "\\1\"")
    |> String.replace(~r/(value=")[^"]*("[^>]*?name="(?:_form|_csrf_token)")/, "\\1\\2")
    |> String.replace(~r/(<meta[^>]*name="csrf-token"[^>]*content=")[^"]*"/, "\\1\"")
    |> String.replace(~r/(<meta[^>]*content=")[^"]*("[^>]*name="csrf-token")/, "\\1\\2")
    # the ids Petal's alerts generate for each render (in the layout's connection notices)
    |> String.replace(~r/"alert-\d+"/, "\"alert\"")
    |> String.replace(~r/"(c-[a-z0-9-]+?)-[0-9A-Z]{3}"/, "\"\\1\"")
  end

  defp reading(balance, on, extra \\ %{}) do
    Map.merge(%{balance: Decode.balance(balance), on: Decode.date(on)}, extra)
  end

  # --- REQ-106

  test "REQ-106 AC-2: home is identical, apart from form tokens, whether or not other members hold entries invisible to the member" do
    h = household(~w(ana ben cy))
    add(h, "ben", "Bus", -2_000, {:every, 1, :month})
    ok(Values.add_value(scope(h, "ben"), "Getting around"))

    before = home(h, "ben")
    assert before =~ "Bus" and before =~ "Getting around"

    add(h, "ana", "Rent", -215_000, {:every, 1, :month})
    add(h, "ana", "Pay", 480_000, {:every, 2, :week}, "2026-10-02")
    ok(Values.add_value(scope(h, "ana"), "Security"))

    value =
      scope(h, "ana") |> Items.visible() |> Enum.find(&(&1.attrs[:label] == "Security"))

    ok(Values.link(scope(h, "ana"), item_id(h, "ana", "Rent"), value.id))

    chk = uid("chk")
    ok(Balances.add_account(scope(h, "ana"), chk, "Ana checking", :checking))
    ok(Balances.add_reading(scope(h, "ana"), chk, reading("3,500", "2026-09-20")))

    visa = uid("visa")
    ok(Balances.add_debt(scope(h, "ana"), visa, "Ana visa", :card))

    ok(
      Balances.add_reading(
        scope(h, "ana"),
        visa,
        reading("900", "2026-09-20", %{
          rate: Decode.rate("21.99"),
          min_payment: Money.parse("30", "in")
        })
      )
    )

    ok(Planning.new_plan(scope(h, "ana"), uid("plan"), "Ana's plan"))
    ok(Items.propose_grant(scope(h, "ana"), item_id(h, "ana", "Pay"), id(h, "cy")))

    assert without_tokens(home(h, "ben")) == without_tokens(before)
  end

  # --- REQ-129

  @nine [
    {"monthly", "Every month"},
    {"biweekly", "Every two weeks"},
    {"weekly", "Every week"},
    {"every_2_months", "Every two months"},
    {"every_3_months", "Every three months"},
    {"twice_a_year", "Twice a year"},
    {"yearly", "Every year"},
    {"irregular", "Irregular (enter the total for a year)"},
    {"one_off", "One-off"}
  ]

  test "REQ-129 AC-1: adding an item offers exactly the nine choices of how often, irregular saying the amount is the total for a year" do
    h = household(~w(ana))
    options = home(h, "ana") |> doc() |> LazyHTML.query("#add-item select#frequency option")

    offered =
      Enum.map(options, fn o ->
        {o |> LazyHTML.attribute("value") |> hd(), squish(LazyHTML.text(o))}
      end)

    assert [{"", "Choose…"} | nine] = offered
    assert Enum.sort(nine) == Enum.sort(@nine)
    assert Enum.sort(Enum.map(nine, &elem(&1, 0))) == Enum.sort(Map.keys(Decode.frequencies()))
    # the System doesn't choose (REQ-129 AC-2): nothing is preselected
    assert options |> LazyHTML.filter("[selected]") |> Enum.count() == 0
  end

  test "REQ-129 AC-6: on the home list, how often an item happens is shown beside its amount" do
    h = household(~w(ana))

    conn =
      act(h, "ana", "/act/add_item", %{
        "note" => "Bus pass",
        "amount" => "32.50",
        "direction" => "out",
        "frequency" => "weekly",
        "on" => ""
      })

    assert conn.status == 302

    rows =
      home(h, "ana")
      |> doc()
      |> LazyHTML.query(~s(table[aria-label="Your items"], [aria-label="Your items"] table))
      |> LazyHTML.query("tbody tr")

    assert [row] = Enum.to_list(rows)
    cells = row |> LazyHTML.query("td") |> texts()
    assert ["Bus pass", "−$32.50", "a week" | _] = cells

    headers =
      home(h, "ana")
      |> doc()
      |> LazyHTML.query(~s([aria-label="Your items"] th[scope="col"]))
      |> texts()

    assert headers == ["Item", "Amount", "How often", "Owned by", "Who else can see it"]
  end

  # --- REQ-136

  test "REQ-136 AC-2: the add-item form offers exactly one date field, and it is optional" do
    h = household(~w(ana))
    form = home(h, "ana") |> doc() |> LazyHTML.query("form#add-item")

    dates = LazyHTML.query(form, ~s([name="on"]))
    assert Enum.count(dates) == 1
    assert LazyHTML.attribute(dates, "type") == ["date"]
    assert LazyHTML.attribute(dates, "required") == []
    assert LazyHTML.query(form, ~s(input[type="date"])) |> Enum.count() == 1

    # an item can be added without a date
    conn =
      act(h, "ana", "/act/add_item", %{
        "note" => "Groceries",
        "amount" => "120",
        "direction" => "out",
        "frequency" => "weekly"
      })

    assert conn.status == 302
    assert home(h, "ana") =~ "Groceries"
  end

  # --- REQ-161 (today is 2026-09-29)

  test "REQ-161 AC-1: Coming up covers today to today + 13; something dated today + 14 isn't shown" do
    h = household(~w(ana)) |> one_offs(~w(2026-10-12 2026-10-13))
    html = home(h, "ana")
    assert coming_up_dates(html) == ["Monday, October 12"]
    refute coming_up_text(html) =~ "more day"

    h2 = household(~w(ana)) |> one_offs(~w(2026-09-29))
    assert coming_up_dates(home(h2, "ana")) == ["Tuesday, September 29"]
  end

  test "REQ-161 AC-2: Coming up shows at most the first four days that have something on them, in date order" do
    h =
      one_offs(
        household(~w(ana)),
        ~w(2026-10-08 2026-09-30 2026-10-04 2026-10-01 2026-10-06 2026-10-02)
      )

    assert coming_up_dates(home(h, "ana")) == [
             "Wednesday, September 30",
             "Thursday, October 1",
             "Friday, October 2",
             "Sunday, October 4"
           ]
  end

  test "REQ-161 AC-3: when more such days follow in the fourteen, Coming up says how many; with four or fewer, nothing more" do
    two_more =
      household(~w(ana))
      |> one_offs(~w(2026-09-30 2026-10-01 2026-10-02 2026-10-04 2026-10-06 2026-10-08))

    assert coming_up_text(home(two_more, "ana")) =~
             "And 2 more days with something on them in the next 14."

    one_more =
      household(~w(ana)) |> one_offs(~w(2026-09-30 2026-10-01 2026-10-02 2026-10-04 2026-10-06))

    assert coming_up_text(home(one_more, "ana")) =~
             "And 1 more day with something on them in the next 14."

    four = household(~w(ana)) |> one_offs(~w(2026-09-30 2026-10-01 2026-10-02 2026-10-04))
    html = home(four, "ana")
    assert length(coming_up_dates(html)) == 4
    refute coming_up_text(html) =~ "more day"
  end

  test "REQ-161 AC-4: Coming up links to the full view (the next 60 days)" do
    h = household(~w(ana)) |> one_offs(~w(2026-09-30))

    links =
      home(h, "ana") |> doc() |> LazyHTML.query(~s(#coming-up a[href="/next-60-days"])) |> texts()

    assert links == ["The next 60 days"]
  end

  # --- REQ-172

  defp with_balances(h) do
    chk = uid("chk")
    ok(Balances.add_account(scope(h, "ana"), chk, "Checking", :checking))
    ok(Balances.add_reading(scope(h, "ana"), chk, reading("990", "2026-09-26")))

    visa = uid("visa")
    ok(Balances.add_debt(scope(h, "ana"), visa, "Visa", :card))

    ok(
      Balances.add_reading(
        scope(h, "ana"),
        visa,
        reading("5,200", "2026-09-25", %{
          rate: Decode.rate("21.99"),
          min_payment: Money.parse("150", "in")
        })
      )
    )

    {chk, visa}
  end

  test "REQ-172 AC-6: home lists accounts and debts compactly, one row each (name, balance, owners, kind and as-of date), each name linking to its page" do
    h = household(~w(ana ben))
    {chk, visa} = with_balances(h)

    table = home(h, "ana") |> doc() |> LazyHTML.query(~s([aria-label="Balances and debts"] table))

    assert table |> LazyHTML.query(~s(th[scope="col"])) |> texts() ==
             ["Account or debt", "Balance", "Owned by", "Kind and date"]

    rows = table |> LazyHTML.query("tbody tr") |> Enum.map(&(LazyHTML.query(&1, "td") |> texts()))

    assert rows == [
             ["Checking", "$990.00", "you", "Checking account, as of Saturday, September 26"],
             ["Visa", "$5,200.00 owed", "you", "Credit card, as of Friday, September 25"]
           ]

    links = table |> LazyHTML.query("tbody a") |> LazyHTML.attribute("href")
    assert links == ["/items/#{chk}", "/items/#{visa}"]
    # no controls in the rows
    assert table |> LazyHTML.query("form, button, input") |> Enum.count() == 0
  end

  test "REQ-172 AC-7: home has no account or debt forms (adding an account, adding a debt, or updating a balance)" do
    h = household(~w(ana))
    with_balances(h)
    html = home(h, "ana")

    actions = html |> doc() |> LazyHTML.query("form") |> LazyHTML.attribute("action")

    for action <- ~w(/act/add_account /act/add_debt /act/add_reading),
        do: refute(action in actions)

    assert html |> doc() |> LazyHTML.query(~s(a[href="/balances/new"])) |> Enum.count() >= 1
  end

  # --- the add-item route (as the local form's router)

  test "adding an item: a field mistake shows home again with what was typed and the error at the field; success says so" do
    h = household(~w(ana))

    conn =
      act(h, "ana", "/act/add_item", %{
        "note" => "Rent",
        "amount" => "12.345",
        "direction" => "in",
        "frequency" => "monthly",
        "on" => "2026-10-01"
      })

    assert conn.status == 422
    page = doc(conn.resp_body)
    assert page |> LazyHTML.query("#amount-error") |> Enum.count() == 1
    assert page |> LazyHTML.query("#amount") |> LazyHTML.attribute("value") == ["12.345"]
    assert page |> LazyHTML.query("#amount") |> LazyHTML.attribute("aria-invalid") == ["true"]
    assert page |> LazyHTML.query("#note") |> LazyHTML.attribute("value") == ["Rent"]

    assert page |> LazyHTML.query("#frequency option[selected]") |> LazyHTML.attribute("value") ==
             ["monthly"]

    assert page
           |> LazyHTML.query(~s(input[name="direction"][checked]))
           |> LazyHTML.attribute("value") ==
             ["in"]

    assert Items.visible(scope(h, "ana")) == []

    none =
      act(h, "ana", "/act/add_item", %{"note" => "Rent", "amount" => "10", "direction" => "out"})

    assert none.status == 422
    assert none.resp_body =~ "Choose how often this happens."

    done =
      act(h, "ana", "/act/add_item", %{
        "note" => "Rent",
        "amount" => "2,150",
        "direction" => "out",
        "frequency" => "monthly"
      })

    assert redirected_to(done) == "/"
    assert Phoenix.Flash.get(done.assigns.flash, :info) == "Added “Rent”."
  end

  test "what is waiting names members by their display names, never by id, with Agree and Withdraw" do
    h = household(~w(ana ben))
    # a value is owned together only with the agreement of each person being added (REQ-115)
    ok(Values.add_value(scope(h, "ana"), "Security"))
    value = scope(h, "ana") |> Items.visible() |> Enum.find(&(&1.attrs[:label] == "Security"))
    ok(Items.propose_owners(scope(h, "ana"), value.id, [id(h, "ana"), id(h, "ben")]))

    ben = home(h, "ben")
    ana = home(h, "ana")

    for html <- [ana, ben] do
      refute html =~ id(h, "ben")
      refute html =~ id(h, "ana")
    end

    assert ben
           |> doc()
           |> LazyHTML.query(~s(#waiting form[action="/act/consent"]))
           |> Enum.count() ==
             1

    others = ana |> doc() |> LazyHTML.query(~s(form[action="/act/withdraw"]))
    assert Enum.count(others) == 1
    assert ana =~ "Waiting for others"
    assert ana =~ "Ben"
  end

  test "a signed-in person without a household is shown how to start or join one" do
    {:ok, _, _} =
      FindependenceHosted.Accounts.sign_up(%{
        "email" => "solo@example.com",
        "passphrase" => "a long passphrase 1",
        "passphrase_confirmation" => "a long passphrase 1",
        "disclosure" => "true"
      })

    conn =
      post(build_conn(), "/sign-in", %{
        "account" => %{"email" => "solo@example.com", "passphrase" => "a long passphrase 1"}
      })

    html = html_response(get(recycle(conn), "/"), 200)
    assert html =~ "Start a household"
    assert html =~ "Join a household"
  end
end
