defmodule FindependenceApp.Identity do
  @moduledoc """
  Platform context Identity (DP-001 section 2), local-first form: who can unlock, and unlocking with a
  passphrase (REQ-118). Sessions themselves are held by `Sessions` (REQ-123).
  """

  alias FindependenceApp.{Store, Vault}

  @doc "The members who can unlock this household."
  def members, do: Store.vault() |> Vault.members()

  @doc "Unlocks `member` with `passphrase`: `{:ok, session}` or `{:error, :unauthenticated, :bad_credentials}`."
  def unlock(member, passphrase) do
    case Store.open(member, passphrase) do
      {:ok, session} -> {:ok, session}
      {:error, :bad_credentials} -> {:error, :unauthenticated, :bad_credentials}
    end
  end
end
