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
    # plaintext file is detected at login and never used for sealing; and every member's signing key
    # (WI-079), derived from their private key. A new vault has nothing written before signing.
    pins = Map.new(made, fn {m, _salt, _kek, {pub, _priv}} -> {m, pub} end)

    sign_pins =
      Map.new(made, fn {m, _salt, _kek, {_pub, priv}} ->
        {m, elem(Crypto.signing_keypair(priv), 0)}
      end)

    members =
      Map.new(made, fn {m, salt, kek, {pub, priv}} ->
        secret = %{
          priv: priv,
          personal: Crypto.random_key(),
          pins: pins,
          sign_pins: sign_pins,
          legacy: MapSet.new()
        }

        box = Crypto.encrypt(kek, encode(secret), aad(hid, {:member, m}))
        {m, %{salt: salt, pub: pub, sign_pub: sign_pins[m], secret: box}}
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

  defmodule OutdatedError do
    @moduledoc "The vault file was made by a version of Findependence from before records were signed (WI-080)."
    defexception []

    @impl true
    def message(_),
      do:
        "this household file was made by an earlier version of Findependence (before v0.8.2-alpha), whose " <>
          "records can't be checked for changes made outside Findependence, so it isn't opened. Make a new " <>
          "household with mix findependence.setup; the old file is left as it was."
  end

  defmodule MalformedError do
    @moduledoc "The vault file's contents are not the shape this version writes (WI-079, FND-02)."
    defexception [:where]

    @impl true
    def message(%{where: where}),
      do: "the household file is malformed (#{where}); it was not written by Findependence"
  end

  @doc """
  Reads and checks a vault file. The bytes are decoded as plain data only (`Envelope.decode/1` refuses
  functions, pids, ports, and references), and the result must have exactly the shape this version writes
  (`validate!/1`), so a malformed file is refused here with a clear error rather than failing later.
  """
  def read!(path) do
    vault =
      try do
        path |> File.read!() |> Envelope.decode()
      rescue
        e in FindependenceShared.SafeTerm.UnsafeTermError -> reraise e, __STACKTRACE__
        ArgumentError -> raise MalformedError, where: "not a stored term"
      end

    if is_map(vault) and vault[:v] != @version and Map.has_key?(vault, :v),
      do: raise(ArgumentError, "unsupported vault version")

    vault = validate!(vault)

    # WI-080 (REV-107): a file made before records were signed (before v0.8.2-alpha) is not opened. Its records
    # carry no signatures, so tampering done before an upgrade could not be told apart; testers make a new
    # household instead (their data is made up).
    if Enum.any?(vault.members, fn {_, m} -> not Map.has_key?(m, :sign_pub) end),
      do: raise(OutdatedError)

    vault
  end

  # ---------------------------------------------------------------------------
  # Shape (WI-079, FND-02): what `create/2` and `FindependenceShared.Envelope.save/2` write, and nothing else.

  @doc "Returns `vault` if it has exactly the vault shape; raises `MalformedError` naming the first problem."
  def validate!(vault) do
    check(vault, "the file", fn v ->
      exact(
        v,
        [
          :v,
          :hid,
          :iterations,
          :unsafe_test,
          :members,
          :member_order,
          :items,
          :proposals,
          :next_proposal,
          :personal
        ],
        [:signers]
      ) and v.v == @version and bytes?(v.hid, 16) and
        pos_int?(v.iterations) and is_boolean(v.unsafe_test) and pos_int?(v.next_proposal)
    end)

    check(vault.members, "members", &map_of?(&1, fn m, rec -> id?(m) and member?(rec) end))

    # WI-079: signing keys of members who left
    check(
      Map.get(vault, :signers, %{}),
      "signers",
      &map_of?(&1, fn m, pub -> id?(m) and bytes?(pub, 32) end)
    )

    check(vault.member_order, "member_order", &list_of?(&1, fn m -> id?(m) end))
    check(vault.personal, "personal", &map_of?(&1, fn m, box -> id?(m) and box?(box) end))
    check(vault.proposals, "proposals", &map_of?(&1, fn n, p -> pos_int?(n) and proposal?(p) end))

    check(vault.items, "items", &map_of?(&1, fn _, _ -> true end))

    for {id, item} <- vault.items,
        do: check(item, "item #{inspect(id)}", fn i -> id?(id) and item?(i) end)

    vault
  end

  defp check(term, where, ok?) do
    if ok?.(term), do: :ok, else: raise(MalformedError, where: where)
  end

  defp member?(rec),
    do:
      exact(rec, [:salt, :pub, :secret], [:sign_pub]) and is_binary(rec.salt) and
        bytes?(rec.pub, 32) and box?(rec.secret) and
        (not Map.has_key?(rec, :sign_pub) or bytes?(rec.sign_pub, 32))

  defp item?(i) do
    exact(i, [:owners, :grantees, :content, :keys, :ledger], [:readings]) and
      list_of?(i.owners, &id?/1) and list_of?(i.grantees, &id?/1) and box?(i.content) and
      map_of?(i.keys, fn m, sealed -> id?(m) and sealed?(sealed) end) and
      list_of?(i.ledger, &sealed_box?/1) and list_of?(Map.get(i, :readings, []), &sealed_box?/1)
  end

  # a ledger entry or a reading: its own box and its key sealed to each reader
  defp sealed_box?(e),
    do:
      exact(e, [:seq, :box, :keys], []) and pos_int?(e.seq) and box?(e.box) and
        map_of?(e.keys, fn m, sealed -> id?(m) and sealed?(sealed) end)

  defp proposal?(p) do
    # WI-088 (REQ-201): when the cooling-off ends, and whether it has been opened to its joiners
    exact(p, [:item_id, :change, :consents, :proposed_by], [:due, :released]) and id?(p.item_id) and
      id?(p.proposed_by) and set_of_ids?(p.consents) and
      (not Map.has_key?(p, :due) or is_integer(p.due)) and
      (not Map.has_key?(p, :released) or p.released == true) and
      case p.change do
        {:owners, owners} -> set_of_ids?(owners)
        {:grant, m} -> id?(m)
        :delete -> true
        _ -> false
      end
  end

  # AES-256-GCM box, optionally signed (WI-079: author and Ed25519 signature)
  defp box?(b),
    do:
      exact(b, [:n, :c, :t], [:a, :s]) and bytes?(b.n, 12) and is_binary(b.c) and bytes?(b.t, 16) and
        (not Map.has_key?(b, :a) or id?(b.a)) and (not Map.has_key?(b, :s) or bytes?(b.s, 64)) and
        Map.has_key?(b, :a) == Map.has_key?(b, :s)

  # a seal: ephemeral public key and box, optionally with its commitment (WI-079)
  defp sealed?(b),
    do:
      exact(b, [:e, :n, :c, :t], [:k]) and bytes?(b.e, 32) and bytes?(b.n, 12) and is_binary(b.c) and
        bytes?(b.t, 16) and (not Map.has_key?(b, :k) or bytes?(b.k, 32))

  # a map with every `required` key and otherwise only `optional` ones (never a struct)
  defp exact(m, required, optional) do
    is_map(m) and not is_struct(m) and Enum.all?(required, &Map.has_key?(m, &1)) and
      Enum.all?(Map.keys(m), &(&1 in required or &1 in optional))
  end

  defp map_of?(m, ok?),
    do: is_map(m) and not is_struct(m) and Enum.all?(m, fn {k, v} -> ok?.(k, v) end)

  defp list_of?(l, ok?), do: is_list(l) and proper?(l) and Enum.all?(l, ok?)
  defp proper?([]), do: true
  defp proper?([_ | t]), do: proper?(t)
  defp proper?(_), do: false

  defp set_of_ids?(%MapSet{} = set),
    do:
      exact(Map.from_struct(set), [:map], []) and
        map_of?(set.map, fn k, v -> id?(k) and v == [] end)

  defp set_of_ids?(_), do: false

  defp id?(x), do: is_binary(x) and byte_size(x) > 0
  defp bytes?(x, n), do: is_binary(x) and byte_size(x) == n
  defp pos_int?(x), do: is_integer(x) and x > 0

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
