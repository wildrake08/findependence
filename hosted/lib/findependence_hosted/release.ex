defmodule FindependenceHosted.Release do
  @moduledoc """
  Commands an operator runs beside a release, as `bin/findependence_hosted eval
  "FindependenceHosted.Release.migrate()"` (a release has no Mix). Each is operator access to production and writes
  one content-free audit record (REQ-191 AC-1, WI-077): operation operator_access, channel release_command, the
  command as the resource, and whether it succeeded.
  """
  @app :findependence_hosted

  alias FindependenceHosted.{Audit, Repo}

  @doc """
  Runs every pending migration, as the owner role when MIGRATION_DATABASE_URL is set; then, when
  DATABASE_RUNTIME_ROLE names the role the application connects as, grants it row access and no more
  (`FindependenceHosted.DbRoles.grant_runtime/2`; WI-081).
  """
  def migrate do
    load_app()
    as_owner()

    run("migrate", fn ->
      result = Ecto.Migrator.run(Repo, :up, all: true)

      case System.get_env("DATABASE_RUNTIME_ROLE") do
        role when is_binary(role) and role != "" ->
          FindependenceHosted.DbRoles.grant_runtime(role)

        _ ->
          :ok
      end

      result
    end)
  end

  @doc "Rolls back to a version (as the owner role, as `migrate/0`)."
  def rollback(version) do
    load_app()
    as_owner()
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

  # Migrations change the schema, which the runtime role can't: they connect as the owner (WI-081).
  defp as_owner do
    case System.get_env("MIGRATION_DATABASE_URL") do
      url when is_binary(url) and url != "" ->
        config = Application.get_env(@app, Repo, [])
        Application.put_env(@app, Repo, Keyword.put(config, :url, url))

      _ ->
        :ok
    end
  end
end
