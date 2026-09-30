defmodule FindependenceApp.Identity do
  @moduledoc """
  Platform context Identity (DP-001 section 2), local-first form: who can unlock, and unlocking with a
  passphrase (REQ-118). Sessions themselves are held by `Sessions` (REQ-123).
  """

  alias FindependenceApp.{Session, Store, Vault}
  alias FindependenceShared.Scope

  @doc "The members who can unlock this household."
  def members, do: Store.vault() |> Vault.members()

  @doc "Unlocks `member` with `passphrase`: `{:ok, session}` or `{:error, :unauthenticated, :bad_credentials}`."
  def unlock(member, passphrase) do
    case Store.open(member, passphrase) do
      {:ok, session} -> {:ok, session}
      {:error, :bad_credentials} -> {:error, :unauthenticated, :bad_credentials}
    end
  end

  @doc "What the member's session found altered or missing in the stored vault, for the integrity banner."
  def integrity_issues(%Scope{session: %Session{} = s}), do: Session.integrity_issues(s)
end
