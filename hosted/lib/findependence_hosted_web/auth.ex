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

      {:ended, :idle} ->
        conn
        |> configure_session(drop: true)
        |> put_flash(:info, "You were signed out after 15 minutes without activity.")
        |> assign(:token, nil)
        |> assign(:current, nil)

      :none ->
        conn |> assign(:token, nil) |> assign(:current, nil)
    end
  end

  @doc "Lets only a signed-in person through; others go to the sign-in page."
  def require_signed_in(conn, _opts) do
    if conn.assigns.current,
      do: conn,
      else: conn |> redirect(to: "/sign-in") |> halt()
  end

  @doc "The client's address, for attempt limits (REQ-190); never logged or stored."
  def client(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
