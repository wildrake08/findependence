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
      conn = request(:post, "/login", %{"member" => "ana", "passphrase" => "ana passphrase 1"})

      # DEF-035: still refused and nothing happens, but with a page that says so (not an empty 403)
      assert conn.status == 403
      assert conn.resp_body =~ "This page was out of date, so nothing was saved."
      assert conn.resp_body =~ ~s(<a href="/">Go to the home page</a>)
      assert Sessions.count() == 0
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
      assert {:locked, :expired} = Sessions.fetch(token, t0 + 2 * Sessions.idle_ms() + 1)
      assert :locked = Sessions.fetch(token, t0 + 2 * Sessions.idle_ms() + 2)
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

      # DEF-055 (WI-062): read every dependency's own source, including the core, not only the names
      # of direct dependencies. Calls, not type names: :ssl.connection_info() in a spec isn't a connection.
      for {dep, path} <- Mix.Project.deps_paths(),
          {file, call} <- network_calls(path),
          do: flunk("#{dep} calls #{call} in #{Path.relative_to(file, path)}")
    end

    test "the dependency scan finds a planted call" do
      dir = Path.join(System.tmp_dir!(), "fv-scan-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "lib"))
      File.mkdir_p!(Path.join(dir, "src"))
      File.write!(Path.join(dir, "lib/a.ex"), "@spec x :: :ssl.connection_info()\n")
      assert network_calls(dir) == []

      File.write!(
        Path.join(dir, "lib/b.ex"),
        "def f, do: :httpc.request(:get, {~c\"u\", []}, [], [])\n"
      )

      File.write!(Path.join(dir, "src/c.erl"), "f() -> gen_tcp:connect(\"h\", 1, []).\n")
      assert [{_, ":httpc."}, {_, "gen_tcp:connect("}] = Enum.sort(network_calls(dir))
      File.rm_rf!(dir)
    end
  end

  # Elixir and Erlang spellings of outbound connections, name lookups, and HTTP clients.
  @network_calls ~w(:httpc. :gen_tcp.connect( :ssl.connect( :inet.getaddr :inet.gethostbyname :inet_res.
                    Mint.HTTP. Finch. :hackney. Req.get Req.post Req.request HTTPoison. Tesla.
                    httpc: gen_tcp:connect( ssl:connect( inet:getaddr inet:gethostbyname inet_res: hackney:)

  defp network_calls(root) do
    for file <- Path.wildcard(Path.join(root, "{lib,src}/**/*.{ex,erl}")),
        source = File.read!(file),
        call <- @network_calls,
        String.contains?(source, call),
        do: {file, call}
  end

  test "end to end: add, share, and view through HTTP; the file holds no plaintext", %{path: path} do
    ana = login("ana", "ana passphrase 1")
    home = request(:get, "/", %{}, ana)
    assert home.resp_body =~ "Your items"

    added =
      post_form(ana, "/act/add_item", %{
        "note" => "MARK-dentist",
        "amount" => "120",
        "direction" => "out",
        "frequency" => "monthly"
      })

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

defmodule FindependenceApp.ContrastTest do
  @moduledoc "UX-001 R5: field boundaries meet WCAG 1.4.11 (at least 3:1 for non-text contrast)."
  use ExUnit.Case, async: true

  defp lum(hex) do
    <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = String.trim_leading(hex, "#")

    [r, g, b]
    |> Enum.map(&(String.to_integer(&1, 16) / 255))
    |> Enum.map(fn c ->
      if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
    end)
    |> then(fn [r, g, b] -> 0.2126 * r + 0.7152 * g + 0.0722 * b end)
  end

  defp ratio(a, b) do
    [l1, l2] = Enum.sort([lum(a), lum(b)], :desc)
    (l1 + 0.05) / (l2 + 0.05)
  end

  test "input and select borders are at least 3:1 against the card and page backgrounds" do
    css = File.read!("lib/findependence_app/web.ex")

    # UX-003: the border is the --control-border token
    assert css =~ ~r/input,select\{[^}]*border:1px solid var\(--control-border\)/

    [border] = Regex.run(~r/--control-border:(#[0-9a-f]{6})/, css, capture: :all_but_first)

    assert ratio(border, "#ffffff") >= 3.0
    assert ratio(border, "#f6f7f9") >= 3.0
  end
end
