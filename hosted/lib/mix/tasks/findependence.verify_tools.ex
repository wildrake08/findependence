defmodule Mix.Tasks.Findependence.VerifyTools do
  @shortdoc "Checks the downloaded asset build tools against their pinned SHA-256"
  @moduledoc """
      mix findependence.verify_tools

  WI-079 (the security assessment's FND-21): the Tailwind binary is downloaded at build time over TLS but
  without a checksum. This task compares it with the SHA-256 pinned in config (`:tool_hashes`) and stops the
  build on a mismatch, or when the platform's binary has no pin yet. The pins were recorded from the binaries
  in use when WI-079 was done (trust on first use; not compared with an upstream published digest). esbuild's
  own installer already checks npm's integrity digest.
  """
  use Mix.Task

  @impl true
  def run(_args) do
    pins = Application.get_env(:findependence_hosted, :tool_hashes, %{})
    build = Mix.Project.build_path() |> Path.dirname()

    for path <- Path.wildcard(Path.join(build, "tailwind-*")) do
      name = Path.basename(path)
      actual = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

      case pins[name] do
        ^actual ->
          Mix.shell().info("#{name}: SHA-256 matches its pin")

        nil ->
          Mix.raise(
            "#{name} has no pinned SHA-256 in config :tool_hashes (it is #{actual}); check it and pin it"
          )

        pinned ->
          Mix.raise("#{name} does not match its pin: #{actual}, expected #{pinned}")
      end
    end

    :ok
  end
end
