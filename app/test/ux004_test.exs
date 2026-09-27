defmodule FindependenceApp.UX004Test do
  @moduledoc "UX-004's corrections (P1-P4, H2, H3) against their acceptance criteria."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}
  alias FindependenceApp.Web.Html
  alias Mix.Tasks.Findependence.Demo

  @today ~D[2026-09-27]

  setup do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-ux004-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}, {"ben", "ben passphrase 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    first = request(:get, "/")

    ana =
      request(
        :post,
        "/login",
        %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => csrf(first)},
        first
      )

    %{path: path, ana: ana}
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp csrf(page),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last()

  defp form_token(page),
    do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp loc(resp), do: resp |> Plug.Conn.get_resp_header("location") |> List.first()
  defp follow(resp), do: request(:get, loc(resp), %{}, resp).resp_body

  # the same form, sent twice from one page
  defp twice(prev, page_path, action, params) do
    page = request(:get, page_path, %{}, prev)
    params = Map.merge(params, %{"_csrf_token" => csrf(page), "_form" => form_token(page)})
    first = request(:post, action, params, page)
    second = request(:post, action, params, first)
    {first, second}
  end

  defp household(path) do
    {:ok, s} = Session.open(Vault.read!(path), "ana", "ana passphrase 1")
    s.household
  end

  defp demo do
    path =
      Path.join(System.tmp_dir!(), "fv-ux004-demo-#{System.unique_integer([:positive])}.vault")

    :ok = Demo.build(path, iterations: 1_000, unsafe_test: true, today: @today)
    on_exit(fn -> File.rm(path) end)

    Map.new(Demo.members(), fn {m, p} ->
      {:ok, s} = Session.open(Vault.read!(path), m, p)
      {m, s.household}
    end)
  end

  test "every form carries a one-time token beside the CSRF token", %{ana: ana} do
    home = request(:get, "/", %{}, ana).resp_body
    tokens = Regex.scan(~r/name=_form value="([^"]+)"/, home, capture: :all_but_first)
    assert tokens != []
    # a new page, a new token
    refute form_token(request(:get, "/", %{}, ana)) == form_token(request(:get, "/", %{}, ana))
  end

  test "P1 (REQ-165): a form sent twice changes the household once, and the repeat says so",
       %{path: path, ana: ana} do
    item = %{
      "note" => "Rent",
      "amount" => "1,450",
      "direction" => "out",
      "frequency" => "monthly"
    }

    {first, second} = twice(ana, "/", "/act/add_item", item)
    assert first.status == 303 and second.status == 303
    assert loc(second) == loc(first)
    assert follow(second) =~ "That was already saved."
    assert household(path).items |> Map.values() |> Enum.count(&(&1.attrs[:note] == "Rent")) == 1

    {_, again} = twice(ana, "/", "/act/add_value", %{"label" => "A safe home"})
    assert follow(again) =~ "That was already saved."

    assert household(path).items
           |> Map.values()
           |> Enum.count(&(&1.attrs[:label] == "A safe home")) ==
             1

    {made, _} =
      twice(ana, "/balances/new", "/act/add_account", %{
        "label" => "Checking",
        "type" => "checking"
      })

    accounts =
      household(path).items
      |> Map.values()
      |> Enum.filter(&(&1.attrs[:note] == "Checking" or &1.attrs[:label] == "Checking"))

    assert length(accounts) == 1
    "/items/" <> id = loc(made)

    {_, _} =
      twice(ana, "/items/#{id}", "/act/add_reading", %{
        "item" => id,
        "balance" => "850",
        "on" => "2026-09-26",
        "return" => "/items/#{id}"
      })

    assert {:ok, [_one]} = Findependence.Balances.readings(household(path), "ana", id)

    {plan, _} = twice(ana, "/plans", "/act/new_plan", %{"name" => "If pay stops"})
    assert map_size(household(path).plans["ana"]) == 1
    plan_id = plan |> loc() |> String.split(["/plans/", "?"]) |> Enum.at(1)

    twice(ana, "/plans/#{plan_id}", "/act/plan_step", %{
      "plan" => plan_id,
      "kind" => "borrow",
      "amount" => "6,000",
      "rate" => "8.75",
      "payment" => "250",
      "from" => "2026-12"
    })

    assert length(household(path).plans["ana"][plan_id].steps) == 1
  end

  test "P1 (REQ-165): a refused form changed nothing, so the same form may be sent again, corrected",
       %{path: path, ana: ana} do
    page = request(:get, "/", %{}, ana)
    base = %{"_csrf_token" => csrf(page), "_form" => form_token(page), "note" => "Phone"}

    refused =
      request(
        :post,
        "/act/add_item",
        Map.merge(base, %{"amount" => "55,5", "direction" => "out", "frequency" => "monthly"}),
        page
      )

    assert refused.status == 422

    fixed =
      request(
        :post,
        "/act/add_item",
        Map.merge(base, %{"amount" => "55.50", "direction" => "out", "frequency" => "monthly"}),
        refused
      )

    assert fixed.status == 303
    refute follow(fixed) =~ "That was already saved."
    assert household(path).items |> Map.values() |> Enum.any?(&(&1.attrs[:note] == "Phone"))
  end

  test "P2: a joint account's view is labelled as the member's part; a member's own account isn't" do
    v = demo()
    dad = Html.coming_up_card(v["Dad"], "Dad", @today)
    assert dad =~ ~s(<table class="stack flow partial")
    assert dad =~ ~s(<th role=columnheader scope=col class=num>Your part after</th>)
    refute dad =~ "Balance after</th>"
    assert dad =~ "Mom also owns Joint checking, so this is your part:"
    # "Below zero" stays (REQ-139)
    assert Html.next_60_page(v["Dad"], "Dad", @today) =~ "<span class=below>Below zero</span>"
    assert Html.next_60_page(v["Dad"], "Dad", @today) =~ "Your part after</th>"
    assert Html.ahead_page(v["Dad"], "Dad", @today) =~ "Your part at the end</th>"

    # one owner: the account's own balance, labelled as such
    h = Findependence.Household.new(["ana"])
    {:ok, h} = Findependence.Balances.add_account(h, "ana", "c", "Checking", :checking)

    {:ok, h} =
      Findependence.Balances.add_reading(h, "ana", "c", %{on: "2026-09-26", balance: 1_000})

    {:ok, h} =
      Findependence.Household.add_item(h, "ana", "r", %{
        note: "Rent",
        amount: -500,
        unit: :cents,
        frequency: {:every, 1, :month},
        on: "2026-10-01"
      })

    own = Html.coming_up_card(h, "ana", @today)
    assert own =~ "Balance after</th>"
    assert own =~ ~s(<table class="stack flow")
    refute own =~ "partial"
    refute own =~ "Your part"
    assert Html.ahead_page(h, "ana", @today) =~ "Cash at the end</th>"
  end

  test "P3 (REQ-166): deleting a plan is previewed by name and confirmed; going back keeps it",
       %{path: path, ana: ana} do
    page = request(:get, "/plans", %{}, ana)

    made =
      request(
        :post,
        "/act/new_plan",
        %{"name" => "If pay stops", "_csrf_token" => csrf(page), "_form" => form_token(page)},
        page
      )

    id = made |> loc() |> String.split(["/plans/", "?"]) |> Enum.at(1)
    plan_page = request(:get, "/plans/#{id}", %{}, made)

    assert plan_page.resp_body =~
             ~s(<form class=inline method=post action="/confirm/delete_plan">)

    refute plan_page.resp_body =~ ~s(action="/act/delete_plan")

    confirm =
      request(
        :post,
        "/confirm/delete_plan",
        %{"plan" => id, "_csrf_token" => csrf(plan_page)},
        plan_page
      )

    assert confirm.status == 200
    assert confirm.resp_body =~ "Delete the plan “If pay stops”?"
    assert confirm.resp_body =~ "Its 0 steps will be deleted with it."
    assert confirm.resp_body =~ ~s(<a href="/plans/#{id}">No, go back</a>)
    # nothing is deleted by the preview
    assert Map.has_key?(household(path).plans["ana"], id)

    done =
      request(
        :post,
        "/act/delete_plan",
        %{
          "plan" => id,
          "return" => "/plans",
          "_csrf_token" => csrf(confirm),
          "_form" => form_token(confirm)
        },
        confirm
      )

    assert loc(done) == "/plans"
    assert follow(done) =~ "Deleted the plan “If pay stops”."
    refute Map.has_key?(household(path).plans["ana"], id)
    # a plan that is gone can't be confirmed
    gone =
      request(
        :post,
        "/confirm/delete_plan",
        %{"plan" => id, "_csrf_token" => csrf(confirm)},
        done
      )

    assert loc(gone) == "/plans"
  end

  test "P4: the unlock page and setup say what can't be recovered" do
    notice = Web.limits_notice()
    assert notice =~ "A forgotten passphrase can't be recovered."
    assert notice =~ "There's no backup"
    assert request(:get, "/").resp_body =~ Html.esc(notice)

    # setup prints it before anyone chooses a passphrase (reading a passphrase needs a terminal, so
    # the task's source is checked rather than run)
    setup = File.read!("lib/mix/tasks/findependence.setup.ex")
    said = :binary.match(setup, "Mix.shell().info(FindependenceApp.Web.limits_notice())")
    asked = :binary.match(setup, "please type your passphrase privately")
    assert said != :nomatch and asked != :nomatch
    assert elem(said, 0) < elem(asked, 0)
  end

  test "H2: empty states say what Coming up needs, and totals wait for an item", %{ana: ana} do
    home = request(:get, "/", %{}, ana).resp_body

    assert home =~
             ~s(Coming up needs an account's balance and the date each bill or paycheck happens. <a href="/balances/new">Add an account and its balance</a>, and give items a date when you <a href="#add-item">add them</a>.)

    assert home =~ "<p class=empty>Totals appear once you add items.</p>"
    refute home =~ ~s(aria-label="Totals by value")

    # with an account and nothing dated, the other message; with an item, the totals table
    page = request(:get, "/balances/new", %{}, ana)

    made =
      request(
        :post,
        "/act/add_account",
        %{
          "label" => "Checking",
          "type" => "checking",
          "_csrf_token" => csrf(page),
          "_form" => form_token(page)
        },
        page
      )

    "/items/" <> id = loc(made)
    item_page = request(:get, "/items/#{id}", %{}, made)

    request(
      :post,
      "/act/add_reading",
      %{
        "item" => id,
        "balance" => "850",
        "on" => "2026-09-26",
        "return" => "/items/#{id}",
        "_csrf_token" => csrf(item_page),
        "_form" => form_token(item_page)
      },
      item_page
    )

    home2 = request(:get, "/", %{}, ana)

    request(
      :post,
      "/act/add_item",
      %{
        "note" => "Gym",
        "amount" => "45",
        "direction" => "out",
        "frequency" => "monthly",
        "_csrf_token" => csrf(home2),
        "_form" => form_token(home2)
      },
      home2
    )

    home3 = request(:get, "/", %{}, ana).resp_body
    assert home3 =~ "Nothing dated in the next 14 days."
    assert home3 =~ ~s(aria-label="Totals by value")
    refute home3 =~ "Totals appear once you add items."
  end

  test "H3: an unknown address gets the page, with a way home, and a 404", %{ana: ana} do
    locked = request(:get, "/nowhere")
    assert locked.status == 404
    assert locked.resp_body =~ "<h2>That page doesn't exist</h2>"
    assert locked.resp_body =~ ~s(<a href="/">Go to the home page</a>)
    assert locked.resp_body =~ "<header>"

    unlocked = request(:get, "/nowhere", %{}, ana)
    assert unlocked.status == 404
    assert unlocked.resp_body =~ "<span class=who>ana</span>"
  end
end
