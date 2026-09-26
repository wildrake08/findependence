defmodule FindependenceApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :findependence_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [
        {:findependence_core, path: "../core"},
        {:plug, "~> 1.16"},
        {:bandit, "~> 1.5"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end
