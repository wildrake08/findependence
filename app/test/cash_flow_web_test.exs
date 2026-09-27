defmodule FindependenceApp.CashFlowWebTest do
  @moduledoc "CAP-011 at the interface (REQ-136, REQ-138..140), with today fixed at Sunday, September 27, 2026."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  setup do
    Application.put_env(:findependence_app, :today, ~D[2026-09-27])
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-flow-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana pass 1"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path, ana: login()}
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

  defp login,
    do: post(request(:get, "/"), "/login", %{"member" => "ana", "passphrase" => "ana pass 1"})

  defp household(path) do
    {:ok, s} = Session.open(Vault.read!(path), "ana", "ana pass 1")
    s.household
  end

  defp add(ana, note, amount, dir, freq, on),
    do:
      post(ana, "/act/add_item", %{
        "note" => note,
        "amount" => amount,
        "direction" => dir,
        "frequency" => freq,
        "on" => on
      })

  defp id_of(path, note),
    do:
      Enum.find_value(household(path).items, fn {id, i} ->
        (i.attrs[:note] || i.attrs[:label]) == note && id
      end)

  test "REQ-136: a date is optional, checked, stored, and shown as the next date; irregular items keep none",
       %{path: path, ana: ana} do
    assert add(ana, "Rent", "2,150", "out", "monthly", "2026-10-01").status == 303
    assert household(path).items[id_of(path, "Rent")].attrs.on == "2026-10-01"

    assert request(:get, "/items/#{id_of(path, "Rent")}", %{}, ana).resp_body =~
             "<p>Next: Thursday, October 1</p>"

    add(ana, "Repairs", "2,400", "out", "irregular", "2026-10-01")
    refute Map.has_key?(household(path).items[id_of(path, "Repairs")].attrs, :on)

    add(ana, "Gym", "45", "out", "monthly", "")
    refute Map.has_key?(household(path).items[id_of(path, "Gym")].attrs, :on)

    resp = add(ana, "Phone", "65", "out", "monthly", "2026-02-30")
    assert resp.status == 422
    assert resp.resp_body =~ ~s(id="on-error")
    assert resp.resp_body =~ ~s(value="2026-02-30")
    assert id_of(path, "Phone") == nil
  end

  test "REQ-138: coming up lists the next 14 days, and a running balance once checking has one",
       %{ana: ana} do
    home = request(:get, "/", %{}, ana).resp_body
    # UX-004 H2: with no account, both things Coming up needs, with a way to each
    assert home =~
             ~s(Coming up needs an account's balance and the date each bill or paycheck happens. <a href="/balances/new">Add an account and its balance</a>)

    add(ana, "Rent", "2,150", "out", "monthly", "2026-10-01")
    add(ana, "Paycheck", "1,980", "in", "biweekly", "2026-10-02")
    add(ana, "Far off", "10", "out", "one_off", "2026-12-01")
    home = request(:get, "/", %{}, ana).resp_body
    [card] = Regex.run(~r/<section class=card id=coming-up>.*?<\/section>/s, home)
    assert card =~ "Thursday, October 1"
    assert card =~ "Friday, October 2"
    refute card =~ "Far off"
    assert card =~ "add your checking account"
    # waiting comes first, then coming up, then items (the UX contract's order)
    assert :binary.match(home, "id=coming-up") < :binary.match(home, "<h2>Your items</h2>")

    resp = post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"})

    id =
      resp
      |> Plug.Conn.get_resp_header("location")
      |> hd()
      |> String.replace_prefix("/items/", "")

    post(ana, "/act/add_reading", %{"item" => id, "balance" => "500", "on" => "2026-09-27"})

    [card] =
      Regex.run(
        ~r/<section class=card id=coming-up>.*?<\/section>/s,
        request(:get, "/", %{}, ana).resp_body
      )

    assert card =~ "Starting from Checking: $500.00 as of Sunday, September 27."

    assert card =~
             "Counts items you own, and items shared with you that you&#39;ve said go through these accounts; anything others keep private isn&#39;t included."

    # 500 - 2,150 = -1,650 on the 1st; + 1,980 = 330 on the 2nd
    assert card =~ ~s(−$1,650.00 <span class=below>Below zero</span>)
    assert card =~ ~s(data-label="Balance after">$330.00<)
  end

  test "REQ-139/140: the 60-day page names the days below zero and the set-asides", %{ana: ana} do
    add(ana, "Rent", "2,150", "out", "monthly", "2026-10-01")
    add(ana, "Paycheck", "1,980", "in", "biweekly", "2026-10-09")
    add(ana, "Car insurance", "1,140", "out", "twice_a_year", "2027-01-15")
    add(ana, "Repairs", "2,400", "out", "irregular", "")
    resp = post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"})

    id =
      resp
      |> Plug.Conn.get_resp_header("location")
      |> hd()
      |> String.replace_prefix("/items/", "")

    post(ana, "/act/add_reading", %{"item" => id, "balance" => "1,000", "on" => "2026-09-27"})

    page = request(:get, "/next-60-days", %{}, ana).resp_body
    # 1,000 - 2,150 = -1,150 from Oct 1 until the paycheck on Oct 9 (+1,980 = 830)
    assert page =~ "<b>Below zero:</b> Thursday, October 1 to Thursday, October 8"
    assert page =~ "Setting aside <b>$390.00 a month</b> covers these:"
    assert page =~ "Repairs</a>: −$2,400.00 a year, irregular, $200.00 a month"
    assert page =~ "Car insurance</a>: −$1,140.00 twice a year, $190.00 a month"

    text =
      page |> String.replace(~r/<style>.*?<\/style>/s, "") |> String.replace(~r/<[^>]+>/, " ")

    assert FindependenceApp.Web.Glossary.judgments(text) == []
  end
end
