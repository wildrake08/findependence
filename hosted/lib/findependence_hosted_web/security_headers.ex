defmodule FindependenceHostedWeb.SecurityHeaders do
  @moduledoc """
  Sets Phoenix's secure browser headers and the Content-Security-Policy on every response,
  static files and errors included (ARCH-001 9.4). Sources are only 'self' and 'none': the
  LiveView script and its socket come from the app's own origin; no 'unsafe-eval', and no
  'unsafe-inline' for scripts or styles. Images allow data: for the icon masks Tailwind
  generates from heroicons.
  """
  @behaviour Plug

  @csp Enum.join(
         [
           "default-src 'none'",
           "script-src 'self'",
           "connect-src 'self'",
           "style-src 'self'",
           "img-src 'self' data:",
           "font-src 'self'",
           "form-action 'self'",
           "base-uri 'none'",
           "frame-ancestors 'none'",
           "object-src 'none'"
         ],
         "; "
       )

  def csp, do: @csp

  # WI-079: no page uses a device feature, so each is refused outright
  @permissions "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()"

  @doc "The headers set on every response, beyond Phoenix's defaults."
  def headers,
    do: %{
      "content-security-policy" => @csp,
      "referrer-policy" => "no-referrer",
      "permissions-policy" => @permissions
    }

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Phoenix.Controller.put_secure_browser_headers(conn, headers())
  end
end
