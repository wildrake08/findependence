defmodule FindependenceApp.VVF05BTest do
  @moduledoc """
  WI-057 (VV-001 F-05/F-08, batch B): acceptance criteria that no earlier test asserted, for REQ-118,
  REQ-119, REQ-122, REQ-123, REQ-124, REQ-129, REQ-133, REQ-165, REQ-166, and REQ-170. Criteria and
  interpretations are in project/assurance/vv/acceptance-b.yaml.
  """
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Plug.Test

  alias FindependenceApp.{Crypto, Session, Sessions, Store, Vault, Web}
  alias Findependence.{Alignment, Balances, Exit, Household, Plans}

  @today ~D[2026-09-27]
  @pass %{"ana" => "ana passphrase 1", "ben" => "ben passphrase 2", "cy" => "cy passphrase 3"}

  setup do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-vvb-#{System.unique_integer([:positive])}.vault")

    Vault.create(Enum.map(["ana", "ben", "cy"], &{&1, @pass[&1]}),
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  # ---------------------------------------------------------------------------
  # HTTP helpers, as in web_test.exs, ux004_test.exs, and wi052_test.exs

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp csrf(page),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last()

  defp form_token(page),
    do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp tokens(page), do: %{"_csrf_token" => csrf(page), "_form" => form_token(page)}
  defp loc(resp), do: resp |> Plug.Conn.get_resp_header("location") |> List.first()
  defp follow(resp), do: request(:get, loc(resp), %{}, resp).resp_body

  # a form from a freshly loaded home page
  defp post(prev, path, params) do
    page = request(:get, "/", %{}, prev)
    request(:post, path, Map.merge(params, tokens(page)), page)
  end

  defp login(member, prev \\ nil),
    do:
      post(request(:get, "/", %{}, prev), "/login", %{
        "member" => member,
        "passphrase" => @pass[member]
      })

  defp household(path, m \\ "ana") do
    {:ok, s} = Session.open(Vault.read!(path), m, @pass[m])
    s.household
  end

  defp id_of(path, name, m \\ "ana"),
    do:
      household(path, m).items
      |> Map.values()
      |> Enum.find_value(&((&1.attrs[:note] == name or &1.attrs[:label] == name) && &1.id))

  defp plan_id(path, name),
    do: Enum.find_value(household(path).plans["ana"], fn {id, p} -> p.name == name && id end)

  # ---------------------------------------------------------------------------
  # Vault-level helpers, as in crypto_properties_test.exs and vault_test.exs

  @opts [iterations: 1_000, unsafe_test: true]

  defp vault, do: Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)

  defp act(v, m, fun) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
      {:error, _} = e -> flunk("#{m}: #{inspect(e)}")
    end
  end

  defp session(v, m) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)
    s
  end

  defp file_bytes(v) do
    path =
      Path.join(System.tmp_dir!(), "fv-vvb-bytes-#{System.unique_integer([:positive])}.vault")

    Vault.write!(v, path)
    bytes = File.read!(path)
    File.rm(path)
    bytes
  end

  defp strip(<<131, rest::binary>>), do: rest

  # Can `m` open the item key of `id` with their own secrets, from the file alone?
  defp opens_item?(v, m, id) do
    s = session(v, m)
    sealed = v.items[id].keys[m]

    sealed != nil and
      match?({:ok, _}, Crypto.open(s.pub, s.priv, sealed, Vault.aad(v.hid, {:item_key, id, m})))
  end

  # Can `m` open ledger entry `e` of `id` with their own secrets, from the file alone?
  defp opens_entry?(v, m, id, e) do
    s = session(v, m)
    sealed = e.keys[m]

    sealed != nil and
      match?(
        {:ok, _},
        Crypto.open(s.pub, s.priv, sealed, Vault.aad(v.hid, {:entry_key, id, e.seq, m}))
      )
  end

  defp entry_readers(v, id), do: Enum.map(v.items[id].ledger, &(Map.keys(&1.keys) |> Enum.sort()))

  # ---------------------------------------------------------------------------

  describe "REQ-118" do
    # the response with its one-time tokens blanked (they are random on every page)
    defp shape(conn) do
      body =
        conn.resp_body
        |> String.replace(~r/name=_csrf_token value="[^"]+"/, "name=_csrf_token value=X")
        |> String.replace(~r/name=_form value="[^"]+"/, "name=_form value=X")

      headers = for {k, v} <- conn.resp_headers, k != "set-cookie", do: {k, v}
      {conn.status, Enum.sort(headers), conn.resp_cookies |> Map.keys() |> Enum.sort(), body}
    end

    test "a wrong passphrase reveals nothing: every failure, for a member or not, looks the same" do
      attempts = [
        {"ana", "wrong"},
        {"ana", ""},
        {"ana", @pass["ben"]},
        {"ana", @pass["ana"] <> " "},
        {"zed", "wrong"},
        {"zed", @pass["ana"]}
      ]

      results =
        for {m, p} <- attempts do
          first = request(:get, "/")

          {resp, log} =
            with_log(fn -> post(first, "/login", %{"member" => m, "passphrase" => p}) end)

          {shape(resp), log |> String.replace(~r/^.*\[warning\] /m, "") |> String.trim()}
        end

      [{{status, _, _, body}, _} = one | _] = results
      assert status == 401
      assert body =~ "That name and passphrase don&#39;t match."
      assert Enum.all?(results, &(&1 == one)), "responses differ: #{inspect(Enum.uniq(results))}"
      assert Sessions.count() == 0
    end
  end

  test "REQ-119: an owner who relinquishes, or is removed by agreement, loses the item key" do
    v =
      vault()
      |> act("ana", &Household.add_item(&1, "ana", "i1", %{note: "x", amount: 5}))
      |> act("ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "ben"]))

    assert opens_item?(v, "ben", "i1")
    v = act(v, "ben", &Household.relinquish(&1, "ben", "i1"))
    refute Map.has_key?(v.items["i1"].keys, "ben")
    assert session(v, "ben").household.items["i1"].attrs == %{}

    v = act(v, "ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "cy"]))
    assert opens_item?(v, "cy", "i1")
    v = act(v, "ana", &Household.propose_owners(&1, "ana", "i1", ["ana"]))
    [pid] = Map.keys(v.proposals)
    v = act(v, "cy", &Household.consent(&1, "cy", pid))
    assert Map.keys(v.items["i1"].keys) == ["ana"]
    refute opens_item?(v, "cy", "i1")
  end

  test "REQ-122: kinds, account and debt types, every kind of history entry, and plan names stay out of the file" do
    v =
      vault()
      |> act("ana", &Balances.add_account(&1, "ana", "x1", "MARK-acct", :retirement_401k))
      |> act("ana", &Balances.add_debt(&1, "ana", "x2", "MARK-debt", :heloc))
      |> act(
        "ana",
        &Balances.add_reading(&1, "ana", "x1", %{on: "2032-03-04", balance: 13_579_246})
      )
      |> act(
        "ana",
        &Household.add_item(&1, "ana", "i1", %{
          note: "MARK-note",
          amount: -24_680,
          unit: :cents,
          frequency: {:every, 3, :month},
          on: "2033-05-06"
        })
      )
      |> act("ana", &Alignment.add_value(&1, "ana", "v1", "MARK-value"))
      |> act("ana", &Alignment.link(&1, "ana", "i1", "v1"))
      |> act("ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
      |> act("ana", &Household.revoke_grant(&1, "ana", "i1", "ben"))
      |> act("ana", &Household.propose_owners(&1, "ana", "x1", ["ana", "ben"]))
      |> act("ben", &Household.relinquish(&1, "ben", "x1"))
      |> act("ana", &Household.propose_grant(&1, "ana", "x2", "cy"))
      |> act("cy", &Exit.leave(&1, "cy"))
      |> act("ana", &Plans.new_plan(&1, "ana", "p1", "MARK-plan"))
      |> act("ana", &Plans.propose_shared(&1, "ana", "p1", "sp1", ["ben"]))

    events =
      Enum.map(session(v, "ana").household.ledger |> Map.values() |> List.flatten(), & &1.event)

    for e <- [
          :created,
          :granted,
          :grant_revoked,
          :owners_changed,
          :owner_relinquished,
          :grantee_departed,
          :reading_added
        ],
        do: assert(e in events, "no #{e} entry was made")

    bytes = file_bytes(v)

    for marker <-
          ~w(MARK- retirement_401k heloc account debt kind label note frequency every month 2032-03-04 2033-05-06 created granted grant_revoked owners_changed owner_relinquished grantee_departed reading_added steps),
        do: assert(:binary.match(bytes, marker) == :nomatch, "#{marker} is in the file")

    for term <- [13_579_246, -24_680, {:every, 3, :month}],
        do: assert(:binary.match(bytes, strip(:erlang.term_to_binary(term))) == :nomatch)
  end

  # ---------------------------------------------------------------------------

  describe "REQ-123" do
    # every route that accepts a POST, as the router declares it
    defp declared_posts do
      src = File.read!("lib/findependence_app/web.ex")

      literal =
        Regex.scan(~r/^\s*post "([^"]+)"/m, src, capture: :all_but_first) |> List.flatten()

      [_, confirm] = Regex.run(~r/post "\/confirm\/:action" when action in \[([^\]]*)\]/, src)
      confirm = Regex.scan(~r/"(\w+)"/, confirm, capture: :all_but_first) |> List.flatten()

      [_, block] = Regex.run(~r/post "\/act\/:action" do(.*?)act\(conn, s, action, op\)/s, src)
      actions = Regex.scan(~r/^\s+"(\w+)" ->/m, block, capture: :all_but_first) |> List.flatten()

      (literal -- ["/confirm/:action", "/act/:action"]) ++
        Enum.map(confirm, &("/confirm/" <> &1)) ++ Enum.map(Enum.uniq(actions), &("/act/" <> &1))
    end

    @posts %{
      "/login" => %{"member" => "ana", "passphrase" => "ana passphrase 1"},
      "/logout" => %{},
      "/act/add_item" => %{
        "note" => "Gym",
        "amount" => "45",
        "direction" => "out",
        "frequency" => "monthly"
      },
      "/act/add_value" => %{"label" => "Calm"},
      "/act/add_account" => %{"label" => "Savings", "type" => "savings"},
      "/act/add_debt" => %{"label" => "Loan", "type" => "loan"},
      "/act/add_reading" => %{"item" => :acct, "balance" => "10", "on" => "2026-09-27"},
      "/act/grant" => %{"item" => :item, "member" => "ben"},
      "/act/revoke" => %{"item" => :item, "member" => "ben"},
      "/act/owners" => %{"item" => :item, "owners" => ["ana", "ben"]},
      "/act/consent" => %{"proposal" => "1"},
      "/act/withdraw" => %{"proposal" => "1"},
      "/act/relinquish" => %{"item" => :item},
      "/act/delete" => %{"item" => :item},
      "/act/let_go" => %{"item" => :item, "to" => "delete"},
      "/act/link" => %{"item" => :item, "value" => :value},
      "/act/unlink" => %{"item" => :item, "value" => :value},
      "/act/attach" => %{"item" => :item, "account" => :acct},
      "/act/remove_step" => %{"plan" => :plan, "n" => "1"},
      "/act/delete_plan" => %{"plan" => :plan},
      "/act/mark" => %{"item" => :item, "job" => :item},
      "/act/unmark" => %{"item" => :item, "job" => :item},
      "/act/leave" => %{},
      "/act/new_plan" => %{"name" => "Plan B"},
      "/act/share_plan" => %{"plan" => :plan, "members" => ["ben"]},
      "/act/plan_step" => %{
        "plan" => :plan,
        "kind" => "add",
        "note" => "Rent",
        "amount" => "10",
        "direction" => "out",
        "frequency" => "monthly",
        "from" => "2026-10"
      },
      "/act/fund_goal" => %{"months" => "3"},
      "/act/set_aside" => %{"value" => :value, "rate" => "10"},
      "/act/retirement" => %{"birth_year" => "1970", "retire_age" => "65", "return" => "5"},
      "/act/bring-in" => %{"file" => :upload},
      "/act/bring-in/confirm" => %{},
      "/act/bring-in/cancel" => %{},
      "/confirm/delete" => %{"item" => :item},
      "/confirm/relinquish" => %{"item" => :item},
      "/confirm/delete_plan" => %{"plan" => :plan}
    }

    test "every state-changing request needs a valid CSRF token: each POST route refuses without one",
         %{path: path} do
      # the list below is every POST route the router has, and no more
      assert Enum.sort(declared_posts()) == Enum.sort(Map.keys(@posts))

      ana = login("ana")
      post(ana, "/act/add_item", @posts["/act/add_item"] |> Map.put("note", "Rent"))
      post(ana, "/act/add_value", %{"label" => "Home"})
      post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"})
      post(ana, "/act/new_plan", %{"name" => "If pay stops"})

      upload = Path.join(System.tmp_dir!(), "fv-vvb-#{System.unique_integer([:positive])}.json")
      File.write!(upload, request(:get, "/export.json", %{}, ana).resp_body)
      on_exit(fn -> File.rm(upload) end)

      ids = %{
        item: id_of(path, "Rent"),
        value: id_of(path, "Home"),
        acct: id_of(path, "Checking"),
        plan: plan_id(path, "If pay stops"),
        upload: %Plug.Upload{path: upload, filename: "x.json", content_type: "application/json"}
      }

      assert Enum.all?(Map.values(ids), & &1)
      # someone else's page gives a well-formed token that isn't this session's
      foreign = csrf(request(:get, "/"))

      # the positive control: with this session's token, the same kind of request is saved
      page = request(:get, "/", %{}, ana)
      before = File.read!(path)

      assert request(:post, "/act/add_value", Map.merge(%{"label" => "Ok"}, tokens(page)), page).status ==
               303

      refute File.read!(path) == before

      for {route, params} <- Enum.sort(@posts),
          bad <- [:missing, :foreign, :garbled] do
        params = Map.new(params, fn {k, v} -> {k, if(is_atom(v), do: ids[v], else: v)} end)
        page = request(:get, "/", %{}, ana)

        token =
          case bad do
            :missing -> %{}
            :foreign -> %{"_csrf_token" => foreign}
            :garbled -> %{"_csrf_token" => String.reverse(csrf(page))}
          end

        before = File.read!(path)

        params = Map.merge(params, Map.put(token, "_form", form_token(page)))
        {resp, _log} = with_log(fn -> request(:post, route, params, page) end)

        assert resp.status == 403, "#{route} (#{bad}) answered #{resp.status}"
        assert resp.resp_body =~ "That wasn't saved", "#{route} (#{bad})"
        assert File.read!(path) == before, "#{route} (#{bad}) changed the file"
        # the session is untouched: still unlocked, as the same member
        assert request(:get, "/", %{}, ana).resp_body =~ "<span class=who>ana</span>"
        assert Sessions.count() == 1
      end

      # and a POST to an address the router doesn't know is refused the same way first
      assert request(:post, "/act/no-such-thing", %{"_form" => "f"}, ana).status == 403
    end

    test "no request other than a POST changes the household: every GET route leaves the file as it was",
         %{path: path} do
      ana = login("ana")
      post(ana, "/act/add_item", %{"note" => "Rent", "amount" => "5", "frequency" => "monthly"})
      post(ana, "/act/add_value", %{"label" => "Home"})
      post(ana, "/act/owners", %{"item" => id_of(path, "Home"), "owners" => ["ana", "ben"]})
      post(ana, "/act/new_plan", %{"name" => "If pay stops"})
      [pid] = Map.keys(household(path).proposals)

      gets = %{
        "/" => "/",
        "/items/:id" => "/items/#{id_of(path, "Rent")}",
        "/next-60-days" => "/next-60-days",
        "/ahead" => "/ahead",
        "/plans" => "/plans",
        "/plans/:id" => "/plans/#{plan_id(path, "If pay stops")}",
        "/requests/:id" => "/requests/#{pid}",
        "/retirement" => "/retirement",
        "/bring-in" => "/bring-in",
        "/goals" => "/goals",
        "/balances/new" => "/balances/new",
        "/leave" => "/leave",
        "/export" => "/export",
        "/export.json" => "/export.json"
      }

      src = File.read!("lib/findependence_app/web.ex")

      declared =
        Regex.scan(~r/^\s*get "([^"]+)"/m, src, capture: :all_but_first) |> List.flatten()

      assert Enum.sort(declared) == Enum.sort(Map.keys(gets))
      # the router declares no other method
      assert Regex.scan(~r/^\s*(put|patch|delete|head|options) "/m, src) == []

      for {route, url} <- gets do
        before = File.read!(path)
        assert request(:get, url, %{}, ana).status in [200, 404], route
        assert File.read!(path) == before, "GET #{route} changed the file"
      end
    end

    test "a request naming any host but the loopback address and port is refused, a POST included" do
      first = request(:get, "/")
      form = Map.merge(%{"member" => "ana", "passphrase" => @pass["ana"]}, tokens(first))

      for {host, port} <- [
            {"evil.example", 4848},
            {"127.0.0.1.evil.example", 4848},
            {"127.0.0.1", 4849},
            {"127.0.0.1", 80},
            {"", 4848},
            {"192.168.1.10", 4848}
          ] do
        conn =
          %{conn(:post, "/login", form) | host: host, port: port}
          |> recycle_cookies(first)
          |> Web.call(Web.init(port: 4848))

        assert conn.status == 421, "#{host}:#{port} got #{conn.status}"
        assert Sessions.count() == 0
      end

      assert request(:post, "/login", form, first).status == 303
      assert Sessions.count() == 1
    end

    test "the idle limit is 15 minutes: a session is kept at exactly 15 minutes and discarded after" do
      assert Sessions.idle_ms() == 15 * 60 * 1000
      {:ok, s} = Store.open("ana", @pass["ana"])
      t0 = 50_000_000
      token = Sessions.put(s, t0)
      Sessions.sweep(t0 + 15 * 60 * 1000)
      assert Sessions.live?(token, t0 + 15 * 60 * 1000)
      Sessions.sweep(t0 + 15 * 60 * 1000 + 1)
      assert [%{expired: true} = marker] = Agent.get(Sessions, &Map.values/1)
      assert Map.keys(marker) |> Enum.sort() == [:at, :expired]
    end

    test "as the server starts it, the sweep discards an idle session's keys within 5 seconds" do
      name = :vvb_sessions
      pid = start_supervised!(Supervisor.child_spec({Sessions, name: name}, id: name))
      {:ok, s} = Store.open("ana", @pass["ana"])
      t = System.monotonic_time(:millisecond)
      Sessions.put(s, t - Sessions.idle_ms() - 1, name)

      gone_at =
        Enum.find_value(1..140, fn _ ->
          Process.sleep(50)

          if match?([%{expired: true}], Agent.get(pid, &Map.values/1)),
            do: System.monotonic_time(:millisecond) - t
        end)

      assert gone_at != nil and gone_at <= 6_000, "still held after #{inspect(gone_at)} ms"
      assert [marker] = Agent.get(pid, &Map.values/1)
      refute Map.has_key?(marker, :session)
    end
  end

  # ---------------------------------------------------------------------------

  describe "REQ-124" do
    # A member's whole visit: every kind of page, a change of each main kind, export, bring-in, lock.
    defp visit(path) do
      locked = request(:get, "/")
      bad = post(locked, "/login", %{"member" => "ana", "passphrase" => "wrong"})
      ana = login("ana")

      post(ana, "/act/add_item", %{
        "note" => "Rent",
        "amount" => "1,450",
        "direction" => "out",
        "frequency" => "monthly",
        "on" => "2026-10-01"
      })

      post(ana, "/act/add_item", %{
        "note" => "Pay",
        "amount" => "3,000",
        "direction" => "in",
        "frequency" => "monthly",
        "on" => "2026-10-02"
      })

      post(ana, "/act/add_value", %{"label" => "Home"})
      post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"})
      post(ana, "/act/add_debt", %{"label" => "Card", "type" => "card"})
      post(ana, "/act/new_plan", %{"name" => "If pay stops"})
      [rent, pay, home, chk, card] = Enum.map(~w(Rent Pay Home Checking Card), &id_of(path, &1))
      plan = plan_id(path, "If pay stops")
      post(ana, "/act/add_reading", %{"item" => chk, "balance" => "800", "on" => "2026-09-26"})

      post(ana, "/act/add_reading", %{
        "item" => card,
        "balance" => "900",
        "rate" => "20",
        "min_payment" => "30",
        "on" => "2026-09-26"
      })

      post(ana, "/act/link", %{"item" => rent, "value" => home})
      post(ana, "/act/mark", %{"item" => rent, "job" => pay})

      post(ana, "/act/plan_step", %{
        "plan" => plan,
        "kind" => "switch_off",
        "items" => [rent],
        "from" => "2026-11"
      })

      post(ana, "/act/retirement", %{
        "birth_year" => "1970",
        "retire_age" => "65",
        "return" => "5"
      })

      post(ana, "/act/owners", %{"item" => home, "owners" => ["ana", "ben"]})

      json = request(:get, "/export.json", %{}, ana)
      upload = Path.join(System.tmp_dir!(), "fv-vvb-#{System.unique_integer([:positive])}.json")
      File.write!(upload, json.resp_body)
      on_exit(fn -> File.rm(upload) end)
      bring = request(:get, "/bring-in", %{}, ana)

      preview =
        request(
          :post,
          "/act/bring-in",
          Map.merge(tokens(bring), %{
            "file" => %Plug.Upload{
              path: upload,
              filename: "x.json",
              content_type: "application/json"
            }
          }),
          bring
        )

      pages =
        [locked, bad, json, bring, preview] ++
          Enum.map(
            [
              "/",
              "/items/#{rent}",
              "/items/#{home}",
              "/items/#{chk}",
              "/items/#{card}",
              "/next-60-days",
              "/ahead",
              "/plans",
              "/plans/#{plan}",
              "/retirement",
              "/goals",
              "/balances/new",
              "/leave",
              "/export",
              "/export.json",
              "/items/nope",
              "/no-such-page",
              "/requests/999"
            ],
            &request(:get, &1, %{}, ana)
          ) ++
          [
            post(ana, "/confirm/delete", %{"item" => rent}),
            post(ana, "/confirm/relinquish", %{"item" => home}),
            post(ana, "/confirm/delete_plan", %{"plan" => plan}),
            post(ana, "/act/add_item", %{
              "note" => "Bad",
              "amount" => "x",
              "frequency" => "monthly"
            }),
            request(:post, "/act/add_value", %{"label" => "Stale"}, ana),
            post(ana, "/act/grant", %{"item" => rent, "member" => "zed"})
          ]

      ben = login("ben", post(ana, "/logout", %{}))
      [pid] = Map.keys(household(path).proposals)
      pages = pages ++ [request(:get, "/requests/#{pid}", %{}, ben), request(:get, "/", %{}, ben)]
      post(ben, "/logout", %{})
      pages
    end

    test "a member's whole visit opens no outbound connection", %{path: path} do
      calls = [
        {:gen_tcp, :connect},
        {:gen_udp, :open},
        {:gen_sctp, :connect},
        {:ssl, :connect},
        {:socket, :connect},
        {:prim_inet, :connect},
        {:inet, :getaddr},
        {:inet, :gethostbyname},
        {:httpc, :request}
      ]

      for {m, f} <- calls do
        Code.ensure_loaded(m)
        :erlang.trace_pattern({m, f, :_}, true, [:local])
      end

      # a process can't trace itself, so a separate process collects the trace messages
      collector = spawn(fn -> collect([]) end)
      :erlang.trace(:all, true, [:call, {:tracer, collector}])

      try do
        # the tracing sees a connection when one is made
        {:ok, l} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
        {:ok, port} = :inet.port(l)
        {:ok, c} = :gen_tcp.connect({127, 0, 0, 1}, port, [])
        :gen_tcp.close(c)
        :gen_tcp.close(l)
        assert Enum.any?(traced(collector), &match?({:gen_tcp, :connect, _}, &1))

        pages = visit(path)
        assert length(pages) > 25

        # only the calls watched here: other tests may leave trace patterns set (vault_test.exs, DEF-043)
        assert Enum.filter(traced(collector), fn {m, f, _} -> {m, f} in calls end) == []
      after
        :erlang.trace(:all, false, [:call])
        for {m, f} <- calls, do: :erlang.trace_pattern({m, f, :_}, false, [:local])
        Process.exit(collector, :kill)
      end
    end

    defp collect(acc) do
      receive do
        {:trace, _, :call, mfa} ->
          collect([mfa | acc])

        {:take, from} ->
          send(from, {:traced, Enum.reverse(acc)})
          collect([])
      end
    end

    # what was traced so far, after letting trace messages arrive; the collector starts afresh
    defp traced(collector) do
      Process.sleep(200)
      send(collector, {:take, self()})

      receive do
        {:traced, list} -> list
      after
        2_000 -> flunk("no answer from the trace collector")
      end
    end

    test "every kind of page forbids remote loads and refers to nothing remote", %{path: path} do
      pages = visit(path)

      for page <- pages do
        what = "#{page.method} #{page.request_path} (#{page.status})"
        [csp] = Plug.Conn.get_resp_header(page, "content-security-policy")

        directives =
          csp
          |> String.split(";", trim: true)
          |> Map.new(fn d ->
            [name | sources] = String.split(String.trim(d))
            {name, sources}
          end)

        assert directives["default-src"] == ["'none'"], what

        for {name, sources} <- directives,
            s <- sources,
            do: assert(s in ["'none'", "'self'", "'unsafe-inline'"], "#{what}: #{name} #{s}")

        refute page.resp_body =~ ~r{https?://}i, what

        refute page.resp_body =~ ~r{(?:src|href|action|srcset|poster|data)\s*=\s*["']?\s*//}i,
               what

        refute page.resp_body =~ ~r{url\(\s*["']?\s*(?:[a-z]+:)?//}i, what
        refute page.resp_body =~ ~r{@import}i, what
      end

      # the misdirected-request refusal is sent before anything else and is plain text
      misdirected =
        %{conn(:get, "/") | host: "evil.example", port: 4848} |> Web.call(Web.init(port: 4848))

      assert misdirected.status == 421
      refute misdirected.resp_body =~ ~r{//|<}
    end
  end

  # ---------------------------------------------------------------------------

  describe "REQ-129" do
    @nine [
      {"one_off", "One-off", :one_off, "−$10.00, one-off"},
      {"weekly", "Every week", {:every, 1, :week}, "−$10.00 a week"},
      {"biweekly", "Every two weeks", {:every, 2, :week}, "−$10.00 every two weeks"},
      {"monthly", "Every month", {:every, 1, :month}, "−$10.00 a month"},
      {"every_2_months", "Every two months", {:every, 2, :month}, "−$10.00 every two months"},
      {"every_3_months", "Every three months", {:every, 3, :month}, "−$10.00 every three months"},
      {"twice_a_year", "Twice a year", {:every, 6, :month}, "−$10.00 twice a year"},
      {"yearly", "Every year", {:every, 1, :year}, "−$10.00 a year"},
      {"irregular", "Irregular (enter the total for a year)", :irregular,
       "−$10.00 a year, irregular"}
    ]

    test "adding an item offers exactly the nine choices, with none chosen" do
      home = request(:get, "/", %{}, login("ana")).resp_body

      [_, select] =
        Regex.run(~r/<select id=frequency name=frequency required>(.*?)<\/select>/s, home)

      options = Regex.scan(~r/<option value="([^"]*)"([^>]*)>([^<]*)<\/option>/, select)
      assert [["", "Choose…"] | offered] = Enum.map(options, fn [_, v, _, t] -> [v, t] end)
      assert Enum.sort(offered) == Enum.sort(for {v, t, _, _} <- @nine, do: [v, t])
      assert Enum.all?(options, fn [_, _, attrs, _] -> attrs == "" end)
    end

    test "each of the nine is stored as chosen and shown beside the amount on home, its page, export, and set-asides",
         %{path: path} do
      ana = login("ana")

      for {value, _text, stored, shown} <- @nine do
        note = "Item " <> value

        resp =
          post(ana, "/act/add_item", %{
            "note" => note,
            "amount" => "10",
            "direction" => "out",
            "frequency" => value
          })

        assert resp.status == 303
        id = id_of(path, note)
        assert household(path).items[id].attrs.frequency == stored
        assert household(path).items[id].attrs.amount == -1000

        words =
          String.replace_prefix(shown, "−$10.00", "") |> String.trim_leading(",") |> String.trim()

        assert request(:get, "/items/#{id}", %{}, ana).resp_body =~ shown

        assert request(:get, "/", %{}, ana).resp_body =~
                 ~r{<b>#{note}</b></a></td><td role=cell class=num data-label="Amount">−\$10.00<span class=phone-only> #{words}</span></td><td role=cell class=freq data-label="How often">#{words}</td>}
      end

      export = request(:get, "/export", %{}, ana).resp_body
      for {value, _, _, shown} <- @nine, do: assert(export =~ "Item #{value}</b>, #{shown}")

      # the set-aside list names each less-than-monthly item with its amount and how often
      next = request(:get, "/next-60-days", %{}, ana).resp_body

      for {value, _, _, shown} <- @nine,
          value in ~w(every_2_months every_3_months twice_a_year yearly irregular),
          do: assert(next =~ ">Item #{value}</a>: #{shown},")
    end

    test "items stored with the earlier frequencies read and show as the same intervals", %{
      path: path
    } do
      {:ok, s} = Store.open("ana", @pass["ana"])

      for {legacy, shown} <- [
            weekly: "−$10.00 a week",
            biweekly: "−$10.00 every two weeks",
            monthly: "−$10.00 a month",
            yearly: "−$10.00 a year"
          ] do
        attrs = %{note: "L #{legacy}", amount: -1000, unit: :cents, frequency: legacy}
        {:ok, _} = Store.apply(s, &Household.add_item(&1, "ana", "legacy-#{legacy}", attrs))
        ana = login("ana")
        assert request(:get, "/items/legacy-#{legacy}", %{}, ana).resp_body =~ shown
        assert household(path).items["legacy-#{legacy}"].attrs.frequency == legacy
      end
    end
  end

  # ---------------------------------------------------------------------------

  describe "REQ-133" do
    defp account_with_readings do
      vault()
      |> act("ana", &Balances.add_account(&1, "ana", "chk", "Checking", :checking))
      |> act("ana", &Balances.add_reading(&1, "ana", "chk", %{on: "2026-08-01", balance: 1}))
      |> act("ana", &Balances.add_reading(&1, "ana", "chk", %{on: "2026-09-01", balance: 2}))
    end

    test "a grantee who leaves the household loses their reading key" do
      v = act(account_with_readings(), "ana", &Household.propose_grant(&1, "ana", "chk", "ben"))
      assert Map.has_key?(List.last(v.items["chk"].readings).keys, "ben")
      v = act(v, "ben", &Exit.leave(&1, "ben"))
      refute Enum.any?(v.items["chk"].readings, &Map.has_key?(&1.keys, "ben"))
    end

    test "an owner removed by agreement loses every reading key and gets none for later readings" do
      v =
        account_with_readings()
        |> act("ana", &Household.propose_owners(&1, "ana", "chk", ["ana", "cy"]))

      assert Enum.all?(v.items["chk"].readings, &Map.has_key?(&1.keys, "cy"))
      v = act(v, "ana", &Household.propose_owners(&1, "ana", "chk", ["ana"]))
      [pid] = Map.keys(v.proposals)
      v = act(v, "cy", &Household.consent(&1, "cy", pid))
      refute Enum.any?(v.items["chk"].readings, &Map.has_key?(&1.keys, "cy"))
      v = act(v, "ana", &Balances.add_reading(&1, "ana", "chk", %{on: "2026-09-27", balance: 3}))
      refute Enum.any?(v.items["chk"].readings, &Map.has_key?(&1.keys, "cy"))
      assert session(v, "cy").reading_keys == %{}
    end
  end

  # ---------------------------------------------------------------------------

  describe "REQ-165" do
    # Sends one form twice from one page. The first must change the file; the repeat must not, and
    # must go where the first went, saying so.
    defp twice(path, page, action, params) do
      params = Map.merge(params, tokens(page))
      before = File.read!(path)
      first = request(:post, action, params, page)
      assert first.status == 303, "#{action}: #{first.status} #{first.resp_body}"
      middle = File.read!(path)
      refute middle == before, "#{action}: the first sending changed nothing"
      second = request(:post, action, params, first)
      assert File.read!(path) == middle, "#{action}: the repeat changed the household"
      assert second.status == 303
      assert loc(second) == loc(first), action
      assert follow(second) =~ "That was already saved.", action
      second
    end

    defp twice(path, prev, action, params, :home),
      do: twice(path, request(:get, "/", %{}, prev), action, params)

    test "every form that changes the household changes it once, and a repeat says it was already saved",
         %{path: path} do
      ana = login("ana")

      add = fn note, amount, dir ->
        %{"note" => note, "amount" => amount, "direction" => dir, "frequency" => "monthly"}
      end

      ana = twice(path, ana, "/act/add_item", add.("Rent", "1,450", "out"), :home)
      ana = twice(path, ana, "/act/add_item", add.("Pay", "3,000", "in"), :home)
      for n <- ~w(Joint Gone Letgo), do: post(ana, "/act/add_item", add.(n, "1", "out"))
      ana = twice(path, ana, "/act/add_value", %{"label" => "Home"}, :home)

      ana =
        twice(
          path,
          ana,
          "/act/add_account",
          %{"label" => "Checking", "type" => "checking"},
          :home
        )

      ana = twice(path, ana, "/act/add_debt", %{"label" => "Card", "type" => "card"}, :home)

      [rent, pay, home, chk, joint, gone, letgo] =
        Enum.map(~w(Rent Pay Home Checking Joint Gone Letgo), &id_of(path, &1))

      ana =
        twice(
          path,
          ana,
          "/act/add_reading",
          %{"item" => chk, "balance" => "850", "on" => "2026-09-26"},
          :home
        )

      ana = twice(path, ana, "/act/link", %{"item" => rent, "value" => home}, :home)
      ana = twice(path, ana, "/act/unlink", %{"item" => rent, "value" => home}, :home)
      ana = twice(path, ana, "/act/attach", %{"item" => rent, "account" => chk}, :home)
      ana = twice(path, ana, "/act/mark", %{"item" => rent, "job" => pay}, :home)
      ana = twice(path, ana, "/act/unmark", %{"item" => rent, "job" => pay}, :home)
      ana = twice(path, ana, "/act/grant", %{"item" => rent, "member" => "cy"}, :home)
      ana = twice(path, ana, "/act/revoke", %{"item" => rent, "member" => "cy"}, :home)
      ana = twice(path, ana, "/act/owners", %{"item" => rent, "owners" => ["ana", "ben"]}, :home)
      post(ana, "/act/owners", %{"item" => joint, "owners" => ["ana", "ben"]})
      ana = twice(path, ana, "/act/relinquish", %{"item" => joint}, :home)
      ana = twice(path, ana, "/act/delete", %{"item" => gone}, :home)
      ana = twice(path, ana, "/act/let_go", %{"item" => letgo, "to" => "delete"}, :home)

      # a pending change on the joint item: withdraw one, and leave another for ben to agree to
      post(ana, "/act/grant", %{"item" => rent, "member" => "cy"})
      [p1] = Map.keys(household(path).proposals)
      ana = twice(path, ana, "/act/withdraw", %{"proposal" => to_string(p1)}, :home)
      post(ana, "/act/grant", %{"item" => rent, "member" => "cy"})
      [p2] = Map.keys(household(path).proposals)

      ana = twice(path, ana, "/act/new_plan", %{"name" => "If pay stops"}, :home)
      post(ana, "/act/new_plan", %{"name" => "Spare"})
      plan = plan_id(path, "If pay stops")

      for month <- ["2026-11", "2026-12"],
          do:
            post(ana, "/act/plan_step", %{
              "plan" => plan,
              "kind" => "switch_off",
              "items" => [rent],
              "from" => month
            })

      ana =
        twice(
          path,
          ana,
          "/act/plan_step",
          %{
            "plan" => plan,
            "kind" => "borrow",
            "amount" => "6,000",
            "rate" => "8.75",
            "payment" => "250",
            "from" => "2027-01"
          },
          :home
        )

      ana = twice(path, ana, "/act/remove_step", %{"plan" => plan, "n" => "1"}, :home)
      assert length(household(path).plans["ana"][plan].steps) == 2
      ana = twice(path, ana, "/act/share_plan", %{"plan" => plan, "members" => ["ben"]}, :home)
      ana = twice(path, ana, "/act/delete_plan", %{"plan" => plan_id(path, "Spare")}, :home)
      ana = twice(path, ana, "/act/fund_goal", %{"months" => "3"}, :home)
      ana = twice(path, ana, "/act/set_aside", %{"value" => home, "rate" => "10"}, :home)

      ana =
        twice(path, request(:get, "/retirement", %{}, ana), "/act/retirement", %{
          "birth_year" => "1970",
          "retire_age" => "65",
          "return" => "5",
          "ss" => "1,800",
          "target" => "4,000"
        })

      # bringing in a saved record: the confirmation is the form that changes the household
      upload = Path.join(System.tmp_dir!(), "fv-vvb-#{System.unique_integer([:positive])}.json")
      File.write!(upload, request(:get, "/export.json", %{}, ana).resp_body)
      on_exit(fn -> File.rm(upload) end)
      bring = request(:get, "/bring-in", %{}, ana)

      preview =
        request(
          :post,
          "/act/bring-in",
          Map.merge(tokens(bring), %{
            "file" => %Plug.Upload{
              path: upload,
              filename: "x.json",
              content_type: "application/json"
            }
          }),
          bring
        )

      assert preview.status == 200
      twice(path, preview, "/act/bring-in/confirm", %{})

      # ben agrees to the pending change, twice
      ben = login("ben", post(ana, "/logout", %{}))
      twice(path, ben, "/act/consent", %{"proposal" => to_string(p2)}, :home)
    end

    test "a second click while the first is still being handled changes nothing", %{path: path} do
      ana = login("ana")
      page = request(:get, "/", %{}, ana)
      params = Map.merge(%{"label" => "Once"}, tokens(page))
      :sys.suspend(Store)
      task = Task.async(fn -> request(:post, "/act/add_value", params, page) end)
      form = params["_form"]

      second =
        try do
          # the first sending has claimed its form and waits on the store
          assert Enum.find_value(1..100, fn _ ->
                   Process.sleep(10)

                   Agent.get(Sessions, &Map.values/1)
                   |> Enum.any?(&(get_in(&1, [:forms, form]) == :busy))
                 end)

          request(:post, "/act/add_value", params, page)
        after
          :sys.resume(Store)
        end

      first = Task.await(task)
      assert second.status == 303
      assert loc(second) == "/"
      assert follow(second) =~ "That was already sent. Check below that it was saved."
      assert first.status == 303
      labels = household(path).items |> Map.values() |> Enum.map(& &1.attrs[:label])
      assert Enum.count(labels, &(&1 == "Once")) == 1
      # once the first is done, a further repeat is told it was saved
      assert follow(request(:post, "/act/add_value", params, first)) =~ "That was already saved."
    end

    test "a form refused by a rule may be sent again, corrected, and is then saved", %{path: path} do
      ana = login("ana")
      post(ana, "/act/add_item", %{"note" => "Rent", "amount" => "5", "frequency" => "monthly"})
      rent = id_of(path, "Rent")
      page = request(:get, "/items/#{rent}", %{}, ana)
      base = Map.merge(%{"item" => rent, "return" => "/items/#{rent}"}, tokens(page))
      refused = request(:post, "/act/grant", Map.put(base, "member", "zed"), page)
      assert refused.status == 422
      again = request(:post, "/act/grant", Map.put(base, "member", "ben"), refused)
      assert again.status == 303
      refute follow(again) =~ "already saved"
      assert "ben" in household(path).items[rent].grantees
    end

    test "a form sent after the session ended changed nothing, and its one-time token isn't kept",
         %{path: path} do
      ana = login("ana")
      page = request(:get, "/", %{}, ana)
      form = tokens(page)["_form"]

      Agent.update(
        Sessions,
        &Map.new(&1, fn {k, v} -> {k, %{v | at: v.at - Sessions.idle_ms() - 1}} end)
      )

      late = request(:post, "/act/add_value", Map.merge(%{"label" => "Late"}, tokens(page)), page)
      assert loc(late) == "/?locked=action"
      refute "Late" in (household(path).items |> Map.values() |> Enum.map(& &1.attrs[:label]))

      # unlocked again, the same form (its one-time token) is applied, not taken for a repeat
      ana = login("ana", late)
      fresh = request(:get, "/", %{}, ana)

      again =
        request(
          :post,
          "/act/add_value",
          %{"label" => "Late", "_csrf_token" => csrf(fresh), "_form" => form},
          fresh
        )

      assert again.status == 303
      refute follow(again) =~ "already saved"
      assert "Late" in (household(path).items |> Map.values() |> Enum.map(& &1.attrs[:label]))
    end
  end

  # ---------------------------------------------------------------------------

  describe "REQ-166" do
    defp forms_to(body),
      do:
        Regex.scan(~r/<form[^>]*action="([^"]+)"/, body, capture: :all_but_first)
        |> List.flatten()

    test "deleting a value, an item, an account, or a debt is first shown by name and asked; going back keeps it",
         %{path: path} do
      ana = login("ana")
      post(ana, "/act/add_value", %{"label" => "A safe home"})
      post(ana, "/act/add_item", %{"note" => "Rent", "amount" => "5", "frequency" => "monthly"})
      post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"})
      post(ana, "/act/add_debt", %{"label" => "Visa", "type" => "card"})

      for name <- ["A safe home", "Rent", "Checking", "Visa"] do
        id = id_of(path, name)
        item_page = request(:get, "/items/#{id}", %{}, ana)
        assert "/confirm/delete" in forms_to(item_page.resp_body), name
        refute "/act/delete" in forms_to(item_page.resp_body), name

        before = File.read!(path)

        confirm =
          request(
            :post,
            "/confirm/delete",
            Map.merge(%{"item" => id}, tokens(item_page)),
            item_page
          )

        assert confirm.status == 200
        assert confirm.resp_body =~ "<h2>Delete “#{name}”?</h2>"
        assert confirm.resp_body =~ "with its history. This can&#39;t be undone."
        assert forms_to(confirm.resp_body) -- ["/logout"] == ["/act/delete"]
        # showing it deletes nothing, and going back leaves it
        assert File.read!(path) == before
        [_, back] = Regex.run(~r/<a href="([^"]+)">No, go back<\/a>/, confirm.resp_body)
        assert request(:get, back, %{}, confirm).resp_body =~ name
        assert File.read!(path) == before
        assert request(:get, "/items/#{id}", %{}, confirm).status == 200

        # confirming deletes it
        done = request(:post, "/act/delete", Map.merge(%{"item" => id}, tokens(confirm)), confirm)
        assert done.status == 303
        refute Map.has_key?(household(path).items, id)
      end
    end

    test "a plan with steps is named, with how many steps go with it; going back keeps it", %{
      path: path
    } do
      ana = login("ana")
      post(ana, "/act/add_item", %{"note" => "Rent", "amount" => "5", "frequency" => "monthly"})
      post(ana, "/act/new_plan", %{"name" => "If pay stops"})
      plan = plan_id(path, "If pay stops")

      for month <- ["2026-11", "2026-12"],
          do:
            post(ana, "/act/plan_step", %{
              "plan" => plan,
              "kind" => "switch_off",
              "items" => [id_of(path, "Rent")],
              "from" => month
            })

      page = request(:get, "/plans/#{plan}", %{}, ana)

      confirm =
        request(:post, "/confirm/delete_plan", Map.merge(%{"plan" => plan}, tokens(page)), page)

      assert confirm.resp_body =~ "Delete the plan “If pay stops”?"
      assert confirm.resp_body =~ "Its 2 steps will be deleted with it."
      [_, back] = Regex.run(~r/<a href="([^"]+)">No, go back<\/a>/, confirm.resp_body)
      assert request(:get, back, %{}, confirm).status == 200
      assert length(household(path).plans["ana"][plan].steps) == 2
    end

    test "no page offers deleting straight away; the leaving checklist names the item and asks for an explicit choice",
         %{path: path} do
      ana = login("ana")
      post(ana, "/act/add_value", %{"label" => "Home"})
      post(ana, "/act/add_item", %{"note" => "Rent", "amount" => "5", "frequency" => "monthly"})
      post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"})
      post(ana, "/act/new_plan", %{"name" => "If pay stops"})
      plan = plan_id(path, "If pay stops")
      post(ana, "/act/share_plan", %{"plan" => plan, "members" => ["ben"]})
      ids = household(path).items |> Map.keys()

      pages =
        [
          "/",
          "/plans",
          "/plans/#{plan}",
          "/goals",
          "/retirement",
          "/next-60-days",
          "/ahead",
          "/export"
        ] ++
          Enum.map(ids, &"/items/#{&1}")

      for p <- pages do
        forms = forms_to(request(:get, p, %{}, ana).resp_body)
        refute "/act/delete" in forms, p
        refute "/act/delete_plan" in forms, p
      end

      leave = request(:get, "/leave", %{}, ana).resp_body
      refute "/act/delete" in forms_to(leave)

      for title <- ["Home", "Rent", "Checking"] do
        id = id_of(path, title)

        assert leave =~
                 ~r{<form method=post action="/act/let_go" class=row>.*?name=item value="#{id}">\s*<p><label for="to-#{id}">What happens to “#{title}”</label><select id="to-#{id}" name=to required><option value="">Choose…</option>.*?<option value="delete">Delete it for everyone \(can't be undone\)</option></select></p>}s
      end

      # without that choice, nothing is deleted
      before = File.read!(path)
      page = request(:get, "/leave", %{}, ana)

      resp =
        request(
          :post,
          "/act/let_go",
          Map.merge(
            %{"item" => id_of(path, "Rent"), "to" => "", "return" => "/leave"},
            tokens(page)
          ),
          page
        )

      assert resp.status == 422
      assert File.read!(path) == before
    end

    test "removing one plan step or one link doesn't ask: one press removes it", %{path: path} do
      ana = login("ana")
      post(ana, "/act/add_value", %{"label" => "Home"})
      post(ana, "/act/add_item", %{"note" => "Rent", "amount" => "5", "frequency" => "monthly"})
      [rent, home] = Enum.map(~w(Rent Home), &id_of(path, &1))
      post(ana, "/act/link", %{"item" => rent, "value" => home})
      post(ana, "/act/new_plan", %{"name" => "If pay stops"})
      plan = plan_id(path, "If pay stops")

      post(ana, "/act/plan_step", %{
        "plan" => plan,
        "kind" => "switch_off",
        "items" => [rent],
        "from" => "2026-11"
      })

      plan_page = request(:get, "/plans/#{plan}", %{}, ana)
      assert "/act/remove_step" in forms_to(plan_page.resp_body)

      refute Enum.any?(
               forms_to(plan_page.resp_body),
               &(String.contains?(&1, "step") and String.starts_with?(&1, "/confirm"))
             )

      removed =
        request(
          :post,
          "/act/remove_step",
          Map.merge(
            %{"plan" => plan, "n" => "1", "return" => "/plans/#{plan}"},
            tokens(plan_page)
          ),
          plan_page
        )

      assert removed.status == 303
      assert household(path).plans["ana"][plan].steps == []

      item_page = request(:get, "/items/#{rent}", %{}, ana)
      assert "/act/unlink" in forms_to(item_page.resp_body)

      refute Enum.any?(
               forms_to(item_page.resp_body),
               &(&1 in ["/confirm/unlink", "/confirm/link"])
             )

      unlinked =
        request(
          :post,
          "/act/unlink",
          Map.merge(
            %{"item" => rent, "value" => home, "return" => "/items/#{rent}"},
            tokens(item_page)
          ),
          item_page
        )

      assert unlinked.status == 303
      assert household(path).links["ana"] == MapSet.new()
    end
  end

  # ---------------------------------------------------------------------------

  describe "REQ-170" do
    test "each ledger entry is sealed to the owners when it is appended, and re-sealed to each new owner" do
      v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{note: "x"}))
      assert entry_readers(v, "i1") == [["ana"]]
      v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
      # the grantee holds the item key but no ledger key
      assert entry_readers(v, "i1") == [["ana"], ["ana"]]
      v = act(v, "ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "cy"]))
      assert entry_readers(v, "i1") == List.duplicate(["ana", "cy"], 3)
      for e <- v.items["i1"].ledger, do: assert(opens_entry?(v, "cy", "i1", e))
      refute Enum.any?(v.items["i1"].ledger, &opens_entry?(v, "ben", "i1", &1))
    end

    test "an owner who relinquishes loses their ledger keys and gets none for later entries" do
      v =
        vault()
        |> act("ana", &Household.add_item(&1, "ana", "i1", %{note: "x"}))
        |> act("ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "ben"]))
        |> act("ben", &Household.relinquish(&1, "ben", "i1"))

      assert entry_readers(v, "i1") == List.duplicate(["ana"], 3)
      v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
      assert entry_readers(v, "i1") == List.duplicate(["ana"], 4)
    end

    test "a prospective owner of a value can read the whole ledger once every current owner agrees, not before" do
      v =
        vault()
        |> act("ana", &Alignment.add_value(&1, "ana", "v1", "a safe home"))
        |> act("ana", &Household.propose_owners(&1, "ana", "v1", ["ana", "ben"]))

      [p] = Map.keys(v.proposals)
      v = act(v, "ben", &Household.consent(&1, "ben", p))
      v = act(v, "ana", &Household.propose_owners(&1, "ana", "v1", ["ana", "ben", "cy"]))
      # only ana has agreed so far
      refute Enum.any?(v.items["v1"].ledger, &Map.has_key?(&1.keys, "cy"))
      [p] = Map.keys(v.proposals)
      v = act(v, "ben", &Household.consent(&1, "ben", p))
      # every current owner agreed; cy hasn't yet, and can already read every entry
      assert Map.has_key?(v.proposals, p)
      assert Enum.all?(v.items["v1"].ledger, &opens_entry?(v, "cy", "v1", &1))
      refute :sealed in session(v, "cy").household.ledger["v1"]
      # withdrawn, that access ends
      v = act(v, "ana", &Household.withdraw(&1, "ana", p))
      refute Enum.any?(v.items["v1"].ledger, &Map.has_key?(&1.keys, "cy"))
    end

    test "so can a prospective owner of a shared plan; a proposed owner of anything else can't" do
      v =
        vault()
        |> act("ana", &Plans.new_plan(&1, "ana", "p1", "If pay stops"))
        |> act("ana", &Plans.propose_shared(&1, "ana", "p1", "sp1", ["ben"]))

      assert Enum.all?(v.items["sp1"].ledger, &opens_entry?(v, "ben", "sp1", &1))
      assert Map.keys(v.items["sp1"].keys) |> Enum.sort() == ["ana", "ben"]

      v =
        v
        |> act("ana", &Household.add_item(&1, "ana", "i1", %{note: "x"}))
        |> act("ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "ben"]))
        |> act("ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "ben", "cy"]))

      refute Enum.any?(v.items["i1"].ledger, &Map.has_key?(&1.keys, "cy"))
      refute Map.has_key?(v.items["i1"].keys, "cy")
    end
  end
end
