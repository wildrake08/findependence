defmodule FindependenceHosted.Repo.Migrations.AccountNumbers do
  @moduledoc """
  WI-081 (REV-108; ASSESS-001 FND-06): accounts are identified by an account number, not an email address. The
  keyed hash that found an account by its address now finds it by its number; the number is also kept encrypted
  for the member's own session to show. Existing accounts (development data only: the hosted form is not in
  service) are removed, since they can't be signed in to without a number.
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
    execute("DELETE FROM accounts")

    rename table(:accounts), :email_hmac, to: :number_hmac
    execute("ALTER INDEX accounts_email_hmac_index RENAME TO accounts_number_hmac_index")

    alter table(:accounts) do
      add :number_box, :binary, null: false
    end
  end

  def down do
    alter table(:accounts) do
      remove :number_box
    end

    execute("ALTER INDEX accounts_number_hmac_index RENAME TO accounts_email_hmac_index")
    rename table(:accounts), :number_hmac, to: :email_hmac
  end
end
