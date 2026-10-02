defmodule FindependenceHosted.WI081RolesTest do
  @moduledoc """
  WI-081 (ASSESS-001 FND-13): the deployment's two database roles, made by rel/database-roles.sql exactly as an
  operator would run it, then migrations as the owner and `DbRoles.grant_runtime/2`. The runtime role reads and
  writes rows, adds audit records, and can do nothing else; the startup check passes for it and fails for the
  owner and for a superuser. Makes a scratch database and two cluster roles on the test server, and removes them.
  """
  use ExUnit.Case, async: false

  alias FindependenceHosted.{DbRoles, Repo}

  @db "fdtest_roles"
  @owner_pw "owner test password"
  @app_pw "runtime test password"

  defp host, do: System.get_env("PGHOST", "localhost")

  defp admin(sql) do
    {out, status} =
      System.cmd("psql", ["-h", host(), "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-qc", sql],
        env: [{"PGPASSWORD", "postgres"}],
        stderr_to_stdout: true
      )

    {status, out}
  end

  defp clean do
    admin("DROP DATABASE IF EXISTS #{@db}")
    admin("DROP ROLE IF EXISTS findependence_app")
    admin("DROP ROLE IF EXISTS findependence_owner")
  end

  defp connect(user, pw) do
    {:ok, conn} =
      Postgrex.start_link(hostname: host(), username: user, password: pw, database: @db)

    conn
  end

  setup_all do
    clean()

    {out, 0} =
      System.cmd(
        "psql",
        ["-h", host(), "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-q"] ++
          ["-v", "owner_password=#{@owner_pw}", "-v", "runtime_password=#{@app_pw}"] ++
          ["-v", "database=#{@db}", "-f", "rel/database-roles.sql"],
        env: [{"PGPASSWORD", "postgres"}],
        stderr_to_stdout: true
      )

    _ = out

    # migrations as the owner, then the runtime role's grants, as Release.migrate does
    {:ok, repo} =
      Repo.start_link(
        name: nil,
        hostname: host(),
        username: "findependence_owner",
        password: @owner_pw,
        database: @db,
        pool: DBConnection.ConnectionPool,
        pool_size: 2
      )

    previous = Repo.put_dynamic_repo(repo)

    Ecto.Migrator.run(
      Repo,
      Application.app_dir(:findependence_hosted, "priv/repo/migrations"),
      :up,
      all: true,
      log: false
    )

    :ok = DbRoles.grant_runtime(Repo, "findependence_app")
    Repo.put_dynamic_repo(previous)
    GenServer.stop(repo)

    on_exit(&clean/0)
    :ok
  end

  test "the runtime role reads and writes rows, adds audit records, and the startup check passes" do
    app = connect("findependence_app", @app_pw)
    query = &Postgrex.query!(app, &1, [])

    assert DbRoles.problems(query) == []

    query.(
      "INSERT INTO audit_events (at, operation, channel, outcome) VALUES (now(), 'sign_in', 'web', 'ok')"
    )

    assert %{rows: [[1]]} = query.("SELECT count(*)::int FROM audit_events")
    assert %{rows: [[0]]} = query.("SELECT count(*)::int FROM households")
  end

  test "the runtime role can't change audit records, the schema, or the migrations' record" do
    app = connect("findependence_app", @app_pw)

    for sql <- [
          "UPDATE audit_events SET outcome = 'refused'",
          "DELETE FROM audit_events",
          "CREATE TABLE extra (id int)",
          "DROP TABLE households",
          "SELECT * FROM schema_migrations"
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: code}}} = Postgrex.query(app, sql, []),
             sql

      assert code in [:insufficient_privilege, :must_be_owner], sql
    end
  end

  test "the startup check refuses the owner and a superuser" do
    owner = connect("findependence_owner", @owner_pw)
    owner_problems = DbRoles.problems(&Postgrex.query!(owner, &1, []))
    assert "owns the application's tables" in owner_problems
    assert "can create objects in the schema" in owner_problems

    super = connect("postgres", "postgres")
    assert "is a superuser" in DbRoles.problems(&Postgrex.query!(super, &1, []))
  end

  test "a role name that isn't a plain identifier is refused before any SQL" do
    assert_raise ArgumentError, fn -> DbRoles.grant_runtime(Repo, "app; DROP TABLE items") end
  end

  test "with the check on (production), a server connected as a superuser doesn't start" do
    # the test database is reached as the superuser postgres
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Application.put_env(:findependence_hosted, :db_role_check, true)
    on_exit(fn -> Application.delete_env(:findependence_hosted, :db_role_check) end)

    assert_raise RuntimeError, ~r/is a superuser/, fn -> DbRoles.start_link() end

    Application.put_env(:findependence_hosted, :db_role_check, false)
    assert DbRoles.start_link() == :ignore
  end
end
