defmodule FindependenceHostedWeb.Router do
  use FindependenceHostedWeb, :router

  @csp FindependenceHostedWeb.SecurityHeaders.csp()

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FindependenceHostedWeb.Layouts, :root}
    plug :protect_from_forgery

    # The endpoint already sets these on every response; repeated here so the pipeline states them.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => @csp,
      "referrer-policy" => "no-referrer"
    }
  end

  pipeline :probe do
    plug :accepts, ["text"]
  end

  scope "/", FindependenceHostedWeb do
    pipe_through :browser

    live "/", SpecimenLive
  end

  scope "/health", FindependenceHostedWeb do
    pipe_through :probe

    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end
end
