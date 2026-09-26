defmodule FindependenceApp.WebTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias FindependenceApp.{Sessions, Store, Vault, Web}

  @port 4848

  setup do
    path = Path.join(System.tmp_dir!(), "fv-web-#{System.unique_integer([:positive])}.vault")

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

  defp request(method, path, params \\ %{}, cookies \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: @port}
    conn = if cookies, do: recycle_cookies(conn, cookies), else: conn
    Web.call(conn, Web.init(port: @port))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  # Loads the page to get a CSRF token, then posts with it; returns the response.
  defp post_form(prev, path, params) do
    page = request(:get, "/", %{}, prev)
    request(:post, path, Map.put(params, "_csrf_token", token(page)), page)
  end

  defp login(member, pass) do
    first = request(:get, "/")
    post_form(first, "/login", %{"member" => member, "passphrase" => pass})
  end

  describe "REQ-123" do
    test "binds only the loopback address" do
      assert Web.bind_ip() == {127, 0, 0, 1}
      %{start: {_, _, [opts]}} = Web.child_spec(port: @port)
      assert Keyword.get(opts, :ip) == {127, 0, 0, 1}
    end

    test "rejects a foreign Host header (DNS rebinding)" do
      conn =
        %{conn(:get, "/") | host: "evil.example", port: @port} |> Web.call(Web.init(port: @port))

      assert conn.status == 421
      conn = %{conn(:get, "/") | host: "127.0.0.1", port: 9999} |> Web.call(Web.init(port: @port))
      assert conn.status == 421
      assert request(:get, "/").status == 200
    end

    test "rejects a state-changing request without a CSRF token" do
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        request(:post, "/login", %{"member" => "ana", "passphrase" => "ana passphrase 1"})
      end
    end

    test "a wrong passphrase is refused" do
      assert login("ana", "wrong").status == 401
      assert Sessions.count() == 0
    end

    test "logout discards the unlocked session" do
      conn = login("ana", "ana passphrase 1")
      assert conn.status == 303
      assert Sessions.count() == 1
      post_form(conn, "/logout", %{})
      assert Sessions.count() == 0
    end

    test "a session locks after 15 minutes idle" do
      {:ok, s} = Store.open("ana", "ana passphrase 1")
      t0 = 1_000_000
      token = Sessions.put(s, t0)
      assert {:ok, _} = Sessions.fetch(token, t0 + Sessions.idle_ms())
      assert :locked = Sessions.fetch(token, t0 + 2 * Sessions.idle_ms() + 1)
      assert Sessions.count() == 0
    end
  end

  describe "REQ-124" do
    test "every response forbids remote loads, and pages contain no remote URLs" do
      conn = request(:get, "/")
      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'none'"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      refute conn.resp_body =~ ~r{https?://}
    end

    test "no HTTP client or outbound-connection code in the app or its dependencies" do
      forbidden =
        ~w(:httpc :gen_tcp.connect :ssl.connect Finch HTTPoison Tesla Mint.HTTP Req.get Req.post :hackney)

      sources = Path.wildcard("lib/**/*.ex") |> Enum.map(&File.read!/1) |> Enum.join()
      for f <- forbidden, do: refute(String.contains?(sources, f), "found #{f}")

      deps = Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0))
      for d <- [:finch, :req, :mint, :httpoison, :tesla, :hackney], do: refute(d in deps)
    end
  end

  test "end to end: add, share, and view through HTTP; the file holds no plaintext", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    home = request(:get, "/", %{}, ana)
    assert home.resp_body =~ "Your items"

    added = post_form(ana, "/act/add_item", %{"note" => "MARK-dentist", "amount" => "-120"})
    assert added.status == 303
    [item_id] = Map.keys(Vault.read!(path).items)

    shared = post_form(ana, "/act/grant", %{"item" => item_id, "member" => "ben"})
    assert shared.status == 303
    post_form(ana, "/logout", %{})

    ben = login("ben", "ben passphrase 2")
    assert request(:get, "/", %{}, ben).resp_body =~ "MARK-dentist"
    refute String.contains?(File.read!(path), "MARK-dentist")

    escaped = post_form(ben, "/act/add_value", %{"label" => "<script>x</script>"})
    assert escaped.status == 303
    body = request(:get, "/", %{}, ben).resp_body
    refute body =~ "<script>x</script>"
    assert body =~ "&lt;script&gt;x&lt;/script&gt;"
  end
end
