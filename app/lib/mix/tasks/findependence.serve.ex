defmodule Mix.Tasks.Findependence.Serve do
  @shortdoc "Serve a household vault on http://127.0.0.1:PORT only"
  @moduledoc """
    mix findependence.serve PATH [PORT]

  Listens on the loopback interface only (REQ-123). Makes no outbound connections (REQ-124).
  """
  use Mix.Task

  @impl true
  def run([path | rest]) do
    port = rest |> List.first("4848") |> String.to_integer()
    Mix.Task.run("app.start")

    {:ok, _} =
      Supervisor.start_link(
        [
          {FindependenceApp.Store, path: path},
          FindependenceApp.Sessions,
          {FindependenceApp.Web, port: port}
        ],
        strategy: :one_for_one
      )

    Mix.shell().info("Open http://127.0.0.1:#{port}/ on this device. Ctrl-C twice to stop.")
    Process.sleep(:infinity)
  end
end
