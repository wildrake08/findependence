import Config

# WI-072: the shared contexts reach this form's canonical state (the vault) through its persistence.
config :findependence_shared, persistence: FindependenceApp.Operation
