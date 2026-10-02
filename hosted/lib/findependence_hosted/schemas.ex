defmodule FindependenceHosted.Schemas do
  @moduledoc """
  The hosted form's tables. The foundation's (WI-073) are structure only: no column holds a passphrase, a
  recovery key, an unwrapped key, or an email address (REQ-182, REV-097 F2). Since WI-086 a household's sealed
  state (REV-099 G2: content, history, readings, personal records, sealed keys, owners, grantees, requests, and
  agreements) is one block in `households.state_box`, encrypted under a key held outside the database
  (`FindependenceHosted.Domain`), and display names are encrypted (REQ-200).
  """
end

defmodule FindependenceHosted.Schemas.Account do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "accounts" do
    # WI-081: an account number's keyed hash finds the account; the number itself, encrypted for the member
    field :number_hmac, :binary
    field :number_box, :binary
    field :public_key, :binary

    # WI-079: the Ed25519 signing public key derived from the private key (nil until filled at sign-in)
    field :signing_public_key, :binary
    field :pass_salt, :binary
    field :pass_iterations, :integer
    field :private_key_by_passphrase, :binary
    field :recovery_salt, :binary
    field :private_key_by_recovery_key, :binary

    # WI-080 (REQ-184 AC-7): when a recovery key was last used, shown to the signed-in owner
    field :recovered_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

defmodule FindependenceHosted.Schemas.Household do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "households" do
    field :next_proposal, :integer, default: 1

    # WI-085 (REQ-198): the code over the household's records, under a key held outside the database
    field :state_mac, :binary

    # WI-086: the household's records as one block encrypted under a key held outside the database, and the
    # change counter it is bound to (also kept outside the database, FindependenceHosted.StateLedger)
    field :state_box, :binary
    field :version, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end

defmodule FindependenceHosted.Schemas.Membership do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "memberships" do
    field :household_id, :binary_id
    field :account_id, :binary_id

    # WI-086: the display name encrypted under a key held outside the database, and a keyed hash of it that
    # keeps names unique in a household
    field :name_box, :binary
    field :name_hmac, :binary
    # the member's personal key sealed to their public key, and their pins under that key (WI-074)
    field :key_box, :binary
    field :pins_box, :binary
    timestamps(type: :utc_datetime)
  end
end

defmodule FindependenceHosted.Schemas.Invitation do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "invitations" do
    field :household_id, :binary_id
    field :created_by, :binary_id
    field :code_hash, :binary
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :withdrawn_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

defmodule FindependenceHosted.Schemas.AuditEvent do
  @moduledoc false
  use Ecto.Schema

  schema "audit_events" do
    field :at, :utc_datetime_usec
    field :account_id, :binary_id
    field :household_id, :binary_id
    field :operation, :string
    field :resource_id, :string
    field :channel, :string
    field :outcome, :string
  end
end
