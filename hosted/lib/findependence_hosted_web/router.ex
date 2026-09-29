defmodule FindependenceHostedWeb.Router do
  use FindependenceHostedWeb, :router

  @csp FindependenceHostedWeb.SecurityHeaders.csp()

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FindependenceHostedWeb.Layouts, :root}
    plug :protect_from_forgery
    plug FindependenceHostedWeb.Auth

    # The endpoint already sets these on every response; repeated here so the pipeline states them.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => @csp,
      "referrer-policy" => "no-referrer"
    }
  end

  pipeline :signed_in do
    plug :require_signed_in
  end

  defp require_signed_in(conn, opts),
    do: FindependenceHostedWeb.Auth.require_signed_in(conn, opts)

  pipeline :probe do
    plug :accepts, ["text"]
  end

  # WI-073: accounts, sessions, and households (REQ-180..REQ-186)
  scope "/", FindependenceHostedWeb do
    pipe_through :browser

    get "/sign-up", AccountController, :new
    post "/sign-up", AccountController, :create
    get "/sign-in", AccountController, :sign_in_page
    post "/sign-in", AccountController, :sign_in
    get "/recover", AccountController, :recover_page
    post "/recover", AccountController, :recover

    # the design specimen (WI-063, WI-070); not a product feature
    live "/specimen", SpecimenLive
  end

  scope "/", FindependenceHostedWeb do
    pipe_through [:browser, :signed_in]

    get "/", HouseholdController, :home
    post "/sign-out", AccountController, :sign_out
    get "/passphrase", AccountController, :passphrase_page
    post "/passphrase", AccountController, :change_passphrase
    post "/household", HouseholdController, :create
    post "/join", HouseholdController, :join
    post "/invitations", HouseholdController, :invite
    post "/invitations/:id/withdraw", HouseholdController, :withdraw
  end

  scope "/health", FindependenceHostedWeb do
    pipe_through :probe

    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end
end
