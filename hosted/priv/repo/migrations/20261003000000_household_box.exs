defmodule FindependenceHosted.Repo.Migrations.HouseholdBox do
  @moduledoc """
  WI-086 (CP-029; ASSESS-002 item 5, FND-209): a household's records (items, their owners, grantees, sealed keys,
  history, readings, requests and agreements, and members' personal records) are stored as one block encrypted
  under a key held outside the database, bound to the household and its change counter, so a database or backup
  copy no longer shows who owns or sees what; display names are encrypted too, with a keyed hash keeping them
  unique in a household. The per-item tables go. Existing households (development data only: the hosted form is
  not in service) are removed.
  """
  use Ecto.Migration

  def up do
    for t <- ~w(sealed_keys proposal_members proposals item_readers ledger_entries readings personal_records items),
        do: execute("DROP TABLE IF EXISTS #{t} CASCADE")

    execute("DELETE FROM invitations")
    execute("DELETE FROM memberships")
    execute("DELETE FROM households")

    alter table(:households) do
      add :state_box, :binary
      add :version, :bigint, null: false, default: 0
    end

    drop_if_exists index(:memberships, [:household_id, :display_name])

    alter table(:memberships) do
      remove :display_name
      add :name_box, :binary, null: false
      add :name_hmac, :binary, null: false
    end

    create unique_index(:memberships, [:household_id, :name_hmac])
  end

  def down, do: raise(Ecto.MigrationError, "WI-086's household box can't be undone (development data only)")
end
