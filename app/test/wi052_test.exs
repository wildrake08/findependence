defmodule FindependenceApp.WI052Test do
  @moduledoc "WI-052: DEF-039 (REQ-123, keys discarded at 15 minutes idle) and DEF-041 (REQ-165, a form changes the household at most once)."
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}
  alias FindependenceApp.Web.Html
  alias Mix.Tasks.Findependence.Demo

  @today ~D[2026-09-27]

  setup do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-wi052-#{System.unique_integer([:positive])}.vault")

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

  # Pretend every live session was last used longer ago than the idle limit.
  defp age_sessions,
    do:
      Agent.update(
        Sessions,
        &Map.new(&1, fn {k, v} -> {k, %{v | at: v.at - Sessions.idle_ms() - 1}} end)
      )

  defp entries, do: Agent.get(Sessions, &Map.values/1)

  test "DEF-039: the sweep leaves an idle session with nothing but a marker", %{ana: ana} do
    page = request(:get, "/", %{}, ana)
    assert [%{session: _}] = entries()
    age_sessions()
    Sessions.sweep()
    assert [marker] = entries()
    assert Map.keys(marker) |> Enum.sort() == [:at, :expired]
    # the next request still says the app locked itself, and saves nothing
    resp =
      request(
        :post,
        "/act/add_value",
        %{"label" => "Home", "_csrf_token" => csrf(page), "_form" => form_token(page)},
        page
      )

    assert loc(resp) == "/?locked=action"
    assert follow(resp) =~ "Locked after 15 minutes without use. Your last action was not saved."
    assert entries() == []
  end

  test "DEF-039: a live session is left alone by the sweep", %{ana: ana} do
    Sessions.sweep()
    assert request(:get, "/", %{}, ana).resp_body =~ "Lock"
    assert [%{session: _}] = entries()
  end

  test "DEF-039: the sweep runs by itself, with no request" do
    {:ok, pid} = Sessions.start_link(name: :wi052_sessions, sweep_ms: 20)

    {:ok, s} =
      Session.open(
        Vault.create([{"x", "x passphrase 12"}], iterations: 1_000, unsafe_test: true),
        "x",
        "x passphrase 12"
      )

    Sessions.put(s, System.monotonic_time(:millisecond) - Sessions.idle_ms() - 1, :wi052_sessions)
    Process.sleep(200)
    assert [%{expired: true} = marker] = Agent.get(pid, &Map.values/1)
    refute Map.has_key?(marker, :session)
  end

  test "DEF-041: a form resent after 70 later forms changes nothing and says so", %{
    path: path,
    ana: ana
  } do
    page = request(:get, "/", %{}, ana)

    rent = %{
      "note" => "Rent",
      "amount" => "1,450",
      "direction" => "out",
      "frequency" => "monthly",
      "_csrf_token" => csrf(page),
      "_form" => form_token(page)
    }

    first = request(:post, "/act/add_item", rent, page)

    last =
      Enum.reduce(1..70, first, fn i, prev ->
        p = request(:get, "/", %{}, prev)

        request(
          :post,
          "/act/add_value",
          %{"label" => "V#{i}", "_csrf_token" => csrf(p), "_form" => form_token(p)},
          p
        )
      end)

    again = request(:post, "/act/add_item", rent, last)
    assert follow(again) =~ "That was already saved."
    assert household(path).items |> Map.values() |> Enum.count(&(&1.attrs[:note] == "Rent")) == 1
  end

  test "DEF-041: a household-changing request without a form token is refused and changes nothing",
       %{path: path, ana: ana} do
    page = request(:get, "/", %{}, ana)

    gym = %{
      "note" => "Gym",
      "amount" => "45",
      "direction" => "out",
      "frequency" => "monthly",
      "_csrf_token" => csrf(page)
    }

    log =
      capture_log(fn ->
        resp = request(:post, "/act/add_item", gym, page)
        assert resp.status == 403
        assert resp.resp_body =~ "That wasn't saved"
        assert request(:post, "/act/add_item", Map.put(gym, "_form", ""), page).status == 403
      end)

    assert log =~ "refused POST /act/add_item 403 (no_form_token)"
    assert household(path).items |> Map.values() |> Enum.count(&(&1.attrs[:note] == "Gym")) == 0
    # the session is untouched: the same member carries on
    assert request(:get, "/", %{}, ana).resp_body =~ "Lock"
  end

  test "DEF-041: after the idle limit, a request without a form token still gets the idle notice",
       %{
         ana: ana
       } do
    page = request(:get, "/", %{}, ana)
    age_sessions()

    resp =
      request(:post, "/act/add_value", %{"label" => "Home", "_csrf_token" => csrf(page)}, page)

    assert loc(resp) == "/?locked=action"
  end

  test "DEF-041: without a session, a request without a form token is refused as locked, as before" do
    first = request(:get, "/")

    resp =
      request(:post, "/act/add_value", %{"label" => "Home", "_csrf_token" => csrf(first)}, first)

    assert resp.status == 303
    assert loc(resp) == "/?locked=replaced"
  end
end
