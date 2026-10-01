defmodule FindependenceHosted.WI079AccountsTest do
  @moduledoc """
  WI-079 (the security assessment's FND-03): a recovery key used to work forever, through passphrase changes,
  and could not be replaced, so anyone who had once seen it could take the account over at any time. Now a
  signed-in member can replace it (REQ-184 AC-5), and a recovery replaces the key it used (AC-6).
  """
  use FindependenceHostedWeb.ConnCase, async: false

  alias FindependenceHosted.TestAccount

  alias FindependenceHosted.{Accounts, Limits, Sessions}

  @pass "a long passphrase 1"

  setup do
    Limits.reset()
    :ok
  end

  defp sign_up(label) do
    conn =
      post(build_conn(), ~p"/sign-up", %{
        "account" => %{
          "passphrase" => @pass,
          "passphrase_confirmation" => @pass,
          "disclosure" => "true"
        }
      })

    TestAccount.remember(label, html_response(conn, 200))
    key_on(conn)
  end

  defp key_on(conn) do
    [_, key] = Regex.run(~r/id="recovery-key"[^>]*>\s*([A-Z2-7-]+)\s*</, html_response(conn, 200))
    key
  end

  defp signed_in(email, pass \\ @pass) do
    conn =
      post(build_conn(), ~p"/sign-in", %{
        "account" => %{"account_number" => TestAccount.number(email), "passphrase" => pass}
      })

    assert redirected_to(conn) == "/"
    recycle(conn)
  end

  defp recover(email, key, new_pass),
    do:
      Accounts.recover(
        %{
          "account_number" => TestAccount.number(email),
          "recovery_key" => key,
          "passphrase" => new_pass,
          "passphrase_confirmation" => new_pass
        },
        "test"
      )

  defp token_of(conn) do
    conn
    |> bypass_through(FindependenceHostedWeb.Router, [:browser])
    |> get("/")
    |> get_session(:token)
  end

  test "the assessment's case: a key seen once no longer works once the member replaces it" do
    old = sign_up("ana@example.com")
    ana = signed_in("ana@example.com")
    other = signed_in("ana@example.com")

    conn = post(ana, ~p"/recovery-key", %{"account" => %{"current" => @pass}})
    new = key_on(conn)
    assert new != old
    assert html_response(conn, 200) =~ "Your old recovery key no longer works"

    # every other session of the account ended; this one carries on
    assert {:ok, _} = Sessions.fetch(token_of(ana))
    assert redirected_to(get(other, ~p"/")) == "/sign-in"

    assert {:error, :unauthenticated, _} = recover("ana@example.com", old, "someone else's pass")
    assert {:ok, _} = recover("ana@example.com", new, "ana's own new pass")
  end

  test "replacing the key needs the passphrase; a wrong one changes nothing" do
    old = sign_up("ben@example.com")
    ben = signed_in("ben@example.com")

    conn = post(ben, ~p"/recovery-key", %{"account" => %{"current" => "not the passphrase"}})
    assert html_response(conn, 422) =~ "That isn&#39;t your passphrase."
    assert {:ok, _} = recover("ben@example.com", old, "ben's new passphrase")
  end

  test "a recovery replaces the key it used, and shows the new one once" do
    old = sign_up("cy@example.com")

    conn =
      post(build_conn(), ~p"/recover", %{
        "account" => %{
          "account_number" => TestAccount.number("cy@example.com"),
          "recovery_key" => old,
          "passphrase" => "cy's recovered pass",
          "passphrase_confirmation" => "cy's recovered pass"
        }
      })

    new = key_on(conn)
    assert new != old
    assert html_response(conn, 200) =~ "The recovery key you used no longer works"

    assert {:error, :unauthenticated, _} = recover("cy@example.com", old, "a second recovery!")
    assert {:ok, _} = recover("cy@example.com", new, "a second recovery!")
    _ = signed_in("cy@example.com", "a second recovery!")
  end

  test "the replacement page is only for a signed-in member" do
    assert redirected_to(get(build_conn(), ~p"/recovery-key")) == "/sign-in"
  end

  test "more than 10 sign-ups from one client in 15 minutes are refused (REQ-190 AC-5)" do
    for n <- 1..10, do: sign_up("many#{n}@example.com")

    conn =
      post(build_conn(), ~p"/sign-up", %{
        "account" => %{
          "passphrase" => @pass,
          "passphrase_confirmation" => @pass,
          "disclosure" => "true"
        }
      })

    assert html_response(conn, 429) =~ "Too many sign-ups from here"

    assert FindependenceHosted.Repo.aggregate(FindependenceHosted.Schemas.Account, :count) == 10
  end

  test "a session ends 12 hours after sign-in however it is used" do
    sign_up("dee@example.com")
    dee = signed_in("dee@example.com")
    token = token_of(dee)
    assert {:ok, _} = Sessions.fetch(token)

    # the session started 13 hours ago and was used a moment ago
    FindependenceHosted.Sessions.backdate(token, :started, 13 * 3_600_000)

    conn = get(dee, ~p"/")
    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "signed in 12 hours ago"
    assert Sessions.fetch(token) == :none

    prod = Config.Reader.read!("config/config.exs", env: :prod)
    assert prod[:findependence_hosted][:sessions][:max_ms] == 12 * 60 * 60 * 1000
  end

  test "the database refuses to change or remove an audit record (FND-13)" do
    sign_up("eve@example.com")
    alias FindependenceHosted.{Repo, Schemas.AuditEvent}
    assert Repo.aggregate(AuditEvent, :count) > 0

    assert_raise Postgrex.Error, ~r/only ever added/, fn ->
      Repo.update_all(AuditEvent, set: [outcome: "ok"])
    end

    assert_raise Postgrex.Error, ~r/only ever added/, fn -> Repo.delete_all(AuditEvent) end
  end
end
