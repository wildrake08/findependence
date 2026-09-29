defmodule FindependenceApp.EgressTest do
  @moduledoc """
  REQ-124 AC-1 as restated (REV-079) for the local-first form, whose egress allowlist is empty (WI-067,
  DEF-057): the running system makes no connect call and no host-name lookup during a member's whole visit.

  The system runs in this VM (Store, Sessions, and the Bandit listener on loopback) under a call trace of
  every process, on the connect and lookup entry points below. It is exercised through every route in the
  router: the accessibility capture scripts' states through the router, plus real HTTP from curl, which is
  an OS process outside the trace, so the client's own connections are not counted.

  Excluded developer-only tooling, never started by the running system: Mix and Hex (dependency fetching
  and compilation). The test makes no connection or lookup beyond the loopback planted calls below.
  """
  use ExUnit.Case, async: false

  alias FindependenceApp.{Sessions, Store, Vault, Web}

  @moduletag timeout: 300_000

  # Connect and host-name lookup entry points: the inet backend (prim_inet) and the socket backend
  # (socket) under gen_tcp, gen_udp, and gen_sctp; TLS; the resolvers; and the HTTP client.
  @traced [
    {:prim_inet, :connect},
    {:socket, :connect},
    {:gen_tcp, :connect},
    {:gen_udp, :connect},
    {:gen_sctp, :connect},
    {:gen_sctp, :connect_init},
    {:ssl, :connect},
    {:inet, :gethostbyname},
    {:inet, :getaddr},
    {:inet, :getaddrs},
    {:inet, :gethostbyaddr},
    {:inet_res, :_},
    {:inet_gethost_native, :_},
    {:httpc, :_}
  ]

  @scripts ~w(capture capture_v02 capture_v03 capture_v04 capture_v05 capture_v06 capture_v07)

  test "the running system makes no connection and no name lookup through every route" do
    {calls, requests} =
      traced(fn ->
        http_visit()
        Enum.each(@scripts, &run_capture_script/1)
      end)

    assert calls == [], "outbound calls with an empty allowlist: #{inspect(calls, limit: 20)}"

    hit = requests |> Enum.map(&route_for/1) |> MapSet.new()
    missing = Enum.reject(routes(), &(&1 in hit))
    assert missing == [], "routes not exercised: #{inspect(missing)}"
  end

  test "the trace reports a planted connect and a planted name lookup, and not an address" do
    {calls, _} =
      traced(fn ->
        {:ok, listener} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
        {:ok, port} = :inet.port(listener)

        Task.async(fn ->
          {:ok, s} = :gen_tcp.connect({127, 0, 0, 1}, port, [], 1_000)
          :gen_tcp.close(s)
          # an address is not a name: no lookup happens, so it must not be reported
          {:ok, _} = :inet.getaddr({127, 0, 0, 1}, :inet)
          # resolved from the hosts file, not the network
          _ = :inet.getaddr(~c"localhost", :inet)
        end)
        |> Task.await()

        :gen_tcp.close(listener)
      end)

    assert Enum.any?(calls, &match?({:gen_tcp, :connect, _}, &1))
    assert Enum.any?(calls, &match?({:inet, :getaddr, [~c"localhost" | _]}, &1))
    refute Enum.any?(calls, &match?({:inet, :getaddr, [{127, 0, 0, 1} | _]}, &1))
  end

  # Runs `fun` with every process traced; returns the connect and lookup calls, and the requests the
  # router saw as {method, path}.
  defp traced(fun) do
    collector = spawn(fn -> collect([], []) end)

    patterns =
      for {m, f} <- @traced, Code.ensure_loaded?(m) do
        spec = if f == :_, do: {m, :_, :_}, else: {m, f, :_}
        :erlang.trace_pattern(spec, true, [:global])
        spec
      end

    # a trace pattern applies only to a loaded module
    Code.ensure_loaded!(Web)
    1 = :erlang.trace_pattern({Web, :call, 2}, true, [:global])
    :erlang.trace(:all, true, [:call, {:tracer, collector}])

    try do
      fun.()
    after
      :erlang.trace(:all, false, [:call])
      Enum.each(patterns, &:erlang.trace_pattern(&1, false, [:global]))
      :erlang.trace_pattern({Web, :call, 2}, false, [:global])
    end

    # every trace message generated so far reaches the collector before :done does
    ref = :erlang.trace_delivered(:all)

    receive do
      {:trace_delivered, :all, ^ref} -> :ok
    after
      10_000 -> flunk("trace messages were not delivered")
    end

    send(collector, {:done, self()})

    receive do
      {:collected, calls, requests} -> {calls, requests}
    after
      10_000 -> flunk("trace collector did not answer")
    end
  end

  defp collect(calls, requests) do
    receive do
      {:trace, _pid, :call, {Web, :call, [%Plug.Conn{method: m, request_path: p} | _]}} ->
        collect(calls, [{m, p} | requests])

      {:trace, _pid, :call, {m, f, args}} ->
        # only the entry points traced here; another test may leave other patterns on
        if outbound?(m, f) and not lookup_of_an_address?(m, f, args),
          do: collect([{m, f, args} | calls], requests),
          else: collect(calls, requests)

      {:done, from} ->
        send(from, {:collected, Enum.reverse(calls), Enum.reverse(requests)})
    end
  end

  defp outbound?(m, f), do: {m, f} in @traced or {m, :_} in @traced

  # :inet.getaddr/getaddrs/gethostbyname on an IP tuple converts it without any lookup
  defp lookup_of_an_address?(:inet, f, [addr | _])
       when f in [:getaddr, :getaddrs, :gethostbyname],
       do: is_tuple(addr)

  defp lookup_of_an_address?(_, _, _), do: false

  # The router's routes, in order, as {method, pattern}.
  defp routes do
    source = File.read!("lib/findependence_app/web.ex")

    for [_, method, path] <- Regex.scan(~r/^  (get|post) "([^"]+)"/m, source),
        do: {String.upcase(method), path}
  end

  # The first route in router order that a request matches, as Plug.Router picks it.
  defp route_for({method, path}) do
    Enum.find(routes(), {method, path}, fn {m, pattern} ->
      m == method and Regex.match?(route_regex(pattern), path)
    end)
  end

  defp route_regex(pattern) do
    body = pattern |> String.split("/") |> Enum.map_join("/", &segment/1)
    Regex.compile!("^" <> body <> "$")
  end

  defp segment(":" <> _), do: "[^/]+"
  defp segment(s), do: Regex.escape(s)

  # Real HTTP over loopback: the listener as a household runs it, used with curl.
  defp http_visit do
    dir = Path.join(System.tmp_dir!(), "fv-egress-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "household.vault")
    jar = Path.join(dir, "jar")

    Vault.create([{"ana", "ana passphrase 1"}, {"ben", "ben passphrase 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    port = free_port()
    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    start_supervised!(Supervisor.child_spec({Web, port: port}, id: :egress_listener))

    {_, 200} = get(port, jar, "/")
    {_, 401} = post(port, jar, "/login", [{"member", "ana"}, {"passphrase", "wrong passphrase"}])
    {_, 303} = post(port, jar, "/login", [{"member", "ana"}, {"passphrase", "ana passphrase 1"}])
    {_, 200} = get(port, jar, "/")
    {_, 200} = get(port, jar, "/export.json")

    # routes the capture scripts do not reach; each must answer, not crash
    for {path, fields} <- [
          {"/act/add_account", [{"type", "checking"}, {"label", "Egress checking"}]},
          {"/act/add_debt", [{"type", "card"}, {"label", "Egress card"}]},
          {"/act/new_plan", [{"name", "Egress plan"}]},
          {"/act/share_plan", [{"plan", "no-such-plan"}, {"members", "ben"}]},
          {"/act/fund_goal", [{"months", "3"}]},
          {"/act/set_aside", [{"value", "no-such-value"}, {"rate", "5"}]},
          {"/act/bring-in/cancel", []}
        ] do
      {_, status} = post(port, jar, path, fields)
      assert status in 200..499, "#{path} answered #{status}"
    end

    {_, 303} = post(port, jar, "/logout", [])

    stop_supervised!(:egress_listener)
    stop_supervised!(Sessions)
    stop_supervised!(Store)
    File.rm_rf!(dir)
  end

  # Each capture script builds its own household and drives its states through the router; it starts
  # Store and Sessions itself, so they are stopped before the next one.
  defp run_capture_script(name) do
    dir = Path.join(System.tmp_dir!(), "fv-egress-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    today = Application.get_env(:findependence_app, :today)
    argv = System.argv()
    System.put_env("ITEM_PAGES", "1")
    System.argv([dir])

    try do
      Code.eval_file(Path.expand("../project/assurance/accessibility/#{name}.exs", File.cwd!()))
    after
      for server <- [Sessions, Store], Process.whereis(server), do: GenServer.stop(server)
      System.argv(argv)
      System.delete_env("ITEM_PAGES")
      restore_today(today)
      File.rm_rf!(dir)
    end
  end

  defp restore_today(nil), do: Application.delete_env(:findependence_app, :today)
  defp restore_today(d), do: Application.put_env(:findependence_app, :today, d)

  defp free_port do
    {:ok, s} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(s)
    :gen_tcp.close(s)
    port
  end

  # {body, status}; `jar` keeps cookies between calls, as a browser would.
  defp curl(jar, args) do
    {out, _} =
      System.cmd("curl", ["-s", "-w", "\n%{http_code}", "-b", jar, "-c", jar] ++ args,
        stderr_to_stdout: true
      )

    [status | rest] = out |> String.split("\n") |> Enum.reverse()
    {rest |> Enum.reverse() |> Enum.join("\n"), String.to_integer(status)}
  end

  defp get(port, jar, path), do: curl(jar, ["http://127.0.0.1:#{port}#{path}"])

  defp post(port, jar, path, fields) do
    {page, 200} = get(port, jar, "/")
    [_, token] = Regex.run(~r/name=_csrf_token value="([^"]+)"/, page)
    form = Regex.run(~r/name=_form value="([^"]+)"/, page)
    fields = if form, do: [{"_form", List.last(form)} | fields], else: fields

    data =
      Enum.flat_map([{"_csrf_token", token} | fields], fn {k, v} ->
        ["--data-urlencode", "#{k}=#{v}"]
      end)

    curl(jar, data ++ ["http://127.0.0.1:#{port}#{path}"])
  end
end
