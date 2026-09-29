defmodule FindependenceApp.Vault do
  @moduledoc """
  The encrypted on-disk form of a household (MEC-013, MEC-014; REQ-118..122).

  What is stored:

  - **members**: salt, X25519 public key, and `secret`, an AES-256-GCM box holding the private
    key and a personal key, encrypted under a PBKDF2-derived key (REQ-118).
  - **items**: plaintext structure (owners, grantees), with `content` encrypted under a per-item
    key, and `keys`, that item key sealed to each current reader (REQ-119).
  - **ledger** entries: each encrypted under its own key, sealed to the owners (REQ-120).
  - **personal**: each member's links and deletion records, under their personal key (REQ-121).
  - **proposals**: plaintext structure (ASM-020).

  All Household logic stays in `findependence_core`. This module only encrypts and decrypts.
  """

  alias FindependenceShared.{Crypto, Envelope}

  @version 1

  @doc "Creates a vault for a new household from `[{member_id, passphrase}]`."
  def create(member_passphrases, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, Crypto.min_iterations())
    hid = :crypto.strong_rand_bytes(16)

    made =
      Enum.map(member_passphrases, fn {m, pass} ->
        salt = Crypto.random_salt()
        {m, salt, Crypto.derive_key(pass, salt, iterations, opts), Crypto.keypair()}
      end)

    # Every member's secret pins every member's public key (WI-020), so a key swapped in the
    # plaintext file is detected at login and never used for sealing.
    pins = Map.new(made, fn {m, _salt, _kek, {pub, _priv}} -> {m, pub} end)

    members =
      Map.new(made, fn {m, salt, kek, {pub, priv}} ->
        secret = %{priv: priv, personal: Crypto.random_key(), pins: pins}
        box = Crypto.encrypt(kek, encode(secret), aad(hid, {:member, m}))
        {m, %{salt: salt, pub: pub, secret: box}}
      end)

    %{
      v: @version,
      hid: hid,
      iterations: iterations,
      unsafe_test: Keyword.get(opts, :unsafe_test, false),
      members: members,
      member_order: Enum.map(member_passphrases, &elem(&1, 0)),
      items: %{},
      proposals: %{},
      next_proposal: 1,
      personal: %{}
    }
  end

  @doc "Writes atomically: write to a temporary file, then rename."
  def write!(vault, path) do
    # A unique name, so two writers never share a temporary file (F-16).
    tmp = path <> ".tmp-" <> Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
    # Owner-only permissions before any content is written (WI-020 self-review, F-06).
    File.write!(tmp, "")
    File.chmod!(tmp, 0o600)

    # DEF-043: flushed to disk before the rename, so a power cut can't leave an empty or partial vault
    # under the real name. (The BEAM can't open a directory to flush the rename itself; at worst a power
    # cut loses the latest save and keeps the one before.)
    {:ok, f} = :file.open(tmp, [:write, :raw, :binary])

    try do
      :ok = :file.write(f, :erlang.term_to_binary(vault))
      :ok = :file.sync(f)
    after
      :file.close(f)
    end

    File.rename!(tmp, path)
    :ok
  end

  # Every atom the vault format can contain (WI-016) is listed in FindependenceShared.Envelope, which
  # decodes the file, so they exist before a [:safe] decode (WI-074).
  @doc false
  defdelegate format_atoms, to: Envelope

  def read!(path) do
    vault = path |> File.read!() |> Envelope.decode()
    if vault[:v] != @version, do: raise(ArgumentError, "unsupported vault version")
    vault
  end

  @doc false
  defdelegate aad(hid, context), to: Envelope

  @doc false
  defdelegate encode(term), to: Envelope

  @doc false
  defdelegate decode(bin), to: Envelope

  @doc "The members still in the household, as a core Household would see them."
  defdelegate members(vault), to: Envelope

  @doc false
  defdelegate empty_household(vault), to: Envelope
end
