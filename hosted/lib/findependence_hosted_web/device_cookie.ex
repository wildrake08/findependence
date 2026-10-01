defmodule FindependenceHostedWeb.DeviceCookie do
  @moduledoc """
  WI-080 (REQ-190 AC-1 as CP-025 amends it; ASSESS-001 FND-06, after OWASP's "device cookies"): after a
  successful sign-in the browser keeps a signed, HttpOnly cookie naming the account, for 90 days. A later
  sign-in to that account from this browser isn't held back by failures for the address from other clients,
  so someone guessing elsewhere can't lock the owner out on a device they have used. The cookie holds only the
  account's random id, signed with the endpoint's secret; it is no credential, since the passphrase is still
  needed.
  """
  import Plug.Conn

  @cookie "_findependence_device"
  @salt "findependence device v1"
  @max_age 90 * 24 * 60 * 60

  @doc "The account id a valid device cookie on the request names, or nil."
  def account_id(conn) do
    conn = fetch_cookies(conn)

    with value when is_binary(value) <- conn.req_cookies[@cookie],
         {:ok, id} <- Phoenix.Token.verify(conn, @salt, value, max_age: @max_age) do
      id
    else
      _ -> nil
    end
  end

  @doc "Gives the browser a device cookie for `account_id`."
  def put(conn, account_id) do
    put_resp_cookie(conn, @cookie, Phoenix.Token.sign(conn, @salt, account_id),
      max_age: @max_age,
      http_only: true,
      same_site: "Lax",
      secure: Application.get_env(:findependence_hosted, :secure_cookies, true)
    )
  end
end
