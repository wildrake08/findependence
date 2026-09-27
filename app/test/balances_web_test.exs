defmodule FindependenceApp.BalancesWebTest do
  @moduledoc "CAP-010 at the interface (REQ-135, and REQ-130..134 through it), with the date fixed."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  setup do
    Application.put_env(:findependence_app, :today, ~D[2026-09-27])
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-bal-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana pass 1"}, {"ben", "ben pass 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path, ana: login("ana", "ana pass 1")}
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  defp post(prev, path, params) do
    page = request(:get, "/", %{}, prev)
    request(:post, path, Map.put(params, "_csrf_token", token(page)), page)
  end

  defp login(m, p), do: post(request(:get, "/"), "/login", %{"member" => m, "passphrase" => p})
  defp follow(resp), do: request(:get, hd(Plug.Conn.get_resp_header(resp, "location")), %{}, resp)

  defp household(path) do
    {:ok, s} = Session.open(Vault.read!(path), "ana", "ana pass 1")
    s.household
  end

  defp new_id(resp),
    do:
      resp
      |> Plug.Conn.get_resp_header("location")
      |> hd()
      |> String.replace_prefix("/items/", "")

  test "home offers a place for balances without forms; the add page has one form for each kind",
       %{ana: ana} do
    home = request(:get, "/", %{}, ana).resp_body
    assert home =~ "<h2>Balances and debts</h2>"
    assert home =~ ~s(<a class="button-link" href="/balances/new">Add an account or debt</a>)
    refute home =~ ~s(action="/act/add_account")
    page = request(:get, "/balances/new", %{}, ana).resp_body
    assert page =~ ~s(action="/act/add_account") and page =~ ~s(action="/act/add_debt")
  end

  test "adding an account, then its balance, from its own page", %{path: path, ana: ana} do
    resp = post(ana, "/act/add_account", %{"label" => "Joint checking", "type" => "checking"})
    id = new_id(resp)
    body = follow(resp).resp_body
    assert body =~ "Added “Joint checking”. Add its balance below."
    assert body =~ "No balance recorded yet."
    assert body =~ ~s(<input id=on name=on type=date required value="2026-09-27")

    resp =
      post(ana, "/act/add_reading", %{
        "item" => id,
        "balance" => "1,240.50",
        "on" => "2026-09-26",
        "return" => "/items/#{id}"
      })

    body = follow(resp).resp_body
    assert body =~ "Saved the balance for “Joint checking”."
    assert body =~ ~s(<p class="amount-big">$1,240.50</p>)
    assert body =~ "As of Saturday, September 26."
    assert household(path).readings[id] |> Enum.map(& &1.balance) == [124_050]

    home = request(:get, "/", %{}, ana).resp_body
    assert home =~ "$1,240.50"
    assert home =~ "Checking account, as of Saturday, September 26"
    # accounts are not items: they're not listed with money items or counted in the totals
    [items_card] = Regex.run(~r/<h2>Your items<\/h2>.*?<\/section>/s, home)
    refute items_card =~ "Joint checking"
  end

  test "an overdrawn account; mistakes are shown at the field with what was typed kept", %{
    path: path,
    ana: ana
  } do
    id = new_id(post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"}))

    follow(
      post(ana, "/act/add_reading", %{"item" => id, "balance" => "−50", "on" => "2026-09-27"})
    )

    assert request(:get, "/items/#{id}", %{}, ana).resp_body =~
             ~s(<p class="amount-big">−$50.00</p>)

    for {params, field, text} <- [
          {%{"balance" => "12,5O", "on" => "2026-09-27"}, "balance", "Enter the balance"},
          {%{"balance" => "", "on" => "2026-09-27"}, "balance", "Enter the balance."},
          {%{"balance" => "10", "on" => "2026-02-30"}, "on", "Enter the date"}
        ] do
      resp = post(ana, "/act/add_reading", Map.put(params, "item", id))
      assert resp.status == 422
      assert resp.resp_body =~ ~s(id="#{field}-error")
      assert resp.resp_body =~ text
      assert resp.resp_body =~ ~s(value="#{params["balance"]}")
    end

    assert length(household(path).readings[id]) == 1
  end

  test "a debt: what's owed, the rate, the minimum, and a month's interest as a fact", %{
    path: path,
    ana: ana
  } do
    id = new_id(post(ana, "/act/add_debt", %{"label" => "Visa", "type" => "card"}))

    resp =
      post(ana, "/act/add_reading", %{
        "item" => id,
        "balance" => "5,200",
        "rate" => "21.99",
        "min_payment" => "150",
        "on" => "2026-09-27",
        "return" => "/items/#{id}"
      })

    body = follow(resp).resp_body
    assert body =~ ~s(<p class="amount-big">$5,200.00 owed</p>)
    assert body =~ "Interest rate 21.99% · Minimum payment $150.00"
    assert body =~ "At 21.99%, a month's interest on $5,200.00 is about $95.29."
    assert [%{rate_bp: 2199, min_payment: 15_000}] = household(path).readings[id]

    for {params, field} <- [
          {%{"rate" => "abc", "min_payment" => "150"}, "rate"},
          {%{"rate" => "120", "min_payment" => "150"}, "rate"},
          {%{"rate" => "21.99", "min_payment" => ""}, "min_payment"}
        ] do
      resp =
        post(
          ana,
          "/act/add_reading",
          Map.merge(params, %{"item" => id, "balance" => "5,000", "on" => "2026-09-27"})
        )

      assert resp.status == 422
      assert resp.resp_body =~ ~s(id="#{field}-error")
    end

    # a debt's amount owed can't be negative
    resp =
      post(ana, "/act/add_reading", %{
        "item" => id,
        "balance" => "-5",
        "rate" => "1",
        "min_payment" => "1",
        "on" => "2026-09-27"
      })

    assert resp.status == 422
  end

  test "shared with someone: they see the latest only, and can't update it", %{
    path: path,
    ana: ana
  } do
    id = new_id(post(ana, "/act/add_debt", %{"label" => "HELOC", "type" => "heloc"}))

    for {bal, on} <- [{"40,000", "2026-08-27"}, {"39,500", "2026-09-27"}],
        do:
          post(ana, "/act/add_reading", %{
            "item" => id,
            "balance" => bal,
            "rate" => "8.5",
            "min_payment" => "320",
            "on" => on
          })

    owner_page = request(:get, "/items/#{id}", %{}, ana).resp_body
    assert owner_page =~ "<h2>Earlier balances</h2>"
    assert owner_page =~ "Balance updated by ana"
    post(ana, "/act/grant", %{"item" => id, "member" => "ben"})

    ben = login("ben", "ben pass 2")
    page = request(:get, "/items/#{id}", %{}, ben).resp_body
    assert page =~ "$39,500.00 owed"
    refute page =~ "$40,000.00"
    refute page =~ ~s(action="/act/add_reading")

    resp =
      post(ben, "/act/add_reading", %{
        "item" => id,
        "balance" => "1",
        "rate" => "1",
        "min_payment" => "1",
        "on" => "2026-09-27"
      })

    assert resp.status == 422

    assert resp.resp_body =~ "Only an owner can update the balance."
    assert length(household(path).readings[id]) == 2
  end

  test "adding needs a name and a kind, and keeps what was typed", %{ana: ana} do
    resp = post(ana, "/act/add_debt", %{"label" => "Car loan", "type" => ""})
    assert resp.status == 422
    assert resp.resp_body =~ "Choose what kind it is."
    assert resp.resp_body =~ ~s(value="Car loan")

    assert post(ana, "/act/add_account", %{"label" => " ", "type" => "savings"}).resp_body =~
             "Give it a name."
  end

  test "the export lists balances and the file carries the readings", %{ana: ana} do
    id = new_id(post(ana, "/act/add_account", %{"label" => "Savings", "type" => "savings"}))
    post(ana, "/act/add_reading", %{"item" => id, "balance" => "900", "on" => "2026-09-27"})
    page = request(:get, "/export", %{}, ana).resp_body
    assert page =~ "<h3>Balances and debts</h3>"
    assert page =~ "$900.00 as of Sunday, September 27. 1 balance recorded."
    json = request(:get, "/export.json", %{}, ana).resp_body
    assert json =~ ~s("balance":90000)
  end
end
