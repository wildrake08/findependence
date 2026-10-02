defmodule FindependenceHostedWeb.DomainCase do
  @moduledoc """
  Page tests for the hosted form's domain pages (WI-075, REV-100 H4): a household whose members are each signed
  in through a browser session, and helpers to act through the shared contexts as a member. Use it as

      use FindependenceHostedWeb.DomainCase

  and then `h = household(~w(ana ben))`, `conn = h["ana"].conn`, `scope(h, "ana")`, `id(h, "ben")`, and
  `form_token()` for a household-changing form's one-time token. Today is fixed at 2026-09-29.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use FindependenceHostedWeb.ConnCase, async: false
      import FindependenceHostedWeb.DomainCase
    end
  end

  alias FindependenceHosted.{Accounts, Forms, Limits, Sessions, Tenancy}

  @pass "a long passphrase 1"
  @today ~D[2026-09-29]

  setup do
    Limits.reset()
    Forms.reset()
    Application.put_env(:findependence_hosted, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_hosted, :today) end)
    :ok
  end

  @doc "The fixed date the pages use as today."
  def today, do: @today

  @doc """
  A household with these members (display names capitalised: "ana" is "Ana"): a map from name to
  `%{conn: signed-in conn, token: session token}`. The first starts it; the others join with codes.
  """
  def household([first | rest]) do
    a = new_member(first)
    {:ok, _} = Tenancy.create_household(a.token, session(a.token), String.capitalize(first))

    others =
      for n <- rest do
        {:ok, code, _} = Tenancy.create_invitation(session(a.token))
        t = new_member(n)
        {:ok, _} = Tenancy.join(t.token, session(t.token), code, String.capitalize(n), "test")
        {n, t}
      end

    Map.new([{first, a} | others])
  end

  @doc "The member's scope on the latest state, to act through the shared contexts."
  def scope(h, name), do: Tenancy.scope(session(h[name].token))

  @doc "The member's id inside the domain rules (their membership id)."
  def id(h, name), do: session(h[name].token).membership.id

  @doc "A fresh signed-in conn for the member (the same session)."
  def conn_of(h, name), do: h[name].conn |> Phoenix.ConnTest.recycle()

  @doc """
  The named member agrees to the request waiting for them on `item` (WI-086, CP-029: nobody becomes an owner
  without agreeing).
  """
  def agree(h, name, item) do
    s = scope(h, name)
    [p] = Enum.filter(FindependenceShared.Items.pending(s), &(&1.item_id == item))
    {:ok, _} = FindependenceShared.Items.consent(s, p.id)
    :ok
  end

  @doc "A one-time form token, as each household-changing form carries (REQ-165)."
  def form_token, do: Forms.new_token()

  @doc "Posts a household-changing form as the member, with a fresh form token unless one is given."
  def act(h, name, path, params) do
    params = Map.put_new(params, "_form", form_token())

    Phoenix.ConnTest.dispatch(
      conn_of(h, name),
      FindependenceHostedWeb.Endpoint,
      :post,
      path,
      params
    )
  end

  @doc "Gets a page as the member."
  def page(h, name, path),
    do:
      Phoenix.ConnTest.dispatch(
        conn_of(h, name),
        FindependenceHostedWeb.Endpoint,
        :get,
        path,
        nil
      )

  defp new_member(_name) do
    {:ok, _, number, _} =
      Accounts.sign_up(%{
        "passphrase" => @pass,
        "passphrase_confirmation" => @pass,
        "disclosure" => "true"
      })

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(FindependenceHostedWeb.Endpoint, :post, "/sign-in", %{
        "account" => %{"account_number" => number, "passphrase" => @pass}
      })

    token =
      conn
      |> Phoenix.ConnTest.recycle()
      |> Phoenix.ConnTest.bypass_through(FindependenceHostedWeb.Router, [:browser])
      |> Phoenix.ConnTest.dispatch(FindependenceHostedWeb.Endpoint, :get, "/", nil)
      |> Plug.Conn.get_session(:token)

    %{conn: Phoenix.ConnTest.recycle(conn), token: token}
  end

  defp session(token), do: elem(Sessions.fetch(token), 1)
end
