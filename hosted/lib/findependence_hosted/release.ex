defmodule FindependenceHosted.Release do
  @moduledoc """
  Commands an operator runs beside a release, as `bin/findependence_hosted eval
  "FindependenceHosted.Release.migrate()"` (a release has no Mix). Each is operator access to production and writes
  one content-free audit record (REQ-191 AC-1, WI-077): operation operator_access, channel release_command, the
  command as the resource, and whether it succeeded.
  """
  @app :findependence_hosted

  alias FindependenceHosted.{Audit, Repo}

  @doc "Runs every pending migration."
  def migrate do
    load_app()
    run("migrate", fn -> Ecto.Migrator.run(Repo, :up, all: true) end)
  end

  @doc "Rolls back to a version."
  def rollback(version) do
    load_app()
    run("rollback", fn -> Ecto.Migrator.run(Repo, :down, to: version) end)
  end

  # Runs the command with the repo started, and records it with the repo still up.
  defp run(command, fun) do
    {:ok, result, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo ->
        outcome =
          try do
            {:ok, fun.()}
          rescue
            e -> {:error, e}
          end

        Audit.record("operator_access", if(match?({:ok, _}, outcome), do: :ok, else: :refused), %{
          resource_id: command,
          channel: "release_command"
        })

        outcome
      end)

    case result do
      {:ok, value} -> value
      {:error, e} -> raise e
    end
  end

  defp load_app, do: Application.load(@app)
end
