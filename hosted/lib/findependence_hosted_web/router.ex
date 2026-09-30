defmodule FindependenceHostedWeb.Router do
  use FindependenceHostedWeb, :router

  @csp FindependenceHostedWeb.SecurityHeaders.csp()

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FindependenceHostedWeb.Layouts, :root}

    # the local form's answer to an out-of-date form (WI-075, REQ-165), then the check that enforces CSRF
    plug :csrf
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
    # REQ-158 (WI-076): going to any other page drops a waiting bring-in file
    plug :leave_bring_in
  end

  # WI-075: the domain pages need a household; household-changing forms are sent once (REQ-165)
  pipeline :household do
    plug :require_household
    plug :once_only
  end

  defp leave_bring_in(conn, opts), do: FindependenceHostedWeb.FormGuard.leave_bring_in(conn, opts)

  defp csrf(conn, opts), do: FindependenceHostedWeb.FormGuard.csrf(conn, opts)
  defp once_only(conn, opts), do: FindependenceHostedWeb.FormGuard.once_only(conn, opts)

  defp require_household(conn, _opts) do
    if conn.assigns.current.membership,
      do: conn,
      else: conn |> Phoenix.Controller.redirect(to: "/") |> halt()
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

    get "/", HomeController, :index
    get "/household", HouseholdController, :home
    post "/sign-out", AccountController, :sign_out
    get "/passphrase", AccountController, :passphrase_page
    post "/passphrase", AccountController, :change_passphrase
    post "/household", HouseholdController, :create
    post "/join", HouseholdController, :join
    post "/invitations", HouseholdController, :invite
    post "/invitations/:id/withdraw", HouseholdController, :withdraw
    get "/account/delete", AccountController, :delete_page
    post "/account/delete", AccountController, :delete
  end

  # WI-075: the domain pages (REV-100), one per local route
  scope "/", FindependenceHostedWeb do
    pipe_through [:browser, :signed_in, :household]

    post "/leave", PortabilityController, :leave
    get "/leave", PortabilityController, :leave_page
    # WI-076: plans and requests
    get "/plans", PlanController, :index
    get "/plans/:id", PlanController, :show
    get "/requests/:id", PlanController, :request
    post "/act/new_plan", PlanController, :new_plan
    post "/act/share_plan", PlanController, :share_plan
    post "/act/plan_step", PlanController, :plan_step
    post "/act/remove_step", PlanController, :remove_step
    post "/act/delete_plan", PlanController, :delete_plan
    post "/confirm/delete_plan", PlanController, :confirm_delete
    # WI-076: goals, set-asides, retirement
    get "/goals", GoalsController, :index
    get "/retirement", GoalsController, :retirement
    post "/act/fund_goal", GoalsController, :fund_goal
    post "/act/set_aside", GoalsController, :set_aside
    post "/act/retirement", GoalsController, :save_retirement
    # WI-076: export, bring-in, and letting go on the leave checklist
    get "/export", PortabilityController, :export
    get "/export.json", PortabilityController, :export_json
    get "/bring-in", PortabilityController, :bring_in
    post "/act/bring-in", PortabilityController, :check_file
    post "/act/bring-in/confirm", PortabilityController, :confirm_bring_in
    post "/act/bring-in/cancel", PortabilityController, :cancel_bring_in
    post "/act/let_go", PortabilityController, :let_go
    get "/items/:id", ItemController, :show
    get "/next-60-days", FlowController, :next_60_days
    get "/ahead", FlowController, :ahead
    get "/balances/new", FlowController, :new_balance
    post "/act/add_item", HomeController, :add_item
    post "/act/add_account", FlowController, :add_account
    post "/act/add_debt", FlowController, :add_debt
    post "/act/add_reading", ItemController, :add_reading
    post "/confirm/:action", ItemController, :confirm
    post "/act/:action", ActionController, :act
  end

  scope "/health", FindependenceHostedWeb do
    pipe_through :probe

    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end
end
