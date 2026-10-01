defmodule FindependenceHosted.Schemas do
  @moduledoc """
  The hosted form's tables. The foundation's (WI-073) are structure only: no column holds a passphrase, a
  recovery key, an unwrapped key, or an email address (REQ-182, REV-097 F2). The domain's (WI-074) hold a
  household's sealed state as the local vault does (REV-099 G2): content, ledger entries, readings, personal
  records, and sealed keys are ciphertext (binary columns, each an encoded box); everything else is structure
  (REQ-187, DP-001 8.2).
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
    field :display_name, :string
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

defmodule FindependenceHosted.Schemas.Item do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "items" do
    field :household_id, :binary_id, primary_key: true
    field :id, :string, primary_key: true
    field :content, :binary
  end
end

defmodule FindependenceHosted.Schemas.ItemReader do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "item_readers" do
    field :household_id, :binary_id, primary_key: true
    field :item_id, :string, primary_key: true
    field :membership_id, :binary_id, primary_key: true
    field :role, :string, primary_key: true
  end
end

defmodule FindependenceHosted.Schemas.LedgerEntry do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "ledger_entries" do
    field :household_id, :binary_id, primary_key: true
    field :item_id, :string, primary_key: true
    field :seq, :integer, primary_key: true
    field :box, :binary
  end
end

defmodule FindependenceHosted.Schemas.Reading do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "readings" do
    field :household_id, :binary_id, primary_key: true
    field :item_id, :string, primary_key: true
    field :seq, :integer, primary_key: true
    field :box, :binary
  end
end

defmodule FindependenceHosted.Schemas.SealedKey do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "sealed_keys" do
    field :household_id, :binary_id, primary_key: true
    field :item_id, :string, primary_key: true
    field :kind, :string, primary_key: true
    field :seq, :integer, primary_key: true
    field :membership_id, :binary_id, primary_key: true
    field :sealed, :binary
  end
end

defmodule FindependenceHosted.Schemas.Proposal do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "proposals" do
    field :household_id, :binary_id, primary_key: true
    field :number, :integer, primary_key: true
    field :item_id, :string
    field :kind, :string
    field :proposed_by, :binary_id
  end
end

defmodule FindependenceHosted.Schemas.ProposalMember do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "proposal_members" do
    field :household_id, :binary_id, primary_key: true
    field :number, :integer, primary_key: true
    field :membership_id, :binary_id, primary_key: true
    field :role, :string, primary_key: true
  end
end

defmodule FindependenceHosted.Schemas.PersonalRecord do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "personal_records" do
    field :membership_id, :binary_id, primary_key: true
    field :household_id, :binary_id
    field :box, :binary
  end
end
