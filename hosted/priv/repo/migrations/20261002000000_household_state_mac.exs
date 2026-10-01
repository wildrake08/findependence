defmodule FindependenceHosted.Repo.Migrations.HouseholdStateMac do
  @moduledoc """
  WI-085 (REQ-198; ASSESS-002 FND-201): each household's records carry a code under a key held outside the
  database, written by the service at every change and checked at every read. A household without one can't
  be read. Existing households (development data only: the hosted form is not in service) are removed, since
  nothing could vouch for their records.
  """
  use Ecto.Migration

  def up do
    execute("DELETE FROM sealed_keys")
    execute("DELETE FROM proposal_members")
    execute("DELETE FROM proposals")
    execute("DELETE FROM item_readers")
    execute("DELETE FROM ledger_entries")
    execute("DELETE FROM readings")
    execute("DELETE FROM personal_records")
    execute("DELETE FROM items")
    execute("DELETE FROM invitations")
    execute("DELETE FROM memberships")
    execute("DELETE FROM households")

    alter table(:households) do
      add :state_mac, :binary
    end
  end

  def down do
    alter table(:households) do
      remove :state_mac
    end
  end
end
