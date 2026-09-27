defmodule FindependenceApp.V03WebTest do
  @moduledoc "v0.3 at the interface (REQ-141..148), with today fixed at Sunday, September 27, 2026."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  setup do
    Application.put_env(:findependence_app, :today, ~D[2026-09-27])
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-v03-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana pass 1"}, {"ben", "ben pass 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    ana = login("ana", "ana pass 1")

    for {note, amt, dir, f, on} <- [
          {"Paycheck", "2,650", "in", "biweekly", "2026-10-02"},
          {"Health premium", "400", "out", "monthly", ""},
          {"Mortgage", "2,240", "out", "monthly", "2026-10-01"}
        ],
        do:
          post(ana, "/act/add_item", %{
            "note" => note,
            "amount" => amt,
            "direction" => dir,
            "frequency" => f,
            "on" => on
          })

    chk = new_id(post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"}))
    post(ana, "/act/add_reading", %{"item" => chk, "balance" => "1,000", "on" => "2026-09-27"})
    sav = new_id(post(ana, "/act/add_account", %{"label" => "Savings", "type" => "savings"}))
    post(ana, "/act/add_reading", %{"item" => sav, "balance" => "6,000", "on" => "2026-09-27"})
    visa = new_id(post(ana, "/act/add_debt", %{"label" => "Visa", "type" => "card"}))

    post(ana, "/act/add_reading", %{
      "item" => visa,
      "balance" => "6,200",
      "rate" => "24.99",
      "min_payment" => "190",
      "on" => "2026-09-27"
    })

    %{path: path, ana: ana, visa: visa}
  end

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

  defp visible_text(html),
    do: html |> String.replace(~r/<style>.*?<\/style>/s, "") |> String.replace(~r/<[^>]+>/, " ")

  test "home links to the new pages without adding forms", %{ana: ana} do
    home = request(:get, "/", %{}, ana).resp_body

    assert home =~
             ~s(<a href="/ahead">The next 12 months</a> · <a href="/plans">Plans</a> · <a href="/goals">Goals</a>)

    refute home =~ ~s(action="/act/new_plan")
  end

  test "REQ-141: the next 12 months, with cash, debts, and the assumptions stated", %{ana: ana} do
    page = request(:get, "/ahead", %{}, ana).resp_body
    assert page =~ "October 2026" and page =~ "September 2027"
    # cash starts from both accounts (7,000); October: 5,741.67 in, 2,640 out
    assert page =~ "Cash starts from Checking and Savings: $7,000.00."
    assert page =~ ~s(data-label="Cash at the end" data-short="Cash at the end">$10,101.67<)
    assert page =~ "Debts over the next 12 months"
    assert page =~ "each debt grows by a month's interest and falls by its minimum payment"
    assert FindependenceApp.Web.Glossary.judgments(visible_text(page)) == []
  end

  test "REQ-142/143: a plan compared with things as they are; steps checked; private", %{
    path: path,
    ana: ana
  } do
    resp = post(ana, "/act/new_plan", %{"name" => "If the job stops"})
    plan = new_id(resp)
    assert follow(resp) =~ "Started “If the job stops”. Add its steps below."
    pay = id_of(path, "Paycheck")

    resp =
      post(ana, "/act/plan_step", %{
        "plan" => plan,
        "kind" => "switch_off",
        "items" => [pay],
        "from" => "2026-11"
      })

    assert follow(resp) =~ "Added the step."

    post(ana, "/act/plan_step", %{
      "plan" => plan,
      "kind" => "add",
      "note" => "Marketplace premium",
      "amount" => "600",
      "direction" => "out",
      "frequency" => "monthly",
      "from" => "2026-11"
    })

    post(ana, "/act/plan_step", %{
      "plan" => plan,
      "kind" => "borrow",
      "amount" => "5,000",
      "rate" => "9",
      "payment" => "200",
      "from" => "2026-12"
    })

    page = request(:get, "/plans/#{plan}", %{}, ana).resp_body
    assert page =~ "From November 2026: switch off Paycheck."
    assert page =~ "From November 2026: Marketplace premium, −$600.00 a month (planned)."
    assert page =~ "From December 2026: borrow $5,000.00 at 9%, paying $200.00 a month."
    # October is the same both ways; November loses the paycheck and adds the premium
    assert page =~ ~s(data-label="Without this plan" data-short="Without this plan">$10,101.67<)
    assert page =~ ~s(data-label="With this plan" data-short="With this plan">$10,101.67<)
    # Nov: 10,101.67 - 2,240 - 400 - 600 = 6,861.67
    assert page =~ "$6,861.67"
    assert page =~ "Interest on the planned borrowing over these months:"

    # each kind of step has its own heading and a button saying what it adds
    for h3 <- ["Switch items off", "Add planned money in or out", "Borrow"],
        do: assert(page =~ "<h3>#{h3}</h3>")

    buttons = Regex.scan(~r/<button>(Add [^<]+)<\/button>/, page, capture: :all_but_first)
    assert List.flatten(buttons) == ["Add switching off", "Add planned item", "Add borrowing"]

    assert page =~ "This is a plan, not what&#39;s real." or
             page =~ "This is a plan, not what's real."

    # the plan changes nothing real
    assert request(:get, "/ahead", %{}, ana).resp_body =~
             ~s(data-short="Cash at the end">$10,101.67<)

    for {params, text} <- [
          {%{"kind" => "switch_off", "from" => "2026-11"},
           "Tick at least one item to switch off."},
          {%{
             "kind" => "add",
             "note" => "X",
             "amount" => "5",
             "direction" => "out",
             "frequency" => "",
             "from" => "2026-11"
           }, "Choose how often the planned item happens."},
          {%{
             "kind" => "borrow",
             "amount" => "5,000",
             "rate" => "abc",
             "payment" => "200",
             "from" => "2026-12"
           }, "Enter how much to borrow, the interest rate, and the monthly payment."},
          {%{"kind" => "switch_off", "items" => [pay], "from" => "Nov"}, "Check the step"}
        ] do
      resp = post(ana, "/act/plan_step", Map.put(params, "plan", plan))
      assert resp.status == 422, inspect(params)
      assert resp.resp_body =~ text
    end

    ben = login("ben", "ben pass 2")
    assert request(:get, "/plans", %{}, ben).resp_body =~ "No plans yet."
    assert request(:get, "/plans/#{plan}", %{}, ben).status == 404

    ana = login("ana", "ana pass 1")

    [_, n | _] =
      Regex.run(~r/name="n" value="(\d+)"/, request(:get, "/plans/#{plan}", %{}, ana).resp_body)

    follow(
      post(ana, "/act/remove_step", %{"plan" => plan, "n" => n, "return" => "/plans/#{plan}"})
    )

    refute request(:get, "/plans/#{plan}", %{}, ana).resp_body =~ "switch off Paycheck"
    resp = post(ana, "/act/delete_plan", %{"plan" => plan, "return" => "/plans"})
    # REQ-166 / UX-004 P3: the message names the plan
    assert follow(resp) =~ "Deleted the plan “"
    assert household(path).plans == %{"ana" => %{}}
  end

  test "REQ-144: marking what depends on a job; the plan switches it off too", %{
    path: path,
    ana: ana
  } do
    health = id_of(path, "Health premium")
    pay = id_of(path, "Paycheck")
    page = request(:get, "/items/#{health}", %{}, ana).resp_body
    assert page =~ "Does it depend on a job?"

    resp =
      post(ana, "/act/mark", %{"item" => health, "job" => pay, "return" => "/items/#{health}"})

    assert follow(resp) =~ "Marked “Health premium” as depending on “Paycheck”."
    plan = new_id(post(ana, "/act/new_plan", %{"name" => "Job"}))

    post(ana, "/act/plan_step", %{
      "plan" => plan,
      "kind" => "switch_off",
      "items" => [pay],
      "from" => "2026-11"
    })

    assert request(:get, "/plans/#{plan}", %{}, ana).resp_body =~
             "switch off Paycheck (and what depends on it: Health premium)."

    # the paycheck's own page offers no mark (it's the job)
    refute request(:get, "/items/#{pay}", %{}, ana).resp_body =~ "Does it depend on a job?"

    follow(
      post(ana, "/act/unmark", %{"item" => health, "job" => pay, "return" => "/items/#{health}"})
    )

    assert household(path).depends == %{"ana" => MapSet.new()}
  end

  test "REQ-145: the debt's what-if is worked out on its page and stores nothing", %{
    path: path,
    ana: ana,
    visa: visa
  } do
    before = Vault.read!(path)
    page = request(:get, "/items/#{visa}", %{"extra" => "100", "rate" => "10"}, ana).resp_body
    assert page =~ "Paying the minimum of $190.00, it would take"
    assert page =~ "With $100.00 more a month:"
    # the extra payment changes the answer: fewer months than the minimum alone
    [_, base] = Regex.run(~r/it would take ([^,]+) to clear/, page)
    [_, extra] = Regex.run(~r/With \$100\.00 more a month:<\/b> ([^,]+),/, page)
    assert base != extra
    # 6,200 at 10% = 51.67 a month
    assert page =~ "At 10%:</b> a month&#39;s interest on $6,200.00 would be $51.67." or
             page =~ "At 10%:</b> a month's interest on $6,200.00 would be $51.67."

    assert request(:get, "/items/#{visa}", %{"extra" => "lots"}, ana).resp_body =~
             "Enter the extra amount like 100"

    assert Vault.read!(path) == before
  end

  test "REQ-146/147: how long savings would last, the member's goal, and a set-aside rate", %{
    path: path,
    ana: ana
  } do
    page = request(:get, "/goals", %{}, ana).resp_body
    # 6,000 against 2,640 a month
    assert page =~ "About 2.3 months"
    follow(post(ana, "/act/fund_goal", %{"months" => "3"}))

    assert request(:get, "/goals", %{}, ana).resp_body =~
             "Your goal: 3 months of money out. You&#39;re at 2.3 of 3." or
             request(:get, "/goals", %{}, ana).resp_body =~
               "Your goal: 3 months of money out. You're at 2.3 of 3."

    assert post(ana, "/act/fund_goal", %{"months" => "99"}).status == 422

    post(ana, "/act/add_value", %{"label" => "Side business"})

    post(ana, "/act/add_item", %{
      "note" => "Shop sales",
      "amount" => "500",
      "direction" => "in",
      "frequency" => "monthly"
    })

    post(ana, "/act/link", %{
      "item" => id_of(path, "Shop sales"),
      "value" => id_of(path, "Side business")
    })

    follow(
      post(ana, "/act/set_aside", %{"value" => id_of(path, "Side business"), "rate" => "25"})
    )

    assert request(:get, "/goals", %{}, ana).resp_body =~ "set aside $125.00 a month"
    follow(post(ana, "/act/set_aside", %{"value" => id_of(path, "Side business"), "rate" => ""}))
    refute request(:get, "/goals", %{}, ana).resp_body =~ "set aside $125.00"
  end

  test "REQ-148: a plan proposed to another member is shared only when they agree", %{
    path: path,
    ana: ana
  } do
    plan = new_id(post(ana, "/act/new_plan", %{"name" => "Side business"}))

    post(ana, "/act/plan_step", %{
      "plan" => plan,
      "kind" => "add",
      "note" => "Shop sales",
      "amount" => "500",
      "direction" => "in",
      "frequency" => "monthly",
      "from" => "2026-11"
    })

    # a step naming one of ana's private items
    post(ana, "/act/plan_step", %{
      "plan" => plan,
      "kind" => "switch_off",
      "items" => [id_of(path, "Mortgage")],
      "from" => "2027-01"
    })

    resp = post(ana, "/act/share_plan", %{"plan" => plan, "members" => ["ben"]})
    assert follow(resp) =~ "Sent the request. It becomes a shared plan when ben agrees."
    # the one asked must agree, as with a shared value (REQ-115), and the sender sees that
    assert request(:get, "/", %{}, ana).resp_body =~ "Waiting for ben."
    # the preview is only for the one asked
    [sent] = Map.keys(household(path).proposals)
    assert request(:get, "/requests/#{sent}", %{}, ana).status == 404

    ben = login("ben", "ben pass 2")
    home = request(:get, "/", %{}, ben).resp_body
    assert home =~ "Request: share the plan “Side business” with ana."
    [pid] = Map.keys(household(path, "ben", "ben pass 2").proposals)

    # before agreeing, ben sees the plan worked out from his own items, and nothing of ana's
    assert home =~ ~s(<a href="/requests/#{pid}">See the plan</a>)
    preview = request(:get, "/requests/#{pid}", %{}, ben).resp_body
    assert preview =~ "ana asked you to share this plan. Nothing changes until you agree"
    assert preview =~ "From November 2026: Shop sales, +$500.00 a month (planned)."

    assert preview =~ "From January 2027: switch off an item you can&#39;t see." or
             preview =~ "From January 2027: switch off an item you can't see."

    refute preview =~ "Mortgage"
    assert preview =~ "With and without this plan"
    assert preview =~ "Agree to share it"
    # it's only for the one asked, and only while it waits
    assert request(:get, "/requests/999999", %{}, ben).status == 404
    post(ben, "/act/consent", %{"proposal" => "#{pid}"})
    assert request(:get, "/requests/#{pid}", %{}, ben).status == 404
    plans = request(:get, "/plans", %{}, ben).resp_body
    assert plans =~ "<h2>Shared plans</h2>"

    shared =
      Enum.find_value(household(path, "ben", "ben pass 2").items, fn {id, i} ->
        i.attrs[:kind] == :plan && id
      end)

    page = request(:get, "/items/#{shared}", %{}, ben).resp_body
    assert page =~ "A shared plan, owned by ana and you."
    assert page =~ "From November 2026: Shop sales, +$500.00 a month (planned)."
    # a shared plan isn't money: it's not on anyone's items list
    refute request(:get, "/", %{}, ben).resp_body =~ ~s(<b>Side business</b></a></td>)
  end
end
