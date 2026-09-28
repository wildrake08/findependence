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

  # the page's one-time form token, as a browser sends it with the form (REQ-165, DEF-041)
  defp form_id(page), do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp post_form(prev, path, params) do
    page = request(:get, "/", %{}, prev)

    request(
      :post,
      path,
      Map.merge(params, %{"_csrf_token" => token(page), "_form" => form_id(page)}),
      page
    )
  end

  defp login(m, p),
    do: post_form(request(:get, "/"), "/login", %{"member" => m, "passphrase" => p})

  defp home(prev), do: request(:get, "/", %{}, prev).resp_body

  defp item_id(path, note),
    do: Enum.find_value(Vault.read!(path).items, fn {id, _} -> id end) |> tap(fn _ -> note end)

  test "success messages and plain-language errors", %{path: path} do
    ana = login("ana", "ana passphrase 1")

    added =
      post_form(ana, "/act/add_item", %{
        "note" => "Rent",
        "amount" => "1200",
        "direction" => "out",
        "frequency" => "monthly"
      })

    assert [loc] = Plug.Conn.get_resp_header(added, "location")
    assert loc == "/"
    # UX-001 R6: the next page states the outcome, once
    shown = request(:get, loc, %{}, added)
    assert shown.resp_body =~ "Added “Rent”."
    refute request(:get, "/", %{}, shown).resp_body =~ "Added “Rent”."

    id = item_id(path, "Rent")
    err = post_form(ana, "/act/relinquish", %{"item" => id})
    assert err.status == 422
    assert err.resp_body =~ "You&#39;re the only owner"
    refute err.resp_body =~ ":sole_owner"
  end

  test "amounts are formatted; names, not ids, in links and proposals", %{path: path} do
    ana = login("ana", "ana passphrase 1")

    post_form(ana, "/act/add_item", %{
      "note" => "Rent",
      "amount" => "1200",
      "direction" => "out",
      "frequency" => "monthly"
    })

    post_form(ana, "/act/add_value", %{"label" => "A safe home"})
    vault = Vault.read!(path)
    {:ok, s} = FindependenceApp.Session.open(vault, "ana", "ana passphrase 1")
    names = Html.names(s.household, "ana")
    rent = Enum.find_value(names, fn {id, n} -> n == "Rent" && id end)
    home_value = Enum.find_value(names, fn {id, n} -> n == "A safe home" && id end)

    post_form(ana, "/act/link", %{"item" => rent, "value" => home_value})
    body = home(ana)
    assert body =~ "−$1,200.00"
    item_page = request(:get, "/items/#{rent}", %{}, ana).resp_body
    assert item_page =~ "A safe home"
    assert item_page =~ ~s(action="/act/unlink")
    refute Regex.replace(~r/<[^>]*>/, item_page, " ") =~ rent
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

    post_form(ana, "/act/add_item", %{
      "note" => "Car loan",
      "amount" => "300",
      "direction" => "out",
      "frequency" => "monthly"
    })

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

  test "delete goes through a confirmation page; leaving through the checklist", %{path: path} do
    ana = login("ana", "ana passphrase 1")

    post_form(ana, "/act/add_item", %{
      "note" => "Old card",
      "amount" => "0",
      "direction" => "in",
      "frequency" => "monthly"
    })

    [id] = Map.keys(Vault.read!(path).items)

    confirm = post_form(ana, "/confirm/delete", %{"item" => id})
    assert confirm.status == 200
    assert confirm.resp_body =~ "Delete “Old card”?"
    assert confirm.resp_body =~ "can&#39;t be undone"
    assert Map.keys(Vault.read!(path).items) == [id]

    post_form(ana, "/act/delete", %{"item" => id})
    assert Vault.read!(path).items == %{}

    # UX-001 R8: the leave checklist is the confirmation; it states the consequence.
    leave = request(:get, "/leave", %{}, ana)
    assert leave.resp_body =~ "This can't be undone."
    assert leave.resp_body =~ ~s(action="/act/leave")
    assert post_form(ana, "/confirm/leave", %{}).status == 404
  end

  test "export page is readable and the saved file is JSON with plain history", %{path: path} do
    ana = login("ana", "ana passphrase 1")

    post_form(ana, "/act/add_item", %{
      "note" => "Savings",
      "amount" => "500",
      "direction" => "in",
      "frequency" => "monthly"
    })

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
                 "attrs" => %{"note" => "Savings", "amount" => 50000, "unit" => "cents"},
                 "history" => ["Created by ana"]
               }
             ]
           } = :json.decode(file.resp_body)

    _ = path
  end

  test "every form field has a label" do
    ana = login("ana", "ana passphrase 1")

    post_form(ana, "/act/add_item", %{
      "note" => "X",
      "amount" => "1",
      "direction" => "in",
      "frequency" => "monthly"
    })

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

    assert Html.format_amount(-1_234_567) == "−$12,345.67"
    assert Html.format_amount(42) == "+$0.42"
  end
end

