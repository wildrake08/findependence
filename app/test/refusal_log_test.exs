defmodule FindependenceApp.RefusalLogTest do
  @moduledoc "WI-050 (C2): refusals and errors are logged by method, path, status, and reason; never contents."
  use ExUnit.Case, async: false
  import Plug.Test
  import ExUnit.CaptureLog

  alias FindependenceApp.{Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-log-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    page = request(:get, "/")

    ana =
      request(
        :post,
        "/login",
        %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => csrf(page)},
        page
      )

    %{ana: ana}
  end

  defp request(method, path, params \\ %{}, prev \\ nil, host \\ "127.0.0.1") do
    conn = %{conn(method, path, params) | host: host, port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp csrf(page),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last()

  # the page's one-time form token, as a browser sends it with the form (REQ-165, DEF-041)
  defp form_id(page), do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp post(prev, path, params) do
    page = request(:get, "/", %{}, prev)

    request(
      :post,
      path,
      Map.merge(params, %{"_csrf_token" => csrf(page), "_form" => form_id(page)}),
      page
    )
  end

  test "a refused form is logged by method, path, and status, without what was typed", %{ana: ana} do
    log =
      capture_log(fn ->
        resp =
          post(ana, "/act/add_item", %{
            "note" => "Secret therapy bill",
            "amount" => "55,5",
            "direction" => "out",
            "frequency" => "monthly"
          })

        assert resp.status == 422
      end)

    assert log =~ "refused POST /act/add_item 422"
    refute log =~ "Secret therapy bill"
    refute log =~ "55,5"
  end

  test "a refusal by the app's rules carries its reason code", %{ana: ana} do
    log =
      capture_log(fn -> assert post(ana, "/act/consent", %{"proposal" => "7"}).status == 422 end)

    assert log =~ ~r/refused POST \/act\/consent 422 \([a-z_]+\)/
  end

  test "not found, a stale form, and a foreign host are logged; query strings never are", %{
    ana: ana
  } do
    log =
      capture_log(fn ->
        assert request(:get, "/items/nope?extra=98765", %{}, ana).status == 404
        assert request(:get, "/nowhere?rate=12.5").status == 404
        assert request(:post, "/act/add_value", %{"label" => "Private label"}).status == 403
        assert request(:get, "/", %{}, nil, "evil.example").status == 421
      end)

    assert log =~ "refused GET /items/nope 404"
    assert log =~ "refused GET /nowhere 404"
    assert log =~ "refused POST /act/add_value 403"
    assert log =~ "refused GET / 421"
    refute log =~ "98765"
    refute log =~ "12.5"
    refute log =~ "Private label"
  end

  test "an action sent after the session ended is logged, though it redirects", %{ana: ana} do
    page = request(:get, "/", %{}, ana)
    # another browser unlocks, which ends Ana's session on the server
    other = request(:get, "/")

    request(
      :post,
      "/login",
      %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => csrf(other)},
      other
    )

    log =
      capture_log(fn ->
        resp =
          request(
            :post,
            "/act/add_value",
            %{"label" => "Lost label", "_csrf_token" => csrf(page)},
            page
          )

        assert resp.status == 303
      end)

    assert log =~ "refused POST /act/add_value 303 (no_session)"
    refute log =~ "Lost label"
  end

  test "successful requests aren't logged", %{ana: ana} do
    log =
      capture_log(fn ->
        request(:get, "/", %{}, ana)
        post(ana, "/act/add_value", %{"label" => "A safe home"})
      end)

    refute log =~ "refused"
    refute log =~ "A safe home"
  end
end
