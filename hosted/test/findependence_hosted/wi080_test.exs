defmodule FindependenceHosted.WI080Test do
  @moduledoc """
  WI-080 (REV-107; CP-025), aligning WI-079 with ASSESS-001's recommendations: the signed-in owner sees when the
  account was last recovered (REQ-184 AC-7, FND-03); guesses from other clients can't lock the owner out on a
  device the account has used (REQ-190 AC-1, FND-06); a member's changes in 15 minutes are bounded (REQ-190
  AC-6, FND-10).
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceHosted.TestAccount

  import Ecto.Query
  alias FindependenceHosted.{Accounts, Limits, Repo}
  alias FindependenceHosted.Schemas.Item

  @pass "a long passphrase 1"

  defp sign_up(label) do
    html =
      post(build_conn(), ~p"/sign-up", %{
        "account" => %{
          "passphrase" => @pass,
          "passphrase_confirmation" => @pass,
          "disclosure" => "true"
        }
      })
      |> html_response(200)

    {_number, key} = TestAccount.remember(label, html)
    key
  end

  defp sign_in(conn, email, pass \\ @pass),
    do:
      post(conn, ~p"/sign-in", %{
        "account" => %{"account_number" => TestAccount.number(email), "passphrase" => pass}
      })

  describe "REQ-184 AC-7: the last recovery is shown to the signed-in owner" do
    test "nothing before a recovery; its date after one" do
      key = sign_up("ana@example.com")
      ana = sign_in(build_conn(), "ana@example.com") |> recycle()
      refute html_response(get(ana, ~p"/household"), 200) =~ "last recovered"

      {:ok, _} =
        Accounts.recover(
          %{
            "account_number" => TestAccount.number("ana@example.com"),
            "recovery_key" => key,
            "passphrase" => "a recovered passphrase",
            "passphrase_confirmation" => "a recovered passphrase"
          },
          "elsewhere"
        )

      ana = sign_in(build_conn(), "ana@example.com", "a recovered passphrase") |> recycle()
      page = html_response(get(ana, ~p"/household"), 200)
      assert page =~ "Your account was last recovered with a recovery key on"
      assert page =~ ~s(href="/recovery-key")
    end
  end

  describe "REQ-190 AC-1: a device the account has used" do
    test "the owner's own browser signs in after 100 failures from elsewhere; other browsers don't" do
      sign_up("ben@example.com")
      # Ben signs in once on his laptop, which keeps the device cookie, and signs out
      laptop = sign_in(build_conn(), "ben@example.com")
      assert redirected_to(laptop) == "/"
      laptop = laptop |> recycle() |> post(~p"/sign-out") |> recycle()

      for n <- 1..100,
          do:
            Accounts.sign_in(
              TestAccount.number("ben@example.com"),
              "a wrong guess!!",
              "guesser #{rem(n, 25)}"
            )

      # a browser without the cookie is held back by the address's total
      assert html_response(sign_in(build_conn(), "ben@example.com"), 401) =~ "Too many attempts"
      # Ben's laptop is not
      assert redirected_to(sign_in(laptop, "ben@example.com")) == "/"
    end

    test "a device cookie for another account, or a made-up one, gives no exemption" do
      sign_up("cy@example.com")
      sign_up("dee@example.com")
      dee_device = sign_in(build_conn(), "dee@example.com") |> recycle()

      for n <- 1..100,
          do:
            Accounts.sign_in(
              TestAccount.number("cy@example.com"),
              "a wrong guess!!",
              "guesser #{rem(n, 25)}"
            )

      assert html_response(sign_in(dee_device, "cy@example.com"), 401) =~ "Too many attempts"

      made_up =
        build_conn() |> put_req_cookie("_findependence_device", "not-a-signed-token")

      assert html_response(sign_in(made_up, "cy@example.com"), 401) =~ "Too many attempts"
    end
  end

  describe "REQ-190 AC-6: a member's changes are bounded" do
    test "past 300 changes in 15 minutes, the next is refused and nothing is saved" do
      h = household(~w(ana))
      for _ <- 1..300, do: Limits.count([{:writes, id(h, "ana")}])

      conn =
        act(h, "ana", "/act/add_item", %{
          "note" => "One more",
          "amount" => "5",
          "direction" => "out",
          "frequency" => "monthly"
        })

      assert html_response(conn, 422) =~ "more changes than one person makes in 15 minutes"
      assert Repo.aggregate(from(i in Item), :count) == 0
    end
  end
end
