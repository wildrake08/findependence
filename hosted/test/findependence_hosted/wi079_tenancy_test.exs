defmodule FindependenceHosted.WI079TenancyTest do
  @moduledoc """
  WI-079 (the security assessment's FND-07 and its F-4 note): an invitation code is claimed inside the joining
  transaction, and a session opened before its account joined or started a household is refused cleanly
  rather than failing on the database's one-membership-per-account index. The concurrent case is shown against
  a running server (the sandbox serializes connections); these tests cover the refusals it relies on.
  """
  use FindependenceHostedWeb.ConnCase, async: false

  alias FindependenceHosted.TestAccount

  import Ecto.Query, only: [from: 2]
  alias FindependenceHosted.{Limits, Repo}
  alias FindependenceHosted.Schemas.{Invitation, Membership}

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
    conn
  end

  defp signed_in(email) do
    conn =
      post(build_conn(), ~p"/sign-in", %{
        "account" => %{"account_number" => TestAccount.number(email), "passphrase" => @pass}
      })

    assert redirected_to(conn) == "/"
    recycle(conn)
  end

  defp new_code(conn) do
    conn = post(conn, ~p"/invitations")
    [_, code] = Regex.run(~r/id="new-code"[^>]*>\s*([A-Z2-7-]+)\s*</, html_response(conn, 200))
    {recycle(conn), code}
  end

  defp join_with(conn, code, name),
    do: post(conn, ~p"/join", %{"join" => %{"code" => code, "display_name" => name}})

  defp host_with_codes(n) do
    _ = sign_up("host@example.com")
    host = signed_in("host@example.com")
    host = post(host, ~p"/household", %{"household" => %{"display_name" => "Host"}}) |> recycle()

    Enum.map_reduce(1..n, host, fn _, conn ->
      {conn, code} = new_code(conn)
      {code, conn}
    end)
    |> elem(0)
  end

  defp memberships_of(email) do
    Repo.one(
      from m in Membership,
        join: a in FindependenceHosted.Schemas.Account,
        on: a.id == m.account_id,
        where:
          a.number_hmac == ^FindependenceHosted.Accounts.number_hmac(TestAccount.number(email)),
        select: count()
    )
  end

  test "a second session of an account that already joined is sent home, not failed, and uses no code" do
    [code1, code2] = host_with_codes(2)
    _ = sign_up("ben@example.com")
    first = signed_in("ben@example.com")
    second = signed_in("ben@example.com")

    assert redirected_to(join_with(first, code1, "Ben")) == "/"
    assert redirected_to(join_with(second, code2, "Benny")) == "/"

    assert memberships_of("ben@example.com") == 1
    assert Repo.aggregate(from(i in Invitation, where: not is_nil(i.used_at)), :count) == 1
  end

  test "a second session of an account that already started a household is sent home, not failed" do
    _ = sign_up("cy@example.com")
    first = signed_in("cy@example.com")
    second = signed_in("cy@example.com")

    assert redirected_to(post(first, ~p"/household", %{"household" => %{"display_name" => "Cy"}})) ==
             "/"

    assert redirected_to(
             post(second, ~p"/household", %{"household" => %{"display_name" => "Cy"}})
           ) == "/"

    assert memberships_of("cy@example.com") == 1
  end
end
