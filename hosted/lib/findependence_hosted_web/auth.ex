defmodule FindependenceHostedWeb.Auth do
  @moduledoc """
  The trusted session for a request (ARCH-003 7, 16; REQ-183). The cookie holds only a signed session token;
  the session itself, with the member's unwrapped key, is held in server memory (`FindependenceHosted.Sessions`).
  A session ended by the idle sweep says so on the next request (REQ-183 AC-1).
  """
  import Plug.Conn
  import Phoenix.Controller
  alias FindependenceHosted.Sessions

  def init(opts), do: opts

  def call(conn, _opts) do
    token = get_session(conn, :token)

    case Sessions.fetch(token) do
      {:ok, session} ->
        conn |> assign(:token, token) |> assign(:current, session)

      {:ended, :idle, mid} ->
        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_flash(:info, idle_message(conn, mid))
        |> assign(:token, nil)
        |> assign(:current, nil)

      :none ->
        conn |> assign(:token, nil) |> assign(:current, nil)
    end
  end

  # REQ-165 AC-3 (as the local form's lock notices): a form sent after the idle end is told whether it was
  # already saved, or that it wasn't.
  defp idle_message(%{method: "POST", body_params: %{"_form" => form}}, mid)
       when is_binary(form) do
    if FindependenceHosted.Forms.saved(mid, form),
      do:
        "You were signed out after 15 minutes without activity. That was already saved. Sign in to carry on.",
      else:
        "You were signed out after 15 minutes without activity. Your last action was not saved. Sign in and do it again."
  end

  defp idle_message(_conn, _mid), do: "You were signed out after 15 minutes without activity."

  @doc "Lets only a signed-in person through; others go to the sign-in page."
  def require_signed_in(conn, _opts) do
    if conn.assigns.current,
      do: conn,
      else: conn |> redirect(to: "/sign-in") |> halt()
  end

  @doc "The client's address, for attempt limits (REQ-190); never logged or stored."
  def client(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
