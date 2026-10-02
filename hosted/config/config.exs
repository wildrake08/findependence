# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :findependence_hosted,
  ecto_repos: [FindependenceHosted.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# WI-073: key derivation for passphrases (REQ-118: PBKDF2-HMAC-SHA256, at least 600,000 iterations)
config :findependence_hosted, :kdf, iterations: 600_000

# The shared contexts reach this form's state through its persistence (WI-074, REV-083 D2)
config :findependence_shared, persistence: FindependenceHosted.Operation

# REQ-201 (CP-030 A, WI-088): sharing, giving away, and deleting wait 72 hours once every owner has agreed
config :findependence_shared, cooling_seconds: 72 * 3600

# WI-073: sessions end after 15 idle minutes (REQ-183); the sweep runs every 5 seconds
config :findependence_hosted, :sessions,
  idle_ms: 15 * 60 * 1000,
  sweep_ms: 5_000,
  # WI-079: a session ends 12 hours after sign-in however it is used
  max_ms: 12 * 60 * 60 * 1000

# Configure the endpoint
config :findependence_hosted, FindependenceHostedWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FindependenceHostedWeb.ErrorHTML, json: FindependenceHostedWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FindependenceHosted.PubSub,
  live_view: [signing_salt: "UgTuLHs0"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  findependence_hosted: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# WI-079 (FND-21): the SHA-256 of each downloaded Tailwind binary, checked by mix findependence.verify_tools.
# WI-081: each equals the digest Tailwind publishes for v4.3.3 (the release's sha256sums.txt and GitHub's asset
# digests, which agree), checked 2026-10-01.
config :findependence_hosted, :tool_hashes, %{
  "tailwind-linux-arm64-4.3.3" =>
    "55fd0b241214eff3de1e8ee4f22796662f2d2e7a49bcfca7477cfd0bac398195",
  "tailwind-linux-x64-4.3.3" =>
    "dc61b3ac6b8c9ca874c0cc4c57b2409791a64c5540404ca5f5367360babc313a",
  "tailwind-macos-arm64-4.3.3" =>
    "cdf646702987a743464dff4d9c60fd4480d1c1e73dd819a9a67f1078815dce9d",
  "tailwind-macos-x64-4.3.3" =>
    "7922e0953f2110c05976e3bf58f14e643d90427575e766b7d433f5f80cbee7e1",
  "tailwind-windows-x64.exe-4.3.3" =>
    "e0e260ce048014e9268f6237ff18f8ccf02cef521cbd0ae04e82c2cdf7aa3955"
}

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  findependence_hosted: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# No request parameter's value is logged, in any environment: forms carry email addresses, passphrases,
# recovery keys, invitation codes, and names (REQ-191 AC-2; WI-073 may_not). Phoenix's default filters only
# "password".
config :phoenix, :filter_parameters, {:keep, []}

# Nor are queries: their parameters include names (REQ-191 AC-2).
config :findependence_hosted, FindependenceHosted.Repo, log: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
