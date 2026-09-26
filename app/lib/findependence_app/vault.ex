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

  alias FindependenceApp.Crypto
  alias Findependence.Household

  @version 1

  @doc "Creates a vault for a new household from `[{member_id, passphrase}]`."
  def create(member_passphrases, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, Crypto.min_iterations())
    hid = :crypto.strong_rand_bytes(16)

    members =
      Map.new(member_passphrases, fn {m, pass} ->
        salt = Crypto.random_salt()
        kek = Crypto.derive_key(pass, salt, iterations, opts)
        {pub, priv} = Crypto.keypair()
        secret = %{priv: priv, personal: Crypto.random_key()}

        {m,
         %{
           salt: salt,
           pub: pub,
           secret: Crypto.encrypt(kek, encode(secret), aad(hid, {:member, m}))
         }}
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
    tmp = path <> ".tmp"
    File.write!(tmp, :erlang.term_to_binary(vault))
    File.rename!(tmp, path)
    :ok
  end

  def read!(path) do
    vault = path |> File.read!() |> :erlang.binary_to_term([:safe])
    if vault[:v] != @version, do: raise(ArgumentError, "unsupported vault version")
    vault
  end

  @doc false
  def aad(hid, context), do: :erlang.term_to_binary({hid, context})

  @doc false
  def encode(term), do: :erlang.term_to_binary(term)

  @doc false
  def decode(bin), do: :erlang.binary_to_term(bin, [:safe])

  @doc "The members still in the household, as a core Household would see them."
  def members(vault), do: Enum.filter(vault.member_order, &Map.has_key?(vault.members, &1))

  @doc false
  def empty_household(vault), do: Household.new(members(vault))
end
