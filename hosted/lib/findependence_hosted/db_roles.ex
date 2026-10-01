defmodule FindependenceHosted.DbRoles do
  @moduledoc """
  WI-081 (ASSESS-001 FND-13): the application connects to PostgreSQL as a runtime role that can only read and
  write rows, and add audit records; migrations run as a separate owner role. A compromised application then
  can't change the schema or rewrite what the audit recorded.

  - `grant_runtime/2` is run by `FindependenceHosted.Release.migrate/0` as the owner, after migrating, when
    DATABASE_RUNTIME_ROLE names the runtime role: row access on every table, add-only on audit_events, none on
    schema_migrations.
  - `problems/1` lists what is wrong with the role a connection uses; a production server refuses to start
    if there is anything (`check!/0`, from `FindependenceHosted.Application`).

  Creating the two login roles is a one-time step for the database's administrator: rel/database-roles.sql.
  """

  alias FindependenceHosted.Repo

  @doc "Grants `role` what the application needs, and no more, on the current schema (run as the owner)."
  def grant_runtime(repo \\ Repo, role) when is_binary(role) do
    unless Regex.match?(~r/\A[a-z_][a-z0-9_]{0,62}\z/, role),
      do: raise(ArgumentError, "DATABASE_RUNTIME_ROLE must be a plain lower-case role name")

    for sql <- [
          "GRANT USAGE ON SCHEMA public TO #{role}",
          "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{role}",
          "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{role}",
          "REVOKE UPDATE, DELETE, TRUNCATE ON audit_events FROM #{role}",
          "REVOKE ALL ON schema_migrations FROM #{role}",
          "REVOKE CREATE ON SCHEMA public FROM #{role}"
        ],
        do: repo.query!(sql)

    :ok
  end

  @doc """
  What is wrong with the role `query` connects as, for running the application: an empty list when it can only
  read and write rows. `query` is a function taking SQL and returning `%{rows: rows}`.
  """
  def problems(query) do
    [[super?, createrole?, createdb?, bypassrls?]] =
      query.(
        "SELECT rolsuper, rolcreaterole, rolcreatedb, rolbypassrls FROM pg_roles WHERE rolname = current_user"
      ).rows

    [[owns?, schema_create?, audit_change?]] =
      query.("""
      SELECT
        EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tableowner = current_user),
        has_schema_privilege(current_user, 'public', 'CREATE'),
        has_table_privilege(current_user, 'audit_events', 'UPDATE')
          OR has_table_privilege(current_user, 'audit_events', 'DELETE')
          OR has_table_privilege(current_user, 'audit_events', 'TRUNCATE')
      """).rows

    for {true, problem} <- [
          {super?, "is a superuser"},
          {createrole?, "can create roles"},
          {createdb?, "can create databases"},
          {bypassrls?, "bypasses row security"},
          {owns?, "owns the application's tables"},
          {schema_create?, "can create objects in the schema"},
          {audit_change?, "can change or remove audit records"}
        ],
        do: problem
  end

  @doc """
  Raises unless the application's own connection uses a runtime role (production only: `:db_role_check`). Used
  as a child of the application's supervisor, so a server with too powerful a role doesn't start.
  """
  def check!(repo \\ Repo) do
    case problems(&repo.query!/1) do
      [] ->
        :ok

      found ->
        raise "the database role the application connects as #{Enum.join(found, ", ")}; connect with the " <>
                "runtime role made by rel/database-roles.sql (migrations use MIGRATION_DATABASE_URL)"
    end
  end

  @doc false
  def child_spec(_),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}

  @doc false
  def start_link do
    if Application.get_env(:findependence_hosted, :db_role_check, false) do
      check!()
    end

    :ignore
  end
end
