defmodule FindependenceApp.WI059RepeatTest do
  @moduledoc "WI-059 (DEF-051, REQ-165): a form already saved is recognised as a repeat in the member's later sessions."
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
    path = Path.join(System.tmp_dir!(), "fv-wi059r-#{System.unique_integer([:positive])}.vault")

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

  defp login(member, pass) do
    first = request(:get, "/")

    request(
      :post,
      "/login",
      %{"member" => member, "passphrase" => pass, "_csrf_token" => csrf(first)},
      first
    )
  end

  defp rents(path),
    do: household(path).items |> Map.values() |> Enum.count(&(&1.attrs[:note] == "Rent"))

  # Ana saves "Rent" from home; returns the page it was sent from and the form's fields.
  defp save_rent(ana) do
    page = request(:get, "/", %{}, ana)

    fields = %{
      "note" => "Rent",
      "amount" => "1,450",
      "direction" => "out",
      "frequency" => "monthly",
      "_csrf_token" => csrf(page),
      "_form" => form_token(page)
    }

    saved = request(:post, "/act/add_item", fields, page)
    {saved, fields}
  end

  test "after locking and unlocking again, resending a saved form says it was already saved",
       %{path: path, ana: ana} do
    {saved, fields} = save_rent(ana)
    request(:post, "/logout", %{"_csrf_token" => fields["_csrf_token"]}, saved)
    again = login("ana", "ana passphrase 1")
    # the old page's form, sent from the same browser after unlocking again
    resent = request(:post, "/act/add_item", fields, again)
    assert follow(resent) =~ "That was already saved."
    assert rents(path) == 1
  end

  test "after the idle lock and the sweep, resending a saved form says it was already saved",
       %{path: path, ana: ana} do
    {saved, fields} = save_rent(ana)
    age_sessions()
    Sessions.sweep()
    resent = request(:post, "/act/add_item", fields, saved)
    assert loc(resent) == "/?locked=saved"
    assert follow(resent) =~ "Locked after 15 minutes without use. That was already saved."
    assert rents(path) == 1
  end

  test "after the idle lock, before the sweep, resending a saved form says it was already saved",
       %{path: path, ana: ana} do
    {saved, fields} = save_rent(ana)
    age_sessions()
    resent = request(:post, "/act/add_item", fields, saved)
    assert loc(resent) == "/?locked=saved"
    assert rents(path) == 1
  end

  test "a form that was never saved, sent after the idle lock, is still told it wasn't saved",
       %{path: path, ana: ana} do
    page = request(:get, "/", %{}, ana)
    age_sessions()

    resent =
      request(
        :post,
        "/act/add_value",
        %{"label" => "Home", "_csrf_token" => csrf(page), "_form" => form_token(page)},
        page
      )

    assert loc(resent) == "/?locked=action"
    assert household(path).items == %{}
  end

  test "after another member unlocks, an old form says nothing about what the first member saved",
       %{path: path, ana: ana} do
    {_saved, fields} = save_rent(ana)
    ben = login("ben", "ben passphrase 2")
    resent = request(:post, "/act/add_item", fields, ben)
    # WI-032: Ben is told only that the page was out of date, nothing about Ana's form
    assert resent.status == 403
    refute resent.resp_body =~ "already saved"
    assert rents(path) == 1
  end

  test "a second click on Leave that arrives after the member left says it was already done",
       %{ana: ana} do
    page = request(:get, "/leave", %{}, ana)
    fields = %{"_csrf_token" => csrf(page), "_form" => form_token(page)}
    left = request(:post, "/act/leave", fields, page)
    assert loc(left) == "/"
    again = request(:post, "/act/leave", fields, page)
    assert loc(again) == "/?locked=left"
    assert follow(again) =~ "You have left the household. That was already done."
  end
end
