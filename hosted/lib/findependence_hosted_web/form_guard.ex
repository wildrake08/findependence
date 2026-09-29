defmodule FindependenceHostedWeb.FormGuard do
  @moduledoc """
  What happens to a form that is out of date or sent again (WI-075, REV-100 H5; REQ-165, REQ-183 AC-3), as the
  local form's router does it:

  - `csrf/2` checks the CSRF token as Phoenix's `protect_from_forgery` does. A form from a page opened before
    the session ended is refused with a page that says nothing was saved (the local form's DEF-035), unless
    this member already saved it, when it goes where it went and says so, or it was a Leave that was done.
  - `once_only/2`: every household-changing form carries a one-time token (`_form`). A repeat goes where the
    first went and says "That was already saved."; a second sending while the first is handled is told to check
    it was saved; a sending that changed nothing frees its token. A signed-in household-changing request
    without a token can't be checked, so it is refused as out of date (the local form's DEF-041).

  A controller marks a change that happened with `changed/1`, so the token is kept for repeats.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias FindependenceHosted.{Forms, Sessions}

  @csrf Plug.CSRFProtection.init([])

  def csrf(conn, _opts) do
    Plug.CSRFProtection.call(conn, @csrf)
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError -> stale(conn)
  end

  defp stale(conn) do
    form = conn.body_params["_form"]

    mid =
      case Sessions.fetch(get_session(conn, :token)) do
        {:ok, %{membership: %{id: mid}}} -> mid
        _ -> nil
      end

    cond do
      Forms.left?(form) ->
        conn
        |> put_flash(:info, "You have left the household. That was already done.")
        |> redirect(to: "/sign-in")
        |> halt()

      where = Forms.saved(mid, form) ->
        conn |> put_flash(:info, "That was already saved.") |> redirect(to: where) |> halt()

      true ->
        refuse(conn)
    end
  end

  @doc "The page for a form that was out of date: nothing was saved."
  def refuse(conn) do
    conn
    |> FindependenceHostedWeb.Auth.call([])
    |> put_status(403)
    |> put_view(html: FindependenceHostedWeb.StaleHTML)
    |> put_layout(false)
    |> render(:stale)
    |> halt()
  end

  # As the local form: forms that change the household (under /act/, and Leave); a confirmation page's request
  # changes nothing and is not checked.
  def once_only(%{method: "POST", request_path: "/act/" <> _} = conn, opts),
    do: check_once(conn, opts)

  def once_only(%{method: "POST", request_path: "/leave"} = conn, opts),
    do: check_once(conn, opts)

  def once_only(conn, _opts), do: conn

  defp check_once(conn, _opts) do
    token = conn.assigns[:token]
    current = conn.assigns[:current]
    form = conn.body_params["_form"]

    cond do
      current == nil ->
        conn

      form in [nil, ""] ->
        refuse(conn)

      true ->
        mid = current.membership && current.membership.id

        case Forms.claim(token, mid, form) do
          :fresh ->
            register_before_send(conn, &settle(&1, token, mid, form))

          {:repeat, where} ->
            conn |> put_flash(:info, "That was already saved.") |> redirect(to: where) |> halt()

          :busy ->
            conn
            |> put_flash(:info, "That was already sent. Check below that it was saved.")
            |> redirect(to: "/")
            |> halt()
        end
    end
  end

  @doc "Marks that this request changed the household, so its form is remembered."
  def changed(conn), do: put_private(conn, :fv_changed, true)

  defp settle(conn, token, mid, form) do
    where = if conn.private[:fv_changed], do: conn |> get_resp_header("location") |> List.first()
    Forms.settle(token, mid, form, where)
    conn
  end
end
