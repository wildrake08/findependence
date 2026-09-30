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

      # WI-079: a session older than 12 hours ends however it's used
      {:ended, :expired, mid} ->
        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_flash(:info, expired_message(conn, mid))
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

  defp expired_message(%{method: "POST", body_params: %{"_form" => form}}, mid)
       when is_binary(form) do
    if FindependenceHosted.Forms.saved(mid, form),
      do:
        "You were signed out because you signed in 12 hours ago. That was already saved. Sign in to carry on.",
      else:
        "You were signed out because you signed in 12 hours ago. Your last action was not saved. Sign in and do it again."
  end

  defp expired_message(_conn, _mid),
    do: "You were signed out because you signed in 12 hours ago. Sign in to carry on."

  @doc "Lets only a signed-in person through; others go to the sign-in page."
  def require_signed_in(conn, _opts) do
    if conn.assigns.current,
      do: conn,
      else: conn |> redirect(to: "/sign-in") |> halt()
  end

  @doc """
  The client's address, for attempt limits (REQ-190); never logged or stored. Behind a reverse proxy every
  connection comes from the proxy, so the limits would count everyone together (the assessment's FND-09): when
  the connection comes from a proxy the deployment lists as trusted (`:trusted_proxies`, from TRUSTED_PROXIES),
  the client is the nearest address in X-Forwarded-For that isn't a trusted proxy. A forwarded header from
  anyone else is ignored.
  """
  def client(conn) do
    proxies = Application.get_env(:findependence_hosted, :trusted_proxies, [])

    ip =
      if trusted?(conn.remote_ip, proxies) do
        conn
        |> get_req_header("x-forwarded-for")
        |> Enum.flat_map(&String.split(&1, ","))
        |> Enum.map(&String.trim/1)
        |> Enum.reverse()
        |> Enum.map(&:inet.parse_strict_address(to_charlist(&1)))
        |> Enum.find_value(conn.remote_ip, fn
          {:ok, ip} -> if not trusted?(ip, proxies), do: ip
          _ -> nil
        end)
      else
        conn.remote_ip
      end

    ip |> :inet.ntoa() |> to_string()
  end

  # a list of {address tuple, prefix length}
  defp trusted?(ip, proxies), do: Enum.any?(proxies, &in_range?(ip, &1))

  defp in_range?(ip, {net, bits}) when tuple_size(ip) == tuple_size(net) do
    size = if tuple_size(ip) == 4, do: 8, else: 16
    to_bits = fn t -> for(x <- Tuple.to_list(t), into: <<>>, do: <<x::size(size)>>) end
    <<a::bitstring-size(^bits), _::bitstring>> = to_bits.(ip)
    <<b::bitstring-size(^bits), _::bitstring>> = to_bits.(net)
    a == b
  end

  defp in_range?(_ip, _range), do: false
end
