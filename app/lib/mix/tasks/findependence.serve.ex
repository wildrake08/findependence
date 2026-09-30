defmodule Mix.Tasks.Findependence.Serve do
  @shortdoc "Serve a household vault on http://127.0.0.1:PORT only"
  @moduledoc """
    mix findependence.serve PATH [PORT]

  Listens on the loopback interface only (REQ-123). Makes no outbound connections (REQ-124).
  """
  use Mix.Task

  @impl true
  def run([path | rest]) do
    unless File.exists?(path) do
      Mix.raise("""
      No household file at #{path}.
      Create one first:  mix findependence.setup #{path} NAME [NAME ...]
      """)
    end

    port = rest |> List.first("4848") |> String.to_integer()

    # WI-079 (FND-21): an uploaded export waits in a directory only this user can open
    tmp =
      Path.join(System.tmp_dir!(), "findependence-uploads-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    File.chmod!(tmp, 0o700)
    System.put_env("PLUG_TMPDIR", tmp)

    Mix.Task.run("app.start")

    # WI-079 (FND-05): crash reports never print a member's information
    FindependenceApp.LogRedaction.install()

    # WI-079 (FND-17): a file that can't be read stops here, with a message, before anything is served
    try do
      FindependenceApp.Vault.read!(path)
    rescue
      e ->
        Mix.raise(
          "The household file at #{path} can't be read (#{inspect(e.__struct__)}). " <>
            "It may have been changed outside Findependence; put back an earlier copy."
        )
    end

    {:ok, _} =
      Supervisor.start_link(
        [
          {FindependenceApp.Store, path: path},
          FindependenceApp.Sessions,
          {FindependenceApp.Web, port: port}
        ],
        strategy: :one_for_one
      )

    # WI-020 self-review F-07: a crash dump would contain unlocked keys from memory.
    if System.get_env("ERL_CRASH_DUMP_SECONDS") != "0" do
      Mix.shell().info(
        "Warning: crash dumps are enabled. If the server crashes, its memory, including unlocked keys, " <>
          "may be written to erl_crash.dump. Start with ERL_CRASH_DUMP_SECONDS=0 to prevent this."
      )
    end

    Mix.shell().info(FindependenceApp.Web.release_notice())
    Mix.shell().info("Open http://127.0.0.1:#{port}/ on this device. Ctrl-C twice to stop.")
    Process.sleep(:infinity)
  end
end
