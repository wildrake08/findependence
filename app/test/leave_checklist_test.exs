defmodule FindependenceApp.LeaveChecklistTest do
  @moduledoc "UX-001 R8 (WI-023): leaving from one page, in at most N+2 actions."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}

  @port 4848

  setup do
    path = Path.join(System.tmp_dir!(), "fv-leave-#{System.unique_integer([:positive])}.vault")

    Vault.create(
      [{"ana", "ana passphrase 1"}, {"ben", "ben passphrase 2"}, {"cy", "cy passphrase 3"}],
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

  # Posts from the leave page, as a member would; returns the response.
  defp post_leave(prev, path, params) do
    page = request(:get, "/leave", %{}, prev)
    request(:post, path, Map.merge(params, %{"_csrf_token" => token(page)}), page)
  end

  defp login(m, p) do
    page = request(:get, "/")

    request(
      :post,
      "/login",
      %{
        "member" => m,
        "passphrase" => p,
        "_csrf_token" => token(page)
      },
      page
    )
  end

  # Vault contents are encrypted; read names through a member's session.
  defp id_of(path, note) do
    {:ok, s} = FindependenceApp.Session.open(Vault.read!(path), "ana", "ana passphrase 1")

    Enum.find_value(FindependenceApp.Web.Html.names(s.household, "ana"), fn {id, n} ->
      n == note && id
    end)
  end

  defp household(path) do
    {:ok, s} = FindependenceApp.Session.open(Vault.read!(path), "ben", "ben passphrase 2")
    s.household
  end

  defp add(ana, note),
    do:
      post_leave(ana, "/act/add_item", %{
        "note" => note,
        "amount" => "1",
        "direction" => "out",
        "frequency" => "monthly"
      })

  test "home always offers the way to leave, even while owning things", %{path: _} do
    ana = login("ana", "ana passphrase 1")
    add(ana, "Rent")

    assert request(:get, "/", %{}, ana).resp_body =~
             ~s(<a class="button-link" href="/leave">Leave the household…</a>)
  end

  test "the checklist offers the export first, lists each owned item with its action, and no leave button yet",
       %{path: path} do
    ana = login("ana", "ana passphrase 1")
    add(ana, "Rent")
    add(ana, "Car")
    car = id_of(path, "Car")
    post_leave(ana, "/act/owners", %{"item" => car, "owners" => ["ana", "ben"]})
    # a sole owner's change of owners applies at once
    assert household(path).items[car].owners == MapSet.new(["ana", "ben"])

    body = request(:get, "/leave", %{}, ana).resp_body
    [before_list, _] = String.split(body, "What you own (2)", parts: 2)
    assert before_list =~ ~s(href="/export")
    # joint: stop owning, naming who keeps it
    assert body =~ "Owned with ben, who will keep it."
    assert body =~ ~s(aria-label="Stop owning Car")
    # sole: an explicit choice between named people and delete, nothing preselected
    assert body =~
             ~s(<option value="">Choose…</option><option value="give:ben">Give it to ben</option><option value="give:cy">Give it to cy</option><option value="delete">)

    refute body =~ "selected"
    refute body =~ ~s(action="/act/leave")
    assert body =~ "You can leave once you don't own anything."
  end

  test "a member owning N items leaves from this page in N+2 actions", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    add(ana, "Rent")
    add(ana, "Car")
    add(ana, "Phone")
    rent = id_of(path, "Rent")
    car = id_of(path, "Car")
    phone = id_of(path, "Phone")
    post_leave(ana, "/act/owners", %{"item" => car, "owners" => ["ana", "ben"]})
    # a sole owner's change of owners applies at once
    assert household(path).items[car].owners == MapSet.new(["ana", "ben"])

    # N = 3 owned: export, three resolutions, leave.
    actions = [
      fn -> request(:get, "/export.json", %{}, ana) end,
      fn ->
        post_leave(ana, "/act/let_go", %{"item" => rent, "to" => "give:ben", "return" => "/leave"})
      end,
      fn -> post_leave(ana, "/act/relinquish", %{"item" => car, "return" => "/leave"}) end,
      fn ->
        post_leave(ana, "/act/let_go", %{"item" => phone, "to" => "delete", "return" => "/leave"})
      end,
      fn -> post_leave(ana, "/act/leave", %{"return" => "/leave"}) end
    ]

    results = Enum.map(actions, & &1.())
    assert length(actions) == 3 + 2
    assert hd(results).status == 200

    for r <- Enum.slice(results, 1..3) do
      assert Plug.Conn.get_resp_header(r, "location") == ["/leave"]
    end

    h = household(path)
    refute "ana" in h.members
    assert h.items[rent].owners == MapSet.new(["ben"])
    assert h.items[car].owners == MapSet.new(["ben"])
    refute Map.has_key?(h.items, phone)
    assert Plug.Conn.get_resp_header(List.last(results), "location") == ["/"]
  end

  test "each action returns to the checklist with its outcome", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    add(ana, "Rent")
    rent = id_of(path, "Rent")
    r = post_leave(ana, "/act/let_go", %{"item" => rent, "to" => "give:cy", "return" => "/leave"})
    next = request(:get, "/leave", %{}, r).resp_body
    assert next =~ "“Rent” is now owned by cy."
    assert next =~ "What you own (0)"
    assert next =~ ~s(action="/act/leave")
  end

  test "no choice made: nothing changes, and the checklist says so", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    add(ana, "Rent")
    rent = id_of(path, "Rent")
    before = household(path).items
    r = post_leave(ana, "/act/let_go", %{"item" => rent, "to" => "", "return" => "/leave"})
    assert r.status == 422
    assert r.resp_body =~ "Choose what should happen to it first."
    assert r.resp_body =~ "What you own (1)"
    assert household(path).items == before
  end

  test "giving away a value waits for the new owner, with a way to withdraw", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    post_leave(ana, "/act/add_value", %{"label" => "Holiday"})
    hol = id_of(path, "Holiday")
    body = request(:get, "/leave", %{}, ana).resp_body
    assert body =~ "Give it to ben (waits for ben to agree)"

    post_leave(ana, "/act/let_go", %{"item" => hol, "to" => "give:ben", "return" => "/leave"})
    body = request(:get, "/leave", %{}, ana).resp_body
    assert body =~ "Waiting for ben to agree."
    assert body =~ ~s(aria-label="Withdraw the request for Holiday")
    refute body =~ ~s(action="/act/leave")
  end
end
