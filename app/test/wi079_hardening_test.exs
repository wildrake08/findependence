defmodule FindependenceApp.WI079HardeningTest do
  @moduledoc """
  WI-079: the security assessment's fixes to the local form's web layer and store. FND-05: crash reports
  print no household information and a malformed sign-in doesn't crash; fields of a shape no form sends are
  refused. FND-15: the session cookie (and the flash in it) is encrypted. FND-16: a refused Host gets the
  security headers. FND-17: a file that can no longer be read leaves the last good copy in place. And the form
  token is renewed at sign-in.
  """
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Plug.Test

  alias FindependenceApp.{LogRedaction, Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-wi079-#{System.unique_integer([:positive])}.vault")

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

  defp request(method, path, params \\ %{}, prev \\ nil, host \\ "127.0.0.1") do
    conn = %{conn(method, path, params) | host: host, port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp csrf(page),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last()

  defp form_token(page),
    do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp signed_in do
    first = request(:get, "/")

    ana =
      request(
        :post,
        "/login",
        %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => csrf(first)},
        first
      )

    {first, ana}
  end

  test "a field sent as a list or map where text is expected is refused with 400 and changes nothing",
       %{path: path} do
    {_, ana} = signed_in()
    home = request(:get, "/", %{}, ana)
    before = File.read!(path)

    for params <- [
          %{"label" => ["x"]},
          %{"label" => %{"a" => "b"}},
          %{"note" => ["Therapy copay"], "amount" => "12"},
          %{"owners" => [%{"a" => "b"}]}
        ] do
      conn =
        request(
          :post,
          "/act/add_value",
          Map.merge(params, %{"_csrf_token" => csrf(home), "_form" => form_token(home)}),
          home
        )

      assert conn.status == 400
    end

    assert File.read!(path) == before
  end

  test "a sign-in without its fields is refused like a wrong passphrase, and logs no passphrase" do
    first = request(:get, "/")

    log =
      capture_log(fn ->
        conn =
          request(
            :post,
            "/login",
            %{"passphrase" => "MY-REAL-PASSPHRASE-123", "_csrf_token" => csrf(first)},
            first
          )

        assert conn.status == 401
      end)

    refute log =~ "MY-REAL-PASSPHRASE-123"
  end

  test "a crash report's details are withheld from the log" do
    LogRedaction.install()

    on_exit(fn ->
      :logger.remove_primary_filter(:findependence_withhold_crash_details)
    end)

    log =
      capture_log(fn ->
        {:ok, pid} = Agent.start(fn -> %{note: "Therapy copay SECRETNOTE"} end)
        ref = Process.monitor(pid)
        Agent.cast(pid, fn state -> raise ArgumentError, "boom #{inspect(state)}" end)
        assert_receive {:DOWN, ^ref, _, _, _}
        Process.sleep(50)
      end)

    refute log =~ "SECRETNOTE"
    assert log =~ "details are withheld"
  end

  test "the session cookie is encrypted: a flash naming an item isn't readable in it" do
    {_, ana} = signed_in()
    home = request(:get, "/", %{}, ana)

    added =
      request(
        :post,
        "/act/add_value",
        %{"label" => "SECRETVALUE", "_csrf_token" => csrf(home), "_form" => form_token(home)},
        home
      )

    cookie = added.resp_cookies["_fv"].value
    refute cookie =~ "SECRETVALUE"

    # every part of the cookie, decoded, holds no trace of the text
    for part <- String.split(cookie, "."),
        {:ok, bytes} <- [Base.url_decode64(part, padding: false)] do
      assert :binary.match(bytes, "SECRETVALUE") == :nomatch
    end
  end

  test "a request for another host is refused with the security headers" do
    conn = request(:get, "/", %{}, nil, "evil.example")
    assert conn.status == 421
    assert [csp] = Plug.Conn.get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'none'"
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "the form token is renewed at sign-in" do
    {first, ana} = signed_in()
    home = request(:get, "/", %{}, ana)
    refute csrf(home) == csrf(first)
  end

  test "a file that can't be read keeps the last good copy and refuses changes", %{path: path} do
    {_, ana} = signed_in()
    good = Store.vault()

    File.write!(path, "not a household file")

    log =
      capture_log(fn ->
        assert Store.vault() == good

        {:ok, s} = Store.open("ana", "ana passphrase 1")

        assert {:error, :file_unreadable, _} =
                 Store.apply(s, &Findependence.Alignment.add_value(&1, "ana", "v1", "A value"))
      end)

    assert log =~ "can't be read"
    assert request(:get, "/", %{}, ana).status == 200
  end
end
