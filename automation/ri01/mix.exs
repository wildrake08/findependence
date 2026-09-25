defmodule RI01.MixProject do
  use Mix.Project

  def project do
    [
      app: :ri01,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      deps: [{:yaml_elixir, "~> 2.11"}]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end
