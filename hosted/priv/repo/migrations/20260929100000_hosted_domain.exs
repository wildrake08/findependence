defmodule FindependenceHosted.Repo.Migrations.HostedDomain do
  @moduledoc """
  WI-074 (REQ-186, REQ-187; DP-001 8.2): the household's sealed state as rows, the same pieces the local
  form's vault holds (REV-099 G2). Content, readings, ledger entries, and personal records are ciphertext;
  household, members, item identifiers, owners and grantees, sealed keys' recipients, and proposals are
  plain structure, each row tied to its household by a composite foreign key.
  """
  use Ecto.Migration

  def change do
    alter table(:households) do
      add :next_proposal, :integer, null: false, default: 1
    end

    # a member's personal key, sealed to their public key, and the public keys they have pinned, under
    # that key (MEC-013; REV-099 G4)
    alter table(:memberships) do
      add :key_box, :binary
      add :pins_box, :binary
    end

    create table(:items, primary_key: false) do
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :id, :string, null: false, primary_key: true
      add :content, :binary, null: false
    end

    # owners and grantees
    create table(:item_readers, primary_key: false) do
      add :household_id, :binary_id, null: false, primary_key: true
      add :item_id, :string, null: false, primary_key: true
      add :membership_id, :binary_id, null: false, primary_key: true
      add :role, :string, null: false, primary_key: true
    end

    create constraint(:item_readers, :item_readers_role, check: "role IN ('owner', 'grantee')")

    # ledger entries and readings, each under its own key
    for t <- [:ledger_entries, :readings] do
      create table(t, primary_key: false) do
        add :household_id, :binary_id, null: false, primary_key: true
        add :item_id, :string, null: false, primary_key: true
        add :seq, :integer, null: false, primary_key: true
        add :box, :binary, null: false
      end
    end

    # an item's, entry's, or reading's key sealed to one member
    create table(:sealed_keys, primary_key: false) do
      add :household_id, :binary_id, null: false, primary_key: true
      add :item_id, :string, null: false, primary_key: true
      add :kind, :string, null: false, primary_key: true
      add :seq, :integer, null: false, primary_key: true
      add :membership_id, :binary_id, null: false, primary_key: true
      add :sealed, :binary, null: false
    end

    create constraint(:sealed_keys, :sealed_keys_kind, check: "kind IN ('item', 'entry', 'reading')")

    create table(:proposals, primary_key: false) do
      add :household_id, :binary_id, null: false, primary_key: true
      add :number, :integer, null: false, primary_key: true
      add :item_id, :string, null: false
      add :kind, :string, null: false
      add :proposed_by, :binary_id, null: false
    end

    create constraint(:proposals, :proposals_kind, check: "kind IN ('owners', 'grant')")

    # the members a proposal names (new owners, or the grantee) and those who have consented
    create table(:proposal_members, primary_key: false) do
      add :household_id, :binary_id, null: false, primary_key: true
      add :number, :integer, null: false, primary_key: true
      add :membership_id, :binary_id, null: false, primary_key: true
      add :role, :string, null: false, primary_key: true
    end

    create constraint(:proposal_members, :proposal_members_role,
             check: "role IN ('target', 'consent')"
           )

    create table(:personal_records, primary_key: false) do
      add :membership_id, :binary_id, null: false, primary_key: true
      add :household_id, :binary_id, null: false
      add :box, :binary, null: false
    end

    # Tenancy (REQ-186 AC-2): every reference carries the household, so a row can't point into another one.
    for {table, constraints} <- [
          item_readers: [
            item_readers_item: "(household_id, item_id) REFERENCES items (household_id, id) ON DELETE CASCADE",
            item_readers_member: "(membership_id, household_id) REFERENCES memberships (id, household_id)"
          ],
          ledger_entries: [
            ledger_entries_item: "(household_id, item_id) REFERENCES items (household_id, id) ON DELETE CASCADE"
          ],
          readings: [
            readings_item: "(household_id, item_id) REFERENCES items (household_id, id) ON DELETE CASCADE"
          ],
          sealed_keys: [
            sealed_keys_item: "(household_id, item_id) REFERENCES items (household_id, id) ON DELETE CASCADE",
            sealed_keys_member: "(membership_id, household_id) REFERENCES memberships (id, household_id)"
          ],
          proposals: [
            proposals_item: "(household_id, item_id) REFERENCES items (household_id, id)",
            proposals_proposer: "(proposed_by, household_id) REFERENCES memberships (id, household_id)"
          ],
          proposal_members: [
            proposal_members_proposal:
              "(household_id, number) REFERENCES proposals (household_id, number) ON DELETE CASCADE",
            proposal_members_member: "(membership_id, household_id) REFERENCES memberships (id, household_id)"
          ],
          personal_records: [
            personal_records_member:
              "(membership_id, household_id) REFERENCES memberships (id, household_id) ON DELETE CASCADE"
          ]
        ],
        {name, fk} <- constraints do
      execute(
        "ALTER TABLE #{table} ADD CONSTRAINT #{name} FOREIGN KEY #{fk}",
        "ALTER TABLE #{table} DROP CONSTRAINT #{name}"
      )
    end
  end
end
