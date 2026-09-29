defmodule FindependenceHosted.NoPersistenceTest do
  @moduledoc """
  WI-063 as read by REV-080: the ecto library may be present (petal_components requires it
  through phoenix_ecto), but no Repo, ecto_sql, database adapter, or schema until DEF-056's
  storage design is decided.
  """
  use ExUnit.Case, async: true

  @adapters ~w(ecto_sql postgrex myxql ecto_sqlite3 tds)a

  test "no database adapter or ecto_sql is locked" do
    lock = File.read!(Path.expand("../../mix.lock", __DIR__))
    locked = for [_, name] <- Regex.scan(~r/^  "([a-z0-9_]+)":/m, lock), do: String.to_atom(name)
    assert "phoenix" in Enum.map(locked, &to_string/1)
    assert Enum.filter(@adapters, &(&1 in locked)) == []
  end

  test "the app defines no Repo and no schema" do
    {:ok, modules} = :application.get_key(:findependence_hosted, :modules)

    offending =
      Enum.filter(modules, fn m ->
        Code.ensure_loaded!(m)

        behaviours =
          m.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

        function_exported?(m, :__schema__, 1) or Ecto.Repo in behaviours
      end)

    assert offending == []
  end
end
