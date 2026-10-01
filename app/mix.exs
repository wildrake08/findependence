defmodule FindependenceApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :findependence_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      # the script that made test/fixtures/pre_signing.vault is not a test (WI-080)
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")],
      deps: [
        {:findependence_core, path: "../core"},
        {:findependence_shared, path: "../shared"},
        {:plug, "~> 1.16"},
        {:bandit, "~> 1.5"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end