defmodule FindependenceApp.IdleLockTest do
  @moduledoc "UX-001 R4: the unlock screen explains an idle lock; a discarded action is reported, never replayed."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-idle-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  # Pretend every session was last used longer ago than the idle limit.
  defp age_sessions,
    do:
      Agent.update(
        Sessions,
        &Map.new(&1, fn {k, v} -> {k, %{v | at: v.at - Sessions.idle_ms() - 1}} end)
      )

  defp login do
    first = request(:get, "/")

    request(
      :post,
      "/login",
      %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => token(first)},
      first
    )
  end

  test "an action after the idle limit is not saved, and the unlock screen says so", %{path: path} do
    ana = login()
    page = request(:get, "/", %{}, ana)
    age_sessions()

    resp =
      request(:post, "/act/add_value", %{"label" => "Home", "_csrf_token" => token(page)}, page)

    assert [loc] = Plug.Conn.get_resp_header(resp, "location")
    assert loc == "/?locked=action"
    assert request(:get, loc, %{}, resp).resp_body =~ "Your last action was not saved."
    assert Vault.read!(path).items == %{}
  end

  test "reloading after the idle limit explains the lock without mentioning an action" do
    ana = login()
    age_sessions()
    body = request(:get, "/", %{}, ana).resp_body
    assert body =~ "Locked after 15 minutes without use."
    refute body =~ "last action"
  end

  test "a first visit shows no lock notice" do
    refute request(:get, "/").resp_body =~ "Locked after"
  end
end

defmodule FindependenceApp.ItemFlowTest do
  @moduledoc "UX-001 R1, R6, R7 over HTTP (WI-022)."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-flow-#{System.unique_integer([:positive])}.vault")

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
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  # the page's one-time form token, as a browser sends it with the form (REQ-165, DEF-041)
  defp form_id(page), do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp post_from(prev, page_path, path, params) do
    page = request(:get, page_path, %{}, prev)

    request(
      :post,
      path,
      Map.merge(params, %{"_csrf_token" => token(page), "_form" => form_id(page)}),
      page
    )
  end

  defp login(m, p),
    do: post_from(request(:get, "/"), "/", "/login", %{"member" => m, "passphrase" => p})

  defp add_rent(ana, path) do
    post_from(ana, "/", "/act/add_item", %{
      "note" => "Rent",
      "amount" => "1,450",
      "direction" => "out",
      "frequency" => "monthly"
    })

    [id] = Map.keys(Vault.read!(path).items)
    id
  end

  test "an action on an item page returns to it and states the outcome", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    id = add_rent(ana, path)

    resp =
      post_from(ana, "/items/#{id}", "/act/grant", %{
        "item" => id,
        "member" => "ben",
        "return" => "/items/#{id}"
      })

    assert Plug.Conn.get_resp_header(resp, "location") == ["/items/#{id}"]
    assert request(:get, "/items/#{id}", %{}, resp).resp_body =~ "ben can now see “Rent”."
  end

  test "return addresses other than an item page the member can see go home (no open redirect)",
       %{path: path} do
    ana = login("ana", "ana passphrase 1")
    id = add_rent(ana, path)

    for bad <- [
          "https://evil.example/",
          "//evil.example",
          "/items/../../etc",
          "/items/nope",
          "javascript:alert(1)"
        ] do
      # An action that succeeds, so the return address is actually used.
      resp =
        post_from(ana, "/items/#{id}", "/act/add_item", %{
          "note" => "Extra",
          "amount" => "1",
          "direction" => "in",
          "frequency" => "monthly",
          "return" => bad
        })

      assert resp.status == 303
      assert Plug.Conn.get_resp_header(resp, "location") == ["/"], "#{bad} was followed"
    end
  end

  test "deleting from an item page lands home, and the deleted item's page is not available", %{
    path: path
  } do
    ana = login("ana", "ana passphrase 1")
    id = add_rent(ana, path)

    resp =
      post_from(ana, "/items/#{id}", "/act/delete", %{"item" => id, "return" => "/items/#{id}"})

    assert Plug.Conn.get_resp_header(resp, "location") == ["/"]
    gone = request(:get, "/items/#{id}", %{}, resp)
    assert gone.status == 404
    assert gone.resp_body =~ "isn't available to you"
  end

  test "the header counts what is waiting for you", %{path: path} do
    ben = login("ben", "ben passphrase 2")
    post_from(ben, "/", "/act/add_value", %{"label" => "Holiday"})
    [id] = Map.keys(Vault.read!(path).items)

    post_from(ben, "/items/#{id}", "/act/owners", %{
      "item" => id,
      "owners" => ["ben", "ana"],
      "return" => "/items/#{id}"
    })

    post_from(ben, "/", "/logout", %{})

    ana = login("ana", "ana passphrase 1")
    home = request(:get, "/", %{}, ana).resp_body
    assert home =~ ~s(<a class=badge href="/#waiting">1 waiting for you</a>)
    assert home =~ ~s(id=waiting)
  end
end
