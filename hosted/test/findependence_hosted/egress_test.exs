defmodule FindependenceHosted.EgressTest do
  @moduledoc """
  REQ-124 AC-1 as restated (REV-079) for the hosted form, whose egress allowlist holds only its own database
  (REV-098, WI-073, DEF-057): while the running system serves every route, every connect call and host-name
  lookup goes to the configured database's host and port, and nowhere else.

  The system runs in this VM (Repo, Sessions, Limits, the endpoint, and a Bandit listener on loopback) under
  a call trace of every process, on the connect and lookup entry points below. A fresh database connection is
  opened inside the trace, so the allowed destination is seen, not assumed. Every route in the router is
  exercised in process, and some over real HTTP from curl, an OS process outside the trace, so the client's
  own connections are not counted.

  Excluded developer-only tooling, never started by the running system: Mix and Hex (dependency fetching
  and compilation). The planted calls below are to loopback only.
  """
  use FindependenceHostedWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest, only: [live: 2]
  alias FindependenceHosted.{Limits, Repo}
  alias FindependenceHostedWeb.Router

  @moduletag timeout: 120_000

  # Connect and host-name lookup entry points: the inet backend (prim_inet) and the socket backend
  # (socket) under gen_tcp, gen_udp, and gen_sctp; TLS; the resolvers; and the HTTP client. The same list
  # as the local-first form's test (app/test/egress_test.exs).
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

  @pass "a long passphrase 1"

  setup do
    Limits.reset()
    :ok
  end

  test "through every route, the only connections and lookups are to the configured database" do
    allowed = allowlist()

    {calls, requests} =
      traced(fn ->
        fresh_database_connection()
        visit_every_route()
        http_visit()
      end)

    refused = Enum.reject(calls, &allowed?(&1, allowed))
    assert refused == [], "outbound calls not on the allowlist: #{inspect(refused, limit: 20)}"

    # the database was really reached inside the trace, so the allowed calls were seen
    assert Enum.any?(calls, &match?({:connect, _, _, _}, destination(&1)))

    hit = requests |> Enum.map(&route_for/1) |> MapSet.new()
    missing = Enum.reject(routes(), &(&1 in hit))
    assert missing == [], "routes not exercised: #{inspect(missing)}"
  end

  test "a planted connect and a planted name lookup are reported; the database and an address are not" do
    allowed = allowlist()

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
        fresh_database_connection()
      end)

    refused = Enum.reject(calls, &allowed?(&1, allowed))

    assert Enum.any?(refused, &match?({:gen_tcp, :connect, _}, &1))
    assert Enum.any?(refused, &match?({:inet, :getaddr, [~c"localhost" | _]}, &1))
    refute Enum.any?(refused, &match?({:inet, :getaddr, [{127, 0, 0, 1} | _]}, &1))
    assert Enum.any?(calls -- refused, &match?({:connect, _, _, _}, destination(&1)))

    # a planted connect to the database's address on another port is refused too
    [{:connect, :prim_inet, db_ip, _} | _] =
      for c <- calls -- refused,
          match?({:connect, :prim_inet, _, _}, destination(c)),
          do: destination(c)

    refute allowed?({:prim_inet, :connect, [:socket, db_ip, allowed.port + 1, 1_000]}, allowed)
  end

  # --- the allowlist: the configured database's host name, its addresses, and its port

  defp allowlist do
    config = Repo.config()
    host = Keyword.fetch!(config, :hostname)
    {:ok, ips} = :inet.getaddrs(String.to_charlist(host), :inet)
    %{names: [host], ips: ips, port: Keyword.get(config, :port, 5432)}
  end

  defp allowed?(call, allowed) do
    case destination(call) do
      {:connect, _, addr, port} -> port == allowed.port and address_allowed?(addr, allowed)
      {:lookup, name} -> to_string(name) in allowed.names
      :none -> true
      :unknown -> false
    end
  end

  defp address_allowed?(addr, allowed) when is_tuple(addr), do: addr in allowed.ips
  defp address_allowed?(name, allowed), do: to_string(name) in allowed.names

  # Where a traced call goes: {:connect, backend, address or name, port}, {:lookup, name}, :none for an
  # internal step with no destination, or :unknown, which is refused.
  defp destination({:prim_inet, :connect, [_s, addr, port | _]}),
    do: {:connect, :prim_inet, addr, port}

  defp destination({:socket, :connect, [_s, %{addr: addr, port: port} | _]}),
    do: {:connect, :socket, addr, port}

  defp destination({m, :connect, [%{addr: addr, port: port} | _]}), do: {:connect, m, addr, port}

  defp destination({m, :connect, [addr, port | _]}) when is_integer(port),
    do: {:connect, m, addr, port}

  defp destination({:gen_sctp, :connect_init, [_s, addr, port | _]}),
    do: {:connect, :gen_sctp, addr, port}

  defp destination({:inet, f, [name | _]}) when f in [:getaddr, :getaddrs, :gethostbyname] do
    if is_tuple(name), do: :none, else: {:lookup, name}
  end

  defp destination({:inet_gethost_native, :gethostbyname, [name | _]}), do: {:lookup, name}
  defp destination(_), do: :unknown

  # --- the visit

  # Opens a connection of its own with the Repo's settings, as a pool does when it starts or reconnects.
  defp fresh_database_connection do
    config =
      Repo.config() |> Keyword.drop([:pool, :pool_size]) |> Keyword.put(:backoff_type, :stop)

    {:ok, pid} = Postgrex.start_link(config)
    %Postgrex.Result{rows: [[1]]} = Postgrex.query!(pid, "SELECT 1", [])
    GenServer.stop(pid)
  end

  # Every route in process through the endpoint, as a member signs up, starts a household, invites
  # someone, and so on.
  defp visit_every_route do
    conn = build_conn()
    assert html_response(get(conn, ~p"/sign-up"), 200)
    ana = sign_up("ana@example.com")
    key = ana_key(ana)
    assert html_response(get(build_conn(), ~p"/sign-in"), 200)

    assert post(build_conn(), ~p"/sign-in", form("ana@example.com", "wrong passphrase!!")).status ==
             401

    a = sign_in("ana@example.com")
    assert html_response(get(a, ~p"/"), 200)
    a = recycle(post(a, ~p"/household", %{"household" => %{"display_name" => "Ana"}}))
    code_conn = post(a, ~p"/invitations")

    [_, code] =
      Regex.run(~r/id="new-code"[^>]*>\s*([A-Z2-7-]+)\s*</, html_response(code_conn, 200))

    a = recycle(code_conn)
    _ = post(a, ~p"/invitations")

    _ = sign_up("ben@example.com")
    b = sign_in("ben@example.com")

    assert redirected_to(
             post(b, ~p"/join", %{"join" => %{"code" => code, "display_name" => "Ben"}})
           ) == "/"

    # the other code, still open, is withdrawn
    [open] = Repo.all(from i in FindependenceHosted.Schemas.Invitation, where: is_nil(i.used_at))
    assert redirected_to(post(a, ~p"/invitations/#{open.id}/withdraw")) == "/"

    # the domain pages and their forms (WI-075): Ana adds an item, a value, an account with a balance, and a
    # debt; shares, links, and marks; opens every page; asks to delete, and deletes
    form = fn params -> Map.put(params, "_form", FindependenceHosted.Forms.new_token()) end
    assert html_response(get(a, ~p"/household"), 200)

    item =
      post(
        a,
        ~p"/act/add_item",
        form.(%{
          "note" => "Rent",
          "amount" => "1,450",
          "direction" => "out",
          "frequency" => "monthly"
        })
      )

    assert redirected_to(item) == "/"

    pay =
      post(
        a,
        ~p"/act/add_item",
        form.(%{
          "note" => "Pay",
          "amount" => "3,000",
          "direction" => "in",
          "frequency" => "monthly"
        })
      )

    assert redirected_to(pay) == "/"
    _ = post(a, ~p"/act/add_value", form.(%{"label" => "Security", "return" => "/"}))
    acct = post(a, ~p"/act/add_account", form.(%{"label" => "Checking", "type" => "checking"}))
    "/items/" <> acct_id = redirected_to(acct)
    debt = post(a, ~p"/act/add_debt", form.(%{"label" => "Card", "type" => "card"}))
    "/items/" <> debt_id = redirected_to(debt)

    _ =
      post(
        a,
        ~p"/act/add_reading",
        form.(%{
          "item" => acct_id,
          "balance" => "2,000",
          "on" => "2026-09-01",
          "return" => "/items/#{acct_id}"
        })
      )

    s = FindependenceHosted.Tenancy.scope(get(a, "/").assigns.current)

    [rent, pay_id] =
      for n <- ["Rent", "Pay"], do: FindependenceShared.Contract.Helpers.find(s.household, n)

    value =
      Enum.find_value(s.household.items, fn {id, i} ->
        if i.attrs[:label] == "Security", do: id
      end)

    b_id = get(b, "/").assigns.current.membership.id

    for {action, params} <- [
          {"grant", %{"item" => rent, "member" => b_id}},
          {"revoke", %{"item" => rent, "member" => b_id}},
          {"link", %{"item" => rent, "value" => value}},
          {"unlink", %{"item" => rent, "value" => value}},
          {"attach", %{"item" => rent, "account" => acct_id}},
          {"mark", %{"item" => rent, "job" => pay_id}},
          {"unmark", %{"item" => rent, "job" => pay_id}}
        ] do
      conn = post(a, "/act/#{action}", form.(Map.put(params, "return", "/items/#{rent}")))
      assert conn.status in [302, 303], "#{action} answered #{conn.status}"
    end

    for path <- [
          "/",
          "/items/#{rent}",
          "/items/#{value}",
          "/items/#{acct_id}",
          "/items/#{debt_id}",
          "/next-60-days",
          "/ahead",
          "/balances/new"
        ],
        do: assert(html_response(get(a, path), 200), path)

    assert html_response(post(a, ~p"/confirm/delete", %{"item" => rent}), 200)
    _ = post(a, ~p"/act/delete", form.(%{"item" => rent, "return" => "/"}))

    # the rest of the pages (WI-076): plans and a request, goals, set-asides, retirement, export, bring-in, and
    # letting go on the leave checklist
    plan_conn = post(a, ~p"/act/new_plan", form.(%{"name" => "If the pay stops"}))
    "/plans/" <> plan = redirected_to(plan_conn)

    _ =
      post(
        a,
        ~p"/act/plan_step",
        form.(%{
          "plan" => plan,
          "kind" => "add",
          "note" => "Premium",
          "amount" => "600",
          "direction" => "out",
          "frequency" => "monthly",
          "from" => "2026-11"
        })
      )

    _ = post(a, ~p"/act/remove_step", form.(%{"plan" => plan, "n" => "1"}))
    _ = post(a, ~p"/act/share_plan", form.(%{"plan" => plan, "members" => [b_id]}))
    s2 = FindependenceHosted.Tenancy.scope(get(a, "/").assigns.current)
    request = s2.household.proposals |> Map.keys() |> Enum.max()

    for {who, path} <- [
          {a, "/plans"},
          {a, "/plans/#{plan}"},
          {b, "/requests/#{request}"},
          {a, "/goals"},
          {a, "/retirement"},
          {a, "/export"},
          {a, "/bring-in"},
          {a, "/leave"}
        ],
        do: assert(html_response(get(who, path), 200), path)

    assert html_response(post(a, ~p"/confirm/delete_plan", %{"plan" => plan}), 200)
    _ = post(a, ~p"/act/delete_plan", form.(%{"plan" => plan, "return" => "/plans"}))
    _ = post(a, ~p"/act/fund_goal", form.(%{"months" => "3"}))
    _ = post(a, ~p"/act/set_aside", form.(%{"value" => value, "rate" => "5"}))

    _ =
      post(
        a,
        ~p"/act/retirement",
        form.(%{
          "birth_year" => "1970",
          "retire_age" => "67",
          "return" => "4",
          "ss" => "",
          "target" => ""
        })
      )

    file = response(get(a, ~p"/export.json"), 200)
    dir = Path.join(System.tmp_dir!(), "fh-egress-file-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "findependence-export.json")
    File.write!(path, file)

    upload = %Plug.Upload{
      path: path,
      filename: "findependence-export.json",
      content_type: "application/json"
    }

    for last <- ["/act/bring-in/cancel", "/act/bring-in/confirm"] do
      # Ana brings in her own saved file (Ben, who leaves below, must own nothing)
      assert html_response(post(a, ~p"/act/bring-in", form.(%{"file" => upload})), 200)
      assert redirected_to(post(a, last, form.(%{}))) =~ "/"
    end

    File.rm_rf!(dir)

    _ =
      post(a, ~p"/act/let_go", form.(%{"item" => pay_id, "to" => "delete", "return" => "/leave"}))

    # Ben leaves (he owns nothing), signs in again, and deletes his account (WI-074)
    assert html_response(get(b, ~p"/leave"), 200)

    assert redirected_to(post(b, ~p"/leave", %{"_form" => FindependenceHosted.Forms.new_token()})) ==
             "/sign-in"

    b = sign_in("ben@example.com")
    assert html_response(get(b, ~p"/account/delete"), 200)

    assert redirected_to(post(b, ~p"/account/delete", %{"account" => %{"passphrase" => @pass}})) ==
             "/sign-up"

    assert html_response(get(a, ~p"/passphrase"), 200)
    new_pass = "a changed passphrase"

    _ =
      post(a, ~p"/passphrase", %{
        "account" => %{
          "current" => @pass,
          "passphrase" => new_pass,
          "passphrase_confirmation" => new_pass
        }
      })

    _ = post(a, ~p"/sign-out")

    assert html_response(get(build_conn(), ~p"/recover"), 200)

    _ =
      post(build_conn(), ~p"/recover", %{
        "account" => %{
          "email" => "ana@example.com",
          "recovery_key" => key,
          "passphrase" => "a recovered passphrase",
          "passphrase_confirmation" => "a recovered passphrase"
        }
      })

    {:ok, _view, _html} = live(build_conn(), ~p"/specimen")

    for path <- [~p"/health/live", ~p"/health/ready"],
        do: assert(get(build_conn(), path).status == 200)
  end

  defp form(email, pass), do: %{"account" => %{"email" => email, "passphrase" => pass}}

  defp sign_up(email) do
    post(build_conn(), ~p"/sign-up", %{
      "account" => %{
        "email" => email,
        "passphrase" => @pass,
        "passphrase_confirmation" => @pass,
        "disclosure" => "true"
      }
    })
  end

  defp ana_key(conn) do
    [_, key] = Regex.run(~r/id="recovery-key"[^>]*>\s*([A-Z2-7-]+)\s*</, html_response(conn, 200))
    key
  end

  defp sign_in(email) do
    conn = post(build_conn(), ~p"/sign-in", form(email, @pass))
    assert redirected_to(conn) == "/"
    recycle(conn)
  end

  # Real HTTP over loopback: the endpoint behind a Bandit listener, used with curl.
  defp http_visit do
    dir = Path.join(System.tmp_dir!(), "fh-egress-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    jar = Path.join(dir, "jar")
    port = free_port()

    start_supervised!(
      Supervisor.child_spec(
        {Bandit,
         plug: FindependenceHostedWeb.Endpoint, scheme: :http, ip: {127, 0, 0, 1}, port: port},
        id: :egress_listener
      )
    )

    _ = sign_up("cy@example.com")
    {page, 200} = curl(jar, ["http://127.0.0.1:#{port}/sign-in"])
    [_, token] = Regex.run(~r/name="_csrf_token"[^>]*value="([^"]+)"/, page)

    {_, 302} =
      curl(jar, [
        "--data-urlencode",
        "_csrf_token=#{token}",
        "--data-urlencode",
        "account[email]=cy@example.com",
        "--data-urlencode",
        "account[passphrase]=#{@pass}",
        "http://127.0.0.1:#{port}/sign-in"
      ])

    {home, 200} = curl(jar, ["http://127.0.0.1:#{port}/"])
    assert home =~ "Start a household"

    stop_supervised!(:egress_listener)
    File.rm_rf!(dir)
  end

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

  # --- the trace

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

    Code.ensure_loaded!(Router)
    1 = :erlang.trace_pattern({Router, :call, 2}, true, [:global])
    :erlang.trace(:all, true, [:call, {:tracer, collector}])

    try do
      fun.()
    after
      :erlang.trace(:all, false, [:call])
      Enum.each(patterns, &:erlang.trace_pattern(&1, false, [:global]))
      :erlang.trace_pattern({Router, :call, 2}, false, [:global])
    end

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
      {:trace, _pid, :call, {Router, :call, [%Plug.Conn{method: m, request_path: p} | _]}} ->
        collect(calls, [{m, p} | requests])

      {:trace, _pid, :call, {m, f, args}} ->
        if outbound?(m, f),
          do: collect([{m, f, args} | calls], requests),
          else: collect(calls, requests)

      {:done, from} ->
        send(from, {:collected, Enum.reverse(calls), Enum.reverse(requests)})
    end
  end

  defp outbound?(m, f), do: {m, f} in @traced or {m, :_} in @traced

  # The router's routes as {method, pattern}.
  defp routes do
    for r <- Router.__routes__(), do: {r.verb |> to_string() |> String.upcase(), r.path}
  end

  defp route_for({method, path}) do
    case Phoenix.Router.route_info(Router, method, path, "www.example.com") do
      %{route: route} -> {method, route}
      :error -> {method, path}
    end
  end
end
