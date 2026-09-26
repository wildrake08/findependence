defmodule FindependenceApp.WebUxTest do
  @moduledoc "WI-013: plain-language, name-based interface; confirmation before irreversible actions."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}
  alias FindependenceApp.Web.Html

  @port 4848

  setup do
    path = Path.join(System.tmp_dir!(), "fv-ux-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}, {"ben", "ben passphrase 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: @port}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: @port))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  defp post_form(prev, path, params) do
    page = request(:get, "/", %{}, prev)
    request(:post, path, Map.put(params, "_csrf_token", token(page)), page)
  end

  defp login(m, p),
    do: post_form(request(:get, "/"), "/login", %{"member" => m, "passphrase" => p})

  defp home(prev), do: request(:get, "/", %{}, prev).resp_body

  defp item_id(path, note),
    do: Enum.find_value(Vault.read!(path).items, fn {id, _} -> id end) |> tap(fn _ -> note end)

  test "success messages and plain-language errors", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    added = post_form(ana, "/act/add_item", %{"note" => "Rent", "amount" => "-1200"})
    assert [loc] = Plug.Conn.get_resp_header(added, "location")
    assert loc == "/?done=add_item"
    assert request(:get, loc, %{}, ana).resp_body =~ "Added."

    id = item_id(path, "Rent")
    err = post_form(ana, "/act/relinquish", %{"item" => id})
    assert err.status == 422
    assert err.resp_body =~ "You&#39;re the only owner"
    refute err.resp_body =~ ":sole_owner"
  end

  test "amounts are formatted; names, not ids, in links and proposals", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    post_form(ana, "/act/add_item", %{"note" => "Rent", "amount" => "-1200"})
    post_form(ana, "/act/add_value", %{"label" => "A safe home"})
    vault = Vault.read!(path)
    {:ok, s} = FindependenceApp.Session.open(vault, "ana", "ana passphrase 1")
    names = Html.names(s.household, "ana")
    rent = Enum.find_value(names, fn {id, n} -> n == "Rent" && id end)
    home_value = Enum.find_value(names, fn {id, n} -> n == "A safe home" && id end)

    post_form(ana, "/act/link", %{"item" => rent, "value" => home_value})
    body = home(ana)
    assert body =~ "−1,200"
    assert body =~ "Rent → A safe home"
    # ids appear only inside form attributes, never in visible text
    visible_text = Regex.replace(~r/<[^>]*>/, body, " ")
    refute visible_text =~ rent

    post_form(ana, "/act/owners", %{"item" => rent, "owners" => ["ana", "ben"]})
    post_form(ana, "/act/add_value", %{"label" => "Freedom"})
    post_form(ana, "/logout", %{})
    # the owner change applied at once (ana was the sole owner); ben now co-owns Rent
    ben = login("ben", "ben passphrase 2")
    assert home(ben) =~ "Rent"
  end

  test "a pending grant on a joint item reads as a sentence", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    post_form(ana, "/act/add_item", %{"note" => "Car loan", "amount" => "-300"})
    [id] = Map.keys(Vault.read!(path).items)
    post_form(ana, "/act/owners", %{"item" => id, "owners" => ["ana", "ben"]})
    post_form(ana, "/act/revoke", %{"item" => id, "member" => "ben"})
    post_form(ana, "/logout", %{})

    ben = login("ben", "ben passphrase 2")
    post_form(ben, "/act/owners", %{"item" => id, "owners" => ["ben"]})
    post_form(ben, "/logout", %{})

    ana = login("ana", "ana passphrase 1")
    body = home(ana)
    assert body =~ "Make “Car loan” owned by ben."
    assert body =~ "Agreed so far: ben."
    refute body =~ "{:owners"
  end

  test "a proposal you already agreed to waits for others, with no Agree button", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    post_form(ana, "/act/add_value", %{"label" => "Holiday"})
    [id] = Map.keys(Vault.read!(path).items)
    post_form(ana, "/act/owners", %{"item" => id, "owners" => ["ana", "ben"]})
    body = home(ana)
    assert body =~ "Waiting for others"
    assert body =~ "Waiting for ben."
    refute body =~ "Agree: Make"
  end

  test "delete and leave go through a confirmation page first", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    post_form(ana, "/act/add_item", %{"note" => "Old card", "amount" => "0"})
    [id] = Map.keys(Vault.read!(path).items)

    confirm = post_form(ana, "/confirm/delete", %{"item" => id})
    assert confirm.status == 200
    assert confirm.resp_body =~ "Delete “Old card”?"
    assert confirm.resp_body =~ "can&#39;t be undone"
    assert Map.keys(Vault.read!(path).items) == [id]

    post_form(ana, "/act/delete", %{"item" => id})
    assert Vault.read!(path).items == %{}

    leave = post_form(ana, "/confirm/leave", %{})
    assert leave.resp_body =~ "Leave this household?"
  end

  test "export page is readable and the saved file is JSON with plain history", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    post_form(ana, "/act/add_item", %{"note" => "Savings", "amount" => "500"})
    page = request(:get, "/export", %{}, ana)
    assert page.resp_body =~ "Savings"
    assert page.resp_body =~ "Created by you" or page.resp_body =~ "Created by ana"

    file = request(:get, "/export.json", %{}, ana)

    assert ["attachment; filename=\"findependence-export.json\""] =
             Plug.Conn.get_resp_header(file, "content-disposition")

    assert %{
             "member" => "ana",
             "items" => [
               %{
                 "attrs" => %{"note" => "Savings", "amount" => 500},
                 "history" => ["Created by ana"]
               }
             ]
           } = :json.decode(file.resp_body)

    _ = path
  end

  test "every form field has a label" do
    ana = login("ana", "ana passphrase 1")
    post_form(ana, "/act/add_item", %{"note" => "X", "amount" => "1"})
    body = home(ana)
    ids = Regex.scan(~r/<(?:input|select)[^>]*\bid=([\w-]+)/, body) |> Enum.map(&List.last/1)
    for id <- ids, do: assert(body =~ ~s(for=#{id}), "no label for #{id}")
    assert body =~ ~s(name=viewport)
  end

  test "event history reads as sentences" do
    assert Html.event_text(%{event: :granted, by: ["ana"], details: %{grantee: "ben"}}) ==
             "Shared with ben (agreed by ana)"

    assert Html.event_text(%{event: :owner_relinquished, by: ["ben"], details: %{owner: "ben"}}) ==
             "ben stopped owning it"

    assert Html.format_amount(-1_234_567) == "−1,234,567"
    assert Html.format_amount(42) == "+42"
  end
end
