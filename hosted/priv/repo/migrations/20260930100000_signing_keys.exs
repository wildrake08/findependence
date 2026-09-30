defmodule FindependenceHosted.Repo.Migrations.SigningKeys do
  @moduledoc """
  WI-079 (security review FND-04): each account's Ed25519 signing public key, derived from its X25519 private
  key and published beside its public key, so members can pin it and check what each other writes. Filled at
  sign-up, and at the next sign-in for an account made before this column.
  """
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :signing_public_key, :binary
    end
  end
end
