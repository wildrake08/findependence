defmodule FindependenceApp.WI088CoolingWebTest do
  @moduledoc """
  REQ-201, REQ-202 (CP-030 option A, WI-088) through the local form's real pages: the outcome says when a change
  takes effect, the waiting change shows it with a way to cancel, someone asked to own an item who agreed can take
  it back, and a page an owner opens after the window applies it. The clock is fixed and moved by the test.
  """
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn, only: [get_resp_header: 2]

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  @wait 72 * 3600

  setup do
    path = Path.join(System.tmp_dir!(), "fv-cool-#{System.unique_integer([:positive])}.vault")

    [{"ana", "ana pass 1"}, {"ben", "ben pass 2"}, {"cy", "cy pass 3"}]
    |> Vault.create(iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)

    Application.put_env(:findependence_shared, :cooling_seconds, @wait)
    Application.put_env(:findependence_shared, :now, 1_900_000_000)

    on_exit(fn ->
      Application.put_env(:findependence_shared, :cooling_seconds, 0)
      Application.delete_env(:findependence_shared, :now)
      File.rm(path)
    end)

    %{path: path}
  end

  defp pass(s),
    do:
      Application.put_env(
        :findependence_shared,
        :now,
        Application.fetch_env!(:findependence_shared, :now) + s
      )

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(c), do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, c.resp_body) |> List.last()
  defp form_id(c), do: Regex.run(~r/name=_form value="([^"]+)"/, c.resp_body) |> List.last()

  defp post(prev, path, params) do
    page = request(:get, "/", %{}, prev)

    request(
      :post,
      path,
      Map.merge(params, %{"_csrf_token" => token(page), "_form" => form_id(page)}),
      page
    )
  end

  defp login(m),
    do:
      post(request(:get, "/"), "/login", %{
        "member" => m,
        "passphrase" => "#{m} pass #{%{"ana" => 1, "ben" => 2, "cy" => 3}[m]}"
      })

  defp follow(resp) do
    [loc] = get_resp_header(resp, "location")
    request(:get, loc, %{}, resp).resp_body
  end

  defp household(path, m) do
    {:ok, s} =
      Session.open(Vault.read!(path), m, "#{m} pass #{%{"ana" => 1, "ben" => 2, "cy" => 3}[m]}")

    s.household
  end

  defp rent(path) do
    Enum.find_value(household(path, "ana").items, fn {id, i} ->
      i.attrs[:note] == "Flat rent" && id
    end)
  end

  test "a share says when it takes effect; the page an owner opens after the window applies it",
       %{path: path} do
    ana = login("ana")

    post(ana, "/act/add_item", %{
      "note" => "Flat rent",
      "amount" => "1450",
      "direction" => "out",
      "frequency" => "monthly"
    })

    id = rent(path)
    resp = post(ana, "/act/grant", %{"item" => id, "member" => "ben"})
    assert follow(resp) =~ "will be shared with ben on"

    page = request(:get, "/items/#{id}", %{}, ana).resp_body
    assert page =~ "Everyone needed has agreed. Takes effect on"
    assert page =~ "Withdraw"

    ben = login("ben")
    refute request(:get, "/", %{}, ben).resp_body =~ "Flat rent"

    pass(@wait)
    # ben's own page doesn't apply it: only an owner's session can seal the key
    refute request(:get, "/", %{}, ben).resp_body =~ "Flat rent"
    ana = login("ana")
    _ = request(:get, "/", %{}, ana)
    ben = login("ben")
    assert request(:get, "/", %{}, ben).resp_body =~ "Flat rent"
  end

  test "someone asked to own an item who agreed sees Take back my agreement, and it works", %{
    path: path
  } do
    ana = login("ana")

    post(ana, "/act/add_item", %{
      "note" => "Flat rent",
      "amount" => "1450",
      "direction" => "out",
      "frequency" => "monthly"
    })

    id = rent(path)
    post(ana, "/act/owners", %{"item" => id, "owners" => ["ana", "ben", "cy"]})
    pass(@wait)
    _ = request(:get, "/", %{}, login("ana"))

    ben = login("ben")
    [pid] = Map.keys(Vault.read!(path).proposals)
    post(ben, "/act/consent", %{"proposal" => "#{pid}"})
    home = request(:get, "/", %{}, ben).resp_body
    assert home =~ "Take back my agreement"

    resp = post(ben, "/act/retract", %{"proposal" => "#{pid}"})
    assert follow(resp) =~ "You took back your agreement. Nothing was changed."
    refute "ben" in Vault.read!(path).proposals[pid].consents
  end

  test "a deletion waits; the leave page lets its owner leave at once", %{path: path} do
    ben = login("ben")

    post(ben, "/act/add_item", %{
      "note" => "Gym",
      "amount" => "40",
      "direction" => "out",
      "frequency" => "monthly"
    })

    gym =
      Enum.find_value(household(path, "ben").items, fn {id, i} ->
        i.attrs[:note] == "Gym" && id
      end)

    resp = post(ben, "/act/let_go", %{"item" => gym, "to" => "delete", "return" => "/leave"})
    leave = follow(resp)
    assert leave =~ "will be deleted on"
    assert leave =~ "Deleted when you leave, or on"
    assert leave =~ ~s(action="/act/leave")

    post(ben, "/act/leave", %{"return" => "/leave"})
    refute Map.has_key?(Vault.read!(path).items, gym)
  end
end
