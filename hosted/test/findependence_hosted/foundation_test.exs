defmodule FindependenceHosted.FoundationTest do
  @moduledoc """
  WI-073: the hosted foundation's acceptance criteria that need no domain data, against PostgreSQL
  (REQ-180..REQ-186, REQ-190, REQ-191). The criteria that need items, readings, or private records are WI-074's.
  """
  use FindependenceHostedWeb.ConnCase, async: false

  import Ecto.Query
  alias FindependenceHosted.{Accounts, Audit, Limits, Repo, Sessions, Tenancy}
  alias FindependenceHosted.Schemas.{Account, AuditEvent, Invitation, Membership}

  @pass "a long passphrase 1"

  setup do
    Limits.reset()
    :ok
  end

  # ---------------------------------------------------------------------------
  # helpers: the flows a browser goes through

  defp sign_up(conn, email, pass \\ @pass, disclosure \\ "true") do
    post(conn, ~p"/sign-up", %{
      "account" => %{
        "email" => email,
        "passphrase" => pass,
        "passphrase_confirmation" => pass,
        "disclosure" => disclosure
      }
    })
  end

  defp recovery_key(conn) do
    [_, key] = Regex.run(~r/id="recovery-key"[^>]*>\s*([A-Z2-7-]+)\s*</, html_response(conn, 200))
    key
  end

  defp sign_in(conn, email, pass \\ @pass),
    do: post(conn, ~p"/sign-in", %{"account" => %{"email" => email, "passphrase" => pass}})

  defp signed_in(email, pass \\ @pass) do
    _ = sign_up(build_conn(), email, pass)
    conn = sign_in(build_conn(), email, pass)
    assert redirected_to(conn) == "/"
    recycle(conn)
  end

  defp start_household(conn, name) do
    conn = post(conn, ~p"/household", %{"household" => %{"display_name" => name}})
    assert redirected_to(conn) == "/"
    recycle(conn)
  end

  defp new_code(conn) do
    conn = post(conn, ~p"/invitations")
    [_, code] = Regex.run(~r/id="new-code"[^>]*>\s*([A-Z2-7-]+)\s*</, html_response(conn, 200))
    {recycle(conn), code}
  end

  # the token behind a browser's cookie, read through the endpoint's session and the browser pipeline
  defp token_of(conn) do
    conn
    |> bypass_through(FindependenceHostedWeb.Router, [:browser])
    |> get("/")
    |> get_session(:token)
  end

  defp session_of(conn), do: Sessions.fetch(token_of(conn))

  # every value in every table, as text, for inspection
  defp dump do
    for table <- ~w(accounts households memberships invitations audit_events),
        row <- Repo.query!("SELECT * FROM #{table}").rows,
        value <- row,
        value != nil,
        do: value
  end

  defp flip(<<c, rest::binary>>), do: <<if(c == ?A, do: ?B, else: ?A), rest::binary>>

  defp form_for_sign_in(email, pass),
    do: %{"account" => %{"email" => email, "passphrase" => pass}}

  defp code_id(code) do
    {:ok, bytes} = code |> String.replace("-", "") |> Base.decode32(padding: false)
    hash = :crypto.hash(:sha256, bytes)
    Repo.one!(from i in Invitation, where: i.code_hash == ^hash, select: i.id)
  end

  defp account_for(email),
    do: Repo.get_by!(Account, email_hmac: Accounts.hmac(Accounts.normalize(email)))

  # ---------------------------------------------------------------------------

  describe "REQ-180: disclosure before sign-up" do
    test "AC-1: the sign-up page states the disclosure before any field, with a confirmation", %{
      conn: conn
    } do
      html = html_response(get(conn, ~p"/sign-up"), 200)
      [before_form | _] = String.split(html, "<form")
      assert before_form =~ "operator&#39;s server can read your information"
      assert html =~ ~s(name="account[disclosure]")
      assert html =~ "I&#39;ve read how my information is handled"
    end

    test "AC-2: without the confirmation no account is made; with it, one is", %{conn: conn} do
      conn1 = sign_up(conn, "a@example.com", @pass, "false")
      assert html_response(conn1, 422) =~ "Confirm that you&#39;ve read"
      assert Repo.aggregate(Account, :count) == 0

      conn2 = sign_up(build_conn(), "a@example.com")
      assert html_response(conn2, 200) =~ "Your recovery key"
      assert Repo.aggregate(Account, :count) == 1
    end
  end

  describe "REQ-181: accounts and sign-in" do
    test "AC-1: one account per address, compared without case or surrounding spaces" do
      _ = sign_up(build_conn(), "Ana@Example.com")
      conn = sign_up(build_conn(), "  ana@example.COM ")
      assert html_response(conn, 422) =~ "An account already uses that address."
      assert Repo.aggregate(Account, :count) == 1
    end

    test "AC-2: an unknown address and a wrong passphrase get the same refusal after the same work" do
      _ = sign_up(build_conn(), "known@example.com")

      unknown = sign_in(build_conn(), "nobody@example.com", "whatever passphrase")
      wrong = sign_in(build_conn(), "known@example.com", "wrong passphrase!!")

      scrub = fn html ->
        html
        |> String.replace(~r/name="_csrf_token"[^>]*>/, "")
        |> String.replace(~r/value="[^"]*@example\.com"/, "")
        |> String.replace(~r/"csrf-token" content="[^"]*"/, "")
        # Petal's element ids end in a counter whose length varies, so ids and references to them are blanked
        |> String.replace(~r/ (id|aria-labelledby|aria-describedby)="[^"]*"/, "")
      end

      assert unknown.status == 401 and wrong.status == 401
      assert scrub.(unknown.resp_body) == scrub.(wrong.resp_body)

      # the same derivation, with the same iteration count, runs in both cases
      mfa = {FindependenceShared.Crypto, :derive_key, 4}

      derivations =
        for {email, pass} <- [
              {"nobody@example.com", "x" <> @pass},
              {"known@example.com", "y" <> @pass}
            ] do
          # traced in its own process: the test process collects the trace
          :erlang.trace_pattern(mfa, true, [:global])
          me = self()

          task =
            Task.async(fn ->
              receive do: (:go -> Accounts.sign_in(email, pass, "test"))
            end)

          :erlang.trace(task.pid, true, [:call, {:tracer, me}])
          send(task.pid, :go)
          Task.await(task)
          :erlang.trace_pattern(mfa, false, [:global])
          # every trace message the task generated has reached this process before it is read
          ref = :erlang.trace_delivered(task.pid)
          assert_receive {:trace_delivered, _, ^ref}, 5_000

          Stream.repeatedly(fn ->
            receive do
              {:trace, _, :call, {_, _, [_pass, _salt, iterations, _opts]}} -> iterations
            after
              50 -> nil
            end
          end)
          |> Enum.take_while(& &1)
        end

      assert derivations == [[Accounts.iterations()], [Accounts.iterations()]]
    end

    test "AC-3: a passphrase under 12 characters is refused at sign-up and at a change" do
      assert html_response(sign_up(build_conn(), "b@example.com", "short pass"), 422) =~
               "at least 12 characters"

      conn = signed_in("c@example.com")

      conn =
        post(conn, ~p"/passphrase", %{
          "account" => %{
            "current" => @pass,
            "passphrase" => "too short",
            "passphrase_confirmation" => "too short"
          }
        })

      assert html_response(conn, 422) =~ "at least 12 characters"
    end
  end

  describe "REQ-182: key material" do
    test "AC-1: the tables hold no passphrase, recovery key, unwrapped key, or address, through every change" do
      email = "keys@example.com"
      key = recovery_key(sign_up(build_conn(), email))
      conn = sign_in(build_conn(), email) |> recycle()
      {:ok, s} = session_of(conn)
      priv = s.private_key

      new_pass = "a new long passphrase"

      conn =
        post(conn, ~p"/passphrase", %{
          "account" => %{
            "current" => @pass,
            "passphrase" => new_pass,
            "passphrase_confirmation" => new_pass
          }
        })

      assert redirected_to(conn) == "/"
      third = "a third long passphrase"

      :ok =
        Accounts.recover(
          %{
            "email" => email,
            "recovery_key" => key,
            "passphrase" => third,
            "passphrase_confirmation" => third
          },
          "test"
        )

      {:ok, recovery_bytes} = key |> String.replace("-", "") |> Base.decode32(padding: false)

      for value <- dump(), is_binary(value) do
        for secret <- [@pass, new_pass, third, email, priv, recovery_bytes, key] do
          refute :binary.match(value, secret) != :nomatch, "a stored value contains a secret"
        end
      end
    end

    test "AC-2: PBKDF2-HMAC-SHA256 with at least 600,000 iterations outside tests; a wrong passphrase fails" do
      prod = Config.Reader.read!("config/config.exs", env: :prod)
      kdf = prod[:findependence_hosted][:kdf]
      assert kdf[:iterations] >= 600_000
      refute kdf[:unsafe_test]

      _ = sign_up(build_conn(), "kdf@example.com")

      assert {:error, :unauthenticated, :bad_credentials} =
               Accounts.sign_in("kdf@example.com", "not the passphrase", "t")
    end

    test "AC-2: each wrap has its own random 16-byte salt, renewed at a passphrase change" do
      _ = sign_up(build_conn(), "salt1@example.com")
      _ = sign_up(build_conn(), "salt2@example.com")
      a = account_for("salt1@example.com")
      b = account_for("salt2@example.com")

      for acc <- [a, b],
          do: assert(byte_size(acc.pass_salt) == 16 and byte_size(acc.recovery_salt) == 16)

      assert length(Enum.uniq([a.pass_salt, a.recovery_salt, b.pass_salt, b.recovery_salt])) == 4
      assert a.pass_iterations == Accounts.iterations()

      new_pass = "another long passphrase"
      conn = sign_in(build_conn(), "salt1@example.com") |> recycle()

      _ =
        post(conn, ~p"/passphrase", %{
          "account" => %{
            "current" => @pass,
            "passphrase" => new_pass,
            "passphrase_confirmation" => new_pass
          }
        })

      refute account_for("salt1@example.com").pass_salt == a.pass_salt
    end
  end

  describe "REQ-183: sessions" do
    test "AC-1: sign-out discards the key; after 15 idle minutes the sweep does, and the next request says so" do
      conn = signed_in("s@example.com")
      account = account_for("s@example.com")
      assert Sessions.held?(account.id)

      out = post(conn, ~p"/sign-out")
      assert redirected_to(out) == "/sign-in"
      refute Sessions.held?(account.id)

      conn = sign_in(build_conn(), "s@example.com") |> recycle()
      token = token_of(conn)
      [{^token, data}] = :ets.lookup(FindependenceHosted.Sessions, token)

      :ets.insert(
        FindependenceHosted.Sessions,
        {token, %{data | touched: data.touched - 16 * 60 * 1000}}
      )

      :ok = Sessions.sweep()
      refute Sessions.held?(account.id)

      next = get(conn, ~p"/")
      assert redirected_to(next) == "/sign-in"
      assert Phoenix.Flash.get(next.assigns.flash, :info) =~ "15 minutes without activity"
    end

    test "AC-2: a passphrase change ends the member's other sessions" do
      _ = sign_up(build_conn(), "p@example.com")
      a = sign_in(build_conn(), "p@example.com") |> recycle()
      b = sign_in(build_conn(), "p@example.com") |> recycle()
      new_pass = "another long passphrase"

      _ =
        post(a, ~p"/passphrase", %{
          "account" => %{
            "current" => @pass,
            "passphrase" => new_pass,
            "passphrase_confirmation" => new_pass
          }
        })

      assert {:ok, _} = session_of(a)
      assert :none = session_of(b)
      assert redirected_to(get(b, ~p"/")) == "/sign-in"
    end

    test "AC-3: the cookie holds only a signed token; a state change needs a CSRF token" do
      conn = signed_in("t@example.com")
      token = token_of(conn)
      assert is_binary(token) and byte_size(token) == 32

      session =
        conn
        |> bypass_through(FindependenceHostedWeb.Router, [:browser])
        |> get("/")
        |> get_session()

      assert Map.keys(session) -- ["_csrf_token"] == ["token"]

      {"cookie", cookie} = List.keyfind(conn.req_headers, "cookie", 0)
      {:ok, s} = session_of(conn)

      for secret <- [@pass, "t@example.com", s.private_key, Base.encode64(s.private_key)],
          do: refute(:binary.match(cookie, secret) != :nomatch)

      prod = Config.Reader.read!("config/config.exs", env: :prod)
      refute prod[:findependence_hosted][:secure_cookies] == false

      unprotected = %{
        build_conn()
        | private: Map.delete(build_conn().private, :plug_skip_csrf_protection)
      }

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        post(unprotected, ~p"/sign-in", %{
          "account" => %{"email" => "t@example.com", "passphrase" => @pass}
        })
      end
    end

    test "AC-1: the sweep runs every few seconds outside tests" do
      prod = Config.Reader.read!("config/config.exs", env: :prod)
      assert prod[:findependence_hosted][:sessions][:idle_ms] == 15 * 60 * 1000
      assert prod[:findependence_hosted][:sessions][:sweep_ms] <= 5_000
    end

    test "AC-3: the cookie is HttpOnly and SameSite=Lax, Secure outside development and tests" do
      conn = post(build_conn(), ~p"/sign-in", form_for_sign_in("nobody@example.com", @pass))

      [cookie] =
        for {"set-cookie", v} <- conn.resp_headers, v =~ "_findependence_hosted_key", do: v

      assert cookie =~ ~r/;\s*HttpOnly/i
      assert cookie =~ ~r/;\s*SameSite=Lax/i

      source = File.read!("lib/findependence_hosted_web/endpoint.ex")

      assert source =~
               "secure: Application.compile_env(:findependence_hosted, :secure_cookies, true)"

      for env <- [:prod],
          do:
            refute(
              Config.Reader.read!("config/config.exs", env: env)[:findependence_hosted][
                :secure_cookies
              ] == false
            )
    end

    test "AC-3: every state-changing route refuses a request without a CSRF token" do
      posts = for r <- FindependenceHostedWeb.Router.__routes__(), r.verb == :post, do: r.path
      assert length(posts) == 11

      for path <- posts do
        path = String.replace(path, ":id", Ecto.UUID.generate())

        unprotected = %{
          build_conn()
          | private: Map.delete(build_conn().private, :plug_skip_csrf_protection)
        }

        assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
          post(unprotected, path, %{})
        end
      end
    end
  end

  describe "REQ-184: recovery with the recovery key" do
    test "AC-1: the key is shown once and not stored" do
      conn = sign_up(build_conn(), "r@example.com")
      key = recovery_key(conn)
      assert html_response(conn, 200) =~ "shown only this once"
      assert Enum.all?(dump(), fn v -> not (is_binary(v) and v =~ key) end)
      refute html_response(get(build_conn(), ~p"/sign-in"), 200) =~ key
    end

    test "AC-2: with the key, a new passphrase keeps the same private key; a wrong key is refused like an unknown address" do
      key = recovery_key(sign_up(build_conn(), "k@example.com"))
      {:ok, before} = session_of(sign_in(build_conn(), "k@example.com") |> recycle())
      new_pass = "recovered passphrase 1"

      wrong =
        post(build_conn(), ~p"/recover", %{
          "account" => %{
            "email" => "k@example.com",
            "recovery_key" => flip(key),
            "passphrase" => new_pass,
            "passphrase_confirmation" => new_pass
          }
        })

      unknown =
        post(build_conn(), ~p"/recover", %{
          "account" => %{
            "email" => "nobody@example.com",
            "recovery_key" => key,
            "passphrase" => new_pass,
            "passphrase_confirmation" => new_pass
          }
        })

      assert wrong.status == 401 and unknown.status == 401
      assert html_response(wrong, 401) =~ "don&#39;t match an account"
      assert html_response(unknown, 401) =~ "don&#39;t match an account"

      ok =
        post(build_conn(), ~p"/recover", %{
          "account" => %{
            "email" => "k@example.com",
            "recovery_key" => String.downcase(key),
            "passphrase" => new_pass,
            "passphrase_confirmation" => new_pass
          }
        })

      assert redirected_to(ok) == "/sign-in"
      {:ok, after_} = session_of(sign_in(build_conn(), "k@example.com", new_pass) |> recycle())
      assert after_.private_key == before.private_key
    end

    test "AC-4: there is no reset without a key, and the pages say what to do" do
      routes = Enum.map(FindependenceHostedWeb.Router.__routes__(), & &1.path)
      refute Enum.any?(routes, &(&1 =~ "reset"))

      for page <- [~p"/sign-in", ~p"/recover"] do
        assert html_response(get(build_conn(), page), 200) =~
                 "there is no way back into that account"
      end
    end
  end

  describe "REQ-185: households and invitations" do
    test "AC-1: the creator is the only member; a member can neither create nor join another" do
      a = signed_in("h1@example.com") |> start_household("Ana")
      {:ok, s} = session_of(a)
      assert Tenancy.member_names(s) == ["Ana"]
      {_, code} = new_code(a)

      assert redirected_to(
               post(a, ~p"/household", %{"household" => %{"display_name" => "Again"}})
             ) == "/"

      assert redirected_to(
               post(a, ~p"/join", %{"join" => %{"code" => code, "display_name" => "Twice"}})
             ) == "/"

      assert Repo.aggregate(Membership, :count) == 1
    end

    test "AC-2: a code is shown once to its creator, works once, expires, can be withdrawn, and is stored hashed" do
      a = signed_in("h2@example.com") |> start_household("Ana")
      {a, code} = new_code(a)
      refute html_response(get(a, ~p"/"), 200) =~ code
      {:ok, bytes} = code |> String.replace("-", "") |> Base.decode32(padding: false)

      assert Enum.all?(dump(), fn v ->
               not (is_binary(v) and :binary.match(v, bytes) != :nomatch)
             end)

      b = signed_in("h3@example.com")

      assert redirected_to(
               post(b, ~p"/join", %{"join" => %{"code" => code, "display_name" => "Ben"}})
             ) == "/"

      c = signed_in("h4@example.com")

      assert html_response(
               post(c, ~p"/join", %{"join" => %{"code" => code, "display_name" => "Cy"}}),
               422
             ) =~ "doesn&#39;t work"

      {a, expired} = new_code(a)

      Repo.update_all(Invitation,
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1) |> DateTime.truncate(:second)]
      )

      assert html_response(
               post(c, ~p"/join", %{"join" => %{"code" => expired, "display_name" => "Cy"}}),
               422
             ) =~ "doesn&#39;t work"

      {a, withdrawn} = new_code(a)

      [open] =
        Repo.all(
          from i in Invitation, where: is_nil(i.used_at) and i.expires_at > ^DateTime.utc_now()
        )

      assert redirected_to(post(a, ~p"/invitations/#{open.id}/withdraw")) == "/"

      assert html_response(
               post(c, ~p"/join", %{"join" => %{"code" => withdrawn, "display_name" => "Cy"}}),
               422
             ) =~ "doesn&#39;t work"
    end

    test "AC-2: a code lasts 72 hours" do
      a = signed_in("h5@example.com") |> start_household("Ana")
      {_, _code} = new_code(a)
      [i] = Repo.all(Invitation)
      assert_in_delta DateTime.diff(i.expires_at, i.inserted_at), 72 * 3600, 2
    end

    test "AC-3: a used, expired, withdrawn, or unknown code gets one refusal", %{conn: _} do
      c = signed_in("h6@example.com")

      unknown =
        post(c, ~p"/join", %{"join" => %{"code" => "AAAA-AAAA-AAAA-AAAA", "display_name" => "Cy"}})

      assert html_response(unknown, 422) =~ "That code doesn&#39;t work. Ask for a new one."
    end
  end

  describe "REQ-186: tenancy" do
    test "AC-1: another household's invitation is not found and nothing changes" do
      a = signed_in("t1@example.com") |> start_household("Ana")
      {_, _} = new_code(a)
      [theirs] = Repo.all(Invitation)
      b = signed_in("t2@example.com") |> start_household("Ben")

      conn = post(b, ~p"/invitations/#{theirs.id}/withdraw")
      assert html_response(conn, 404) =~ "isn&#39;t one of yours"
      assert Repo.get!(Invitation, theirs.id).withdrawn_at == nil
    end

    test "AC-2: the database refuses an invitation whose creator is in another household" do
      a = signed_in("t3@example.com") |> start_household("Ana")
      b = signed_in("t4@example.com") |> start_household("Ben")
      {:ok, sa} = session_of(a)
      {:ok, sb} = session_of(b)

      assert_raise Ecto.ConstraintError, ~r/invitations_creator_in_household/, fn ->
        Repo.insert!(%Invitation{
          household_id: sb.membership.household_id,
          created_by: sa.membership.id,
          code_hash: :crypto.strong_rand_bytes(32),
          expires_at: DateTime.add(DateTime.utc_now(), 3600) |> DateTime.truncate(:second)
        })
      end
    end
  end

  describe "REQ-190: limits" do
    test "AC-1: after 10 failures for one address, sign-in is refused alike for known and unknown addresses" do
      _ = sign_up(build_conn(), "l@example.com")

      for _ <- 1..10,
          do:
            assert(
              {:error, :unauthenticated, _} =
                Accounts.sign_in("l@example.com", "wrong wrong wrong", "c1")
            )

      assert {:error, :rate_limited, _} = Accounts.sign_in("l@example.com", @pass, "c2")
      for _ <- 1..10, do: Accounts.sign_in("ghost@example.com", "wrong wrong wrong", "c3")

      assert {:error, :rate_limited, _} =
               Accounts.sign_in("ghost@example.com", "anything at all", "c4")
    end

    test "AC-1: after 30 failures from one client, it is refused for any address" do
      for n <- 1..30, do: Accounts.sign_in("x#{n}@example.com", "wrong wrong wrong", "one client")

      assert {:error, :rate_limited, _} =
               Accounts.sign_in("fresh@example.com", "whatever passphrase", "one client")
    end

    test "AC-2: at most 5 open codes per member" do
      a = signed_in("l2@example.com") |> start_household("Ana")
      a = Enum.reduce(1..5, a, fn _, acc -> elem(new_code(acc), 0) end)
      assert html_response(post(a, ~p"/invitations"), 422) =~ "You have 5 open codes."
    end

    test "AC-1: after 10 failed recoveries for one address, recovery is refused even with the right key" do
      key = recovery_key(sign_up(build_conn(), "rl@example.com"))

      params = fn k ->
        %{
          "email" => "rl@example.com",
          "recovery_key" => k,
          "passphrase" => "a new long passphrase",
          "passphrase_confirmation" => "a new long passphrase"
        }
      end

      for _ <- 1..10,
          do:
            assert(
              {:error, :unauthenticated, _} =
                Accounts.recover(params.(flip(key)), "c#{System.unique_integer()}")
            )

      assert {:error, :rate_limited, _} = Accounts.recover(params.(key), "another client")
    end

    test "AC-3: a request body over the stated limit (100 kB) is refused" do
      # a raw form body, so the endpoint's parser reads it (a params map would skip the parser)
      body = "account%5Bemail%5D=" <> String.duplicate("a", 200_000)

      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        build_conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(~p"/sign-in", body)
      end

      small = "account%5Bemail%5D=a%40example.com&account%5Bpassphrase%5D=x"

      assert build_conn()
             |> put_req_header("content-type", "application/x-www-form-urlencoded")
             |> post(~p"/sign-in", small)
             |> Map.get(:status) == 401

      assert Plug.Exception.status(%Plug.Parsers.RequestTooLargeError{}) == 413
    end
  end

  describe "REQ-191: audit" do
    test "AC-1: each audited operation writes one record with identifiers, operation, time, channel, and outcome only" do
      a = signed_in("au@example.com") |> start_household("Ana")
      {a, _} = new_code(a)
      _ = post(a, ~p"/sign-out")
      _ = sign_in(build_conn(), "au@example.com", "wrong wrong wrong")

      ops = Repo.all(from e in AuditEvent, order_by: e.id, select: {e.operation, e.outcome})

      assert ops == [
               {"sign_up", "ok"},
               {"sign_in", "ok"},
               {"household_created", "ok"},
               {"invitation_created", "ok"},
               {"sign_out", "ok"},
               {"sign_in", "refused"}
             ]

      assert AuditEvent.__schema__(:fields) == [
               :id,
               :at,
               :account_id,
               :household_id,
               :operation,
               :resource_id,
               :channel,
               :outcome
             ]
    end

    test "AC-1: the other foundation operations each write one record, with its identifiers" do
      key = recovery_key(sign_up(build_conn(), "au2@example.com"))
      a = sign_in(build_conn(), "au2@example.com") |> recycle() |> start_household("Ana")
      {:ok, sa} = session_of(a)
      household = sa.membership.household_id
      {a, code} = new_code(a)
      {a, _} = new_code(a)
      b = signed_in("au3@example.com")
      _ = post(b, ~p"/join", %{"join" => %{"code" => code, "display_name" => "Ben"}})
      [open] = Repo.all(from i in Invitation, where: is_nil(i.used_at))
      _ = post(a, ~p"/invitations/#{open.id}/withdraw")

      # a second session, revoked by the passphrase change; then this one ends idle
      other = sign_in(build_conn(), "au2@example.com") |> recycle()
      new_pass = "a changed passphrase"

      _ =
        post(a, ~p"/passphrase", %{
          "account" => %{
            "current" => @pass,
            "passphrase" => new_pass,
            "passphrase_confirmation" => new_pass
          }
        })

      assert :none = session_of(other)
      token = token_of(a)
      [{^token, data}] = :ets.lookup(FindependenceHosted.Sessions, token)

      :ets.insert(
        FindependenceHosted.Sessions,
        {token, %{data | touched: data.touched - 16 * 60 * 1000}}
      )

      :ok = Sessions.sweep()

      :ok =
        Accounts.recover(
          %{
            "email" => "au2@example.com",
            "recovery_key" => key,
            "passphrase" => "a recovered passphrase",
            "passphrase_confirmation" => "a recovered passphrase"
          },
          "t"
        )

      account = account_for("au2@example.com").id
      mine = Repo.all(from e in AuditEvent, where: e.account_id == ^account, order_by: e.id)
      ops = Enum.map(mine, &{&1.operation, &1.outcome})

      for op <- ~w(invitation_withdrawn passphrase_changed recovery),
          do: assert(Enum.count(ops, &(&1 == {op, "ok"})) == 1, op)

      # the revoked session and the idle one
      assert Enum.count(ops, &(&1 == {"session_ended", "ok"})) == 2

      assert Enum.all?(
               Enum.filter(mine, &(&1.operation == "session_ended")),
               &(&1.household_id == household)
             )

      [used] =
        Repo.all(
          from e in AuditEvent, where: e.operation == "invitation_used" and e.outcome == "ok"
        )

      assert used.household_id == household and used.resource_id == code_id(code)

      for e <- Repo.all(AuditEvent), do: assert(e.at && e.channel && e.outcome in ~w(ok refused))
    end

    test "AC-2: the only telemetry handlers are Phoenix's and LiveView's loggers; no reporter records events" do
      # Phoenix's and Ecto's events carry the conn and query parameters in memory (DEF-060); what could keep
      # them is a handler. The loggers write through Logger, whose output the next test inspects.
      modules =
        for h <- :telemetry.list_handlers([]), uniq: true do
          case h.id do
            {m, _} when is_atom(m) -> m
            other -> other
          end
        end

      assert Enum.sort(modules) == [Phoenix.LiveView.Logger, Phoenix.Logger]

      assert FindependenceHostedWeb.Telemetry
             |> Supervisor.which_children()
             |> Enum.all?(fn {id, _, _, _} -> id == :telemetry_poller end)
    end

    test "AC-2: no audit record or log line holds an address, passphrase, name, key, or code" do
      # at debug, the most the system logs; the test configuration's level would hide what is logged there
      level = Logger.level()
      Logger.configure(level: :debug)
      new_pass = "a changed passphrase"

      {log, secrets} =
        try do
          ExUnit.CaptureLog.with_log([level: :debug], fn ->
            key = recovery_key(sign_up(build_conn(), "log@example.com"))
            _ = sign_in(build_conn(), "log@example.com", "a wrong passphrase")
            a = signed_in("log2@example.com") |> start_household("Secret Name")
            token = token_of(a)
            {:ok, %{private_key: priv}} = Sessions.fetch(token)
            {a, code} = new_code(a)
            b = signed_in("log3@example.com")
            _ = post(b, ~p"/join", %{"join" => %{"code" => code, "display_name" => "Other Name"}})

            _ =
              post(a, ~p"/passphrase", %{
                "account" => %{
                  "current" => @pass,
                  "passphrase" => new_pass,
                  "passphrase_confirmation" => new_pass
                }
              })

            _ =
              post(build_conn(), ~p"/recover", %{
                "account" => %{
                  "email" => "log@example.com",
                  "recovery_key" => key,
                  "passphrase" => "a recovered passphrase",
                  "passphrase_confirmation" => "a recovered passphrase"
                }
              })

            [
              "log@example.com",
              "log2@example.com",
              "log3@example.com",
              @pass,
              new_pass,
              "a wrong passphrase",
              "a recovered passphrase",
              "Secret Name",
              "Other Name",
              key,
              code,
              token,
              Base.encode64(priv),
              Base.encode16(priv, case: :lower),
              inspect(priv)
            ]
          end)
        after
          Logger.configure(level: level)
        end
        |> then(fn {secrets, log} -> {log, secrets} end)

      # the capture saw the requests, so an empty log does not pass by accident
      assert log =~ "POST /sign-up"
      for secret <- secrets, do: refute(log =~ secret, "the log holds a secret")

      audit = inspect(Repo.all(AuditEvent))
      for secret <- secrets, do: refute(audit =~ secret)
      assert "sign_in" in Audit.operations()
    end
  end
end
