defmodule FindependenceHosted.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FindependenceHostedWeb.Telemetry,
      # WI-073: the database (REV-098), sessions holding keys in memory (REQ-183), and attempt limits (REQ-190)
      FindependenceHosted.Repo,
      # WI-081: a production server whose database role could change the schema or the audit doesn't start
      FindependenceHosted.DbRoles,
      FindependenceHosted.Sessions,
      FindependenceHosted.Limits,
      # WI-075: one-time form tokens (REQ-165)
      FindependenceHosted.Forms,
      # WI-077: each node that connects (an operator's remote console) is audited (REQ-191)
      FindependenceHosted.OperatorAccess,
      {Phoenix.PubSub, name: FindependenceHosted.PubSub},
      # Start a worker by calling: FindependenceHosted.Worker.start_link(arg)
      # {FindependenceHosted.Worker, arg},
      # Start to serve requests, typically the last entry
      FindependenceHostedWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FindependenceHosted.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FindependenceHostedWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
