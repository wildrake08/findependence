import Config

# WI-072: the shared contexts reach this form's canonical state (the vault) through its persistence.
config :findependence_shared, persistence: FindependenceApp.Operation

# REQ-201 (CP-030 A, WI-088): sharing, giving away, and deleting wait 72 hours once every owner has agreed. The
# test suite checks the rules without it; its own tests turn it on (FindependenceShared.Clock).
config :findependence_shared, cooling_seconds: if(config_env() == :test, do: 0, else: 72 * 3600)
