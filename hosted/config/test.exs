import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :findependence_hosted, FindependenceHostedWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "F1PCVb4gETGPBJapG8PpvNbxkQNY/j2mruG8Lsiau7ajnJxSd8GapiJdA05U+Ecu",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Cookies without the Secure flag, for plain-HTTP tests.
config :findependence_hosted, secure_cookies: false

# WI-073: the dev container's PostgreSQL service, one database per test partition, in a sandbox
config :findependence_hosted, FindependenceHosted.Repo,
  hostname: System.get_env("PGHOST", "localhost"),
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  database: "findependence_hosted_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  timeout: 15_000,
  connect_timeout: 5_000

# Tests derive keys with few iterations (the production value is checked by a test)
config :findependence_hosted, :kdf, iterations: 1_000, unsafe_test: true
config :findependence_hosted, :account_hmac_key, "test-only account number hmac key"
config :findependence_hosted, :passphrase_pepper, "test-only passphrase pepper, 32 bytes+"
config :findependence_hosted, :household_state_key, "test-only household state key, 32 bytes"

# WI-086 (REQ-198 AC-5): the change ledger outside the database, a fresh file for each test run
config :findependence_hosted,
       :household_ledger_path,
       Path.join(
         System.tmp_dir!(),
         "findependence-ledger-#{System.pid()}-#{System.unique_integer([:positive])}"
       )

# the design specimen LiveView is routed only outside production (WI-079)
config :findependence_hosted, :specimen_route, true

# WI-088: the suite checks the rules without the cooling-off; its own tests turn it on
config :findependence_shared, cooling_seconds: 0
