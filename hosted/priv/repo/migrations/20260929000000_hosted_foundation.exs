defmodule FindependenceHosted.Repo.Migrations.HostedFoundation do
  @moduledoc """
  WI-073: accounts, households, memberships, invitations, and audit events (REQ-181..REQ-186, REQ-191).
  No column holds a passphrase, a recovery key, an unwrapped key, or an email address (REQ-182, F2).
  """
  use Ecto.Migration

  def change do
    # F2 (REV-097): the address only as a keyed hash; the private key only wrapped (REQ-182)
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email_hmac, :binary, null: false
      add :public_key, :binary, null: false
      add :pass_salt, :binary, null: false
      add :pass_iterations, :integer, null: false
      add :private_key_by_passphrase, :binary, null: false
      add :recovery_salt, :binary, null: false
      add :private_key_by_recovery_key, :binary, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:email_hmac])

    create table(:households, primary_key: false) do
      add :id, :binary_id, primary_key: true
      timestamps(type: :utc_datetime)
    end

    # F1 (REV-097): the membership's id is the member inside the domain rules; the display name is unique
    # within the household. One household per account (REQ-181 note, H1).
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :household_id, references(:households, type: :binary_id, on_delete: :restrict), null: false
      add :account_id, references(:accounts, type: :binary_id, on_delete: :restrict), null: false
      add :display_name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:account_id])
    create unique_index(:memberships, [:household_id, :display_name])
    # the target of every foreign key that must stay inside one household (REQ-186 AC-2)
    create unique_index(:memberships, [:id, :household_id])

    # H3 (REV-094): the code only as a hash; its creator must be a member of the same household
    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :household_id, references(:households, type: :binary_id, on_delete: :restrict), null: false
      add :created_by, :binary_id, null: false
      add :code_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :withdrawn_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:code_hash])

    execute(
      "ALTER TABLE invitations ADD CONSTRAINT invitations_creator_in_household FOREIGN KEY (created_by, household_id) REFERENCES memberships (id, household_id)",
      "ALTER TABLE invitations DROP CONSTRAINT invitations_creator_in_household"
    )

    # REQ-191: content-free; identifiers, the operation, the channel, and the outcome only
    create table(:audit_events) do
      add :at, :utc_datetime_usec, null: false
      add :account_id, :binary_id
      add :household_id, :binary_id
      add :operation, :string, null: false
      add :resource_id, :string
      add :channel, :string, null: false
      add :outcome, :string, null: false
    end

    create index(:audit_events, [:account_id])
  end
end
