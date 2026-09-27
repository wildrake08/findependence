defmodule FindependenceApp.HttpActionsTest do
  @moduledoc """
  WI-032: web paths the coverage run found unexercised. Agreeing, withdrawing, and unlinking over
  HTTP; malformed request numbers; an unknown action; errors on item pages; a lost action after a
  session is replaced; and messages that had never been rendered.
  """
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-http-#{System.unique_integer([:positive])}.vault")

    Vault.create(
      [{"ana", "ana pass 1"}, {"ben", "ben pass 2"}, {"cy", "cy pass 3"}, {"dan", "dan pass 4"}],
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

  defp post(prev, path, params) do
    page = request(:get, "/", %{}, prev)
    request(:post, path, Map.put(params, "_csrf_token", token(page)), page)
  end

  defp login(m),
    do:
      post(request(:get, "/"), "/login", %{
        "member" => m,
        "passphrase" => "#{m} pass #{%{"ana" => 1, "ben" => 2, "cy" => 3, "dan" => 4}[m]}"
      })

  defp household(path) do
    {:ok, s} = Session.open(Vault.read!(path), "ana", "ana pass 1")
    s.household
  end

  defp follow(resp) do
    [loc] = Plug.Conn.get_resp_header(resp, "location")
    request(:get, loc, %{}, resp).resp_body
  end

  defp add(who, note),
    do:
      post(who, "/act/add_item", %{
        "note" => note,
        "amount" => "1",
        "direction" => "out",
        "frequency" => "monthly"
      })

  defp id_of(path, note),
    do:
      Enum.find_value(household(path).items, fn {id, i} ->
        (i.attrs[:note] || i.attrs[:label]) == note && id
      end)

  test "agreeing over HTTP: a partial agreement says who is still needed, the last one applies it",
       %{path: path} do
    ana = login("ana")
    add(ana, "Rent")
    rent = id_of(path, "Rent")
    post(ana, "/act/owners", %{"item" => rent, "owners" => ["ana", "ben", "cy"]})
    assert household(path).items[rent].owners == MapSet.new(["ana", "ben", "cy"])

    # sharing a three-owner item with dan needs ben and cy too
    post(ana, "/act/grant", %{"item" => rent, "member" => "dan"})
    [pid] = Map.keys(household(path).proposals)

    ben = login("ben")
    resp = post(ben, "/act/consent", %{"proposal" => "#{pid}"})
    assert resp.status == 303
    assert follow(resp) =~ "You agreed. Still waiting for cy."
    refute "dan" in household(path).items[rent].grantees

    cy = login("cy")
    resp = post(cy, "/act/consent", %{"proposal" => "#{pid}"})
    assert follow(resp) =~ "You agreed, and the change has been made."
    assert "dan" in household(path).items[rent].grantees
    assert household(path).proposals == %{}
  end

  test "withdrawing over HTTP removes the request and changes nothing else", %{path: path} do
    ana = login("ana")
    post(ana, "/act/add_value", %{"label" => "Holiday"})
    hol = id_of(path, "Holiday")
    post(ana, "/act/owners", %{"item" => hol, "owners" => ["ana", "ben"]})
    [pid] = Map.keys(household(path).proposals)

    resp = post(ana, "/act/withdraw", %{"proposal" => "#{pid}"})
    assert follow(resp) =~ "Withdrawn. Nothing was changed."
    assert household(path).proposals == %{}
    assert household(path).items[hol].owners == MapSet.new(["ana"])
  end

  test "unlinking over HTTP removes only that link", %{path: path} do
    ana = login("ana")
    add(ana, "Rent")
    post(ana, "/act/add_value", %{"label" => "Home"})
    post(ana, "/act/add_value", %{"label" => "Calm"})
    {rent, home, calm} = {id_of(path, "Rent"), id_of(path, "Home"), id_of(path, "Calm")}
    post(ana, "/act/link", %{"item" => rent, "value" => home})
    post(ana, "/act/link", %{"item" => rent, "value" => calm})

    resp =
      post(ana, "/act/unlink", %{"item" => rent, "value" => home, "return" => "/items/#{rent}"})

    assert Plug.Conn.get_resp_header(resp, "location") == ["/items/#{rent}"]
    assert follow(resp) =~ "Unlinked “Rent” from “Home”."
    assert Findependence.Alignment.links(household(path), "ana") == [{rent, calm}]
  end

  test "request numbers must be whole numbers; anything else is refused and changes nothing", %{
    path: path
  } do
    ana = login("ana")
    post(ana, "/act/add_value", %{"label" => "Holiday"})
    post(ana, "/act/owners", %{"item" => id_of(path, "Holiday"), "owners" => ["ana", "ben"]})
    [pid] = Map.keys(household(path).proposals)
    ben = login("ben")
    before = household(path)

    for bad <- ["abc", "#{pid}abc", "#{pid}.0", "-#{pid}", "", "0", " #{pid}"] do
      resp = post(ben, "/act/consent", %{"proposal" => bad})
      assert resp.status == 422, "#{inspect(bad)} was accepted"
      assert resp.resp_body =~ "That isn&#39;t available to you."
    end

    assert household(path) == before
  end

  test "an unknown action is refused plainly and changes nothing", %{path: path} do
    ana = login("ana")
    before = household(path)
    resp = post(ana, "/act/frobnicate", %{"item" => "x"})
    assert resp.status == 422
    assert resp.resp_body =~ "That didn&#39;t work."
    assert household(path) == before
  end

  test "an error from an item page is shown on that page", %{path: path} do
    ana = login("ana")
    add(ana, "Rent")
    rent = id_of(path, "Rent")

    resp =
      post(ana, "/act/revoke", %{"item" => rent, "member" => "ben", "return" => "/items/#{rent}"})

    assert resp.status == 422
    assert resp.resp_body =~ "<h2>Rent</h2>"
    assert resp.resp_body =~ "They can&#39;t see it now, so there is nothing to stop."
  end

  test "a member whose session was replaced is told their last action was not saved", %{
    path: path
  } do
    ana = login("ana")
    page = request(:get, "/", %{}, ana)
    _ben = login("ben")

    resp =
      request(
        :post,
        "/act/add_item",
        %{
          "note" => "Lost",
          "amount" => "1",
          "direction" => "out",
          "frequency" => "monthly",
          "_csrf_token" => token(page)
        },
        page
      )

    assert Plug.Conn.get_resp_header(resp, "location") == ["/?locked=replaced"]
    body = request(:get, "/?locked=replaced", %{}, resp).resp_body
    assert body =~ "You were locked out, so your last action was not saved."
    # the notice doesn't say who unlocked instead
    [notice] = Regex.run(~r/<p class="msg info" role="status">[^<]*<\/p>/, body)
    refute notice =~ "ben"
    assert household(path).items == %{}
  end

  test "history says when someone who could see an item left; the leave page counts what others share",
       %{path: path} do
    ana = login("ana")
    add(ana, "Rent")
    add(ana, "Car")

    for note <- ["Rent", "Car"],
        do: post(ana, "/act/grant", %{"item" => id_of(path, note), "member" => "dan"})

    dan = login("dan")

    assert request(:get, "/leave", %{}, dan).resp_body =~
             "You'll stop seeing the 2 items and values others share with you."

    post(dan, "/act/leave", %{"return" => "/leave"})

    ana = login("ana")

    assert request(:get, "/items/#{id_of(path, "Rent")}", %{}, ana).resp_body =~
             "dan left the household"
  end
end
