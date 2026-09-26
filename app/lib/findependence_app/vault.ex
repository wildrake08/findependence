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

  # Every atom the vault format can contain (WI-016). Decoding uses [:safe], which refuses atoms
  # that don't exist yet, and in a freshly started VM atoms defined only in not-yet-loaded modules
  # (core proposals, ledger events, attribute keys) don't exist. Listing them here creates them when
  # this module loads. [:safe] stays on deliberately, so file contents can never create atoms.
  @format_atoms [
    # vault, members, boxes, secrets
    :v,
    :hid,
    :iterations,
    :unsafe_test,
    :members,
    :member_order,
    :items,
    :proposals,
    :next_proposal,
    :personal,
    :salt,
    :pub,
    :secret,
    :n,
    :c,
    :t,
    :e,
    :priv,
    # item records and ledger entry records
    :owners,
    :grantees,
    :content,
    :keys,
    :ledger,
    :seq,
    :box,
    # proposals (Findependence.Household), including their MapSets
    :item_id,
    :change,
    :consents,
    :proposed_by,
    :grant,
    MapSet,
    :__struct__,
    :map,
    # personal records and deletion records
    :links,
    :deletions,
    # item attributes (web interface and Findependence.Alignment)
    :note,
    :amount,
    :kind,
    :value,
    :label,
    # ledger entries (Findependence.Ledger)
    :event,
    :by,
    :details,
    :owner,
    :grantee,
    :created,
    :owners_changed,
    :owner_relinquished,
    :granted,
    :grant_revoked,
    :grantee_departed
  ]

  @doc false
  def format_atoms, do: @format_atoms

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
