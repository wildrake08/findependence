defmodule FindependenceHosted.Schemas do
  @moduledoc """
  The hosted foundation's tables (WI-073). Structure only: no column holds a passphrase, a recovery key, an
  unwrapped key, or an email address (REQ-182, REV-097 F2), and nothing here is a member's information.
  """
end

defmodule FindependenceHosted.Schemas.Account do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "accounts" do
    field :email_hmac, :binary
    field :public_key, :binary
    field :pass_salt, :binary
    field :pass_iterations, :integer
    field :private_key_by_passphrase, :binary
    field :recovery_salt, :binary
    field :private_key_by_recovery_key, :binary
    timestamps(type: :utc_datetime)
  end
end

defmodule FindependenceHosted.Schemas.Household do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "households" do
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
