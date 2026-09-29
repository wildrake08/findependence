defmodule FindependenceApp.Session do
  @moduledoc """
  One member's unlocked view of a vault. Unlocking with a passphrase is the local form's; building the
  view and saving it are shared with the hosted form (`FindependenceShared.Envelope`, WI-074).

  `open/4` decrypts exactly what the member may read; everything else becomes a placeholder:
  empty attributes, and `:sealed` ledger entries. Callers change `session.household` with the
  unmodified core API, then `save/1` re-encrypts: it seals item keys and ledger entries to exactly
  the members who may now read them (REQ-119, REQ-120) and writes the member's own personal
  record (REQ-121).

  Invariant: a session only changes items its member can read. `save/1` raises if any other item
  changed, which would mean the core let a member act on an item they cannot see.
  """

  alias FindependenceApp.{Money, Vault}
  alias FindependenceShared.{Crypto, Envelope}

  defstruct [
    :vault,
    :member,
    :pub,
    :priv,
    :personal,
    :household,
    :baseline,
    # public keys pinned in this member's own secret at setup (nil for vaults made before WI-020)
    :pins,
    item_keys: %{},
    entry_keys: %{},
    reading_keys: %{},
    integrity: []
  ]

  @doc "Unlocks `member`. A wrong passphrase or unknown member is `{:error, :bad_credentials}`."
  def open(vault, member, passphrase) do
    with %{salt: salt, pub: pub, secret: box} <- vault.members[member],
         kek =
           Crypto.derive_key(passphrase, salt, vault.iterations, unsafe_test: vault.unsafe_test),
         {:ok, bin} <- Crypto.decrypt(kek, box, Vault.aad(vault.hid, {:member, member})) do
      %{priv: priv, personal: personal} = secret = Vault.decode(bin)
      pins = Map.get(secret, :pins)

      {:ok,
       build(%__MODULE__{
         vault: vault,
         member: member,
         # the pinned copy, not the unauthenticated one in the file (WI-020)
         pub: (pins && pins[member]) || pub,
         priv: priv,
         personal: personal,
         pins: pins
       })}
    else
      _ -> {:error, :bad_credentials}
    end
  end

  @doc """
  Rebuilds the session on a newer vault without the passphrase, using keys it has already
  unlocked. Used to serialize saves by different members on one device, so none is lost.
  """
  def refresh(%__MODULE__{} = s, vault), do: Envelope.refresh(s, vault, &Money.normalize/1)

  @doc "Encrypts the session's household back into a new vault, and returns the refreshed session."
  def save(%__MODULE__{} = s), do: Envelope.save(s, &Money.normalize/1)

  @doc "Signs that the file was changed outside the app (WI-020); see `FindependenceShared.Envelope`."
  def integrity_issues(%__MODULE__{} = s), do: Envelope.integrity_issues(s)

  defp build(s), do: Envelope.build(s, &Money.normalize/1)
end
