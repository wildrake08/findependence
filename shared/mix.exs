defmodule FindependenceShared.MixProject do
  use Mix.Project

  # WI-072 (REV-083 D2, ARCH-003 5 and 41): the application layer both forms share: the trusted Scope, the
  # failure categories, the domain contexts, and Crypto. It depends on the domain core only; each form
  # supplies its persistence (FindependenceShared.Persistence) in its own configuration.
  def project do
    [
      app: :findependence_shared,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:findependence_core, path: "../core"}]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end
