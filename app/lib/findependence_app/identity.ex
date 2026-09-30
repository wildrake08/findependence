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
      {:ok, session} -> {:ok, record_legacy(session)}
      {:error, :bad_credentials} -> {:error, :unauthenticated, :bad_credentials}
    end
  end

  # WI-079: a member's first unlock after the upgrade records, in their own secret, which boxes and seals were
  # written before signing; it is saved at once (a save that changes nothing else), so what is added later
  # without a signature is reported even if the member changes nothing now. If another process wrote the file
  # meanwhile, the record stays in the session and is saved with the member's next change.
  defp record_legacy(session) do
    if Session.upgrade_pending?(session) do
      case Store.apply(session, &{:ok, &1}) do
        {:ok, saved} -> saved
        _ -> session
      end
    else
      session
    end
  end

  @doc "What the member's session found altered or missing in the stored vault, for the integrity banner."
  def integrity_issues(%Scope{session: %Session{} = s}), do: Session.integrity_issues(s)

  @doc "Which parts of item `id` were saved before signing began, for the item page's note (WI-079)."
  def written_before_signing(%Scope{session: %Session{} = s}, id),
    do: Session.written_before_signing(s, id)
end
