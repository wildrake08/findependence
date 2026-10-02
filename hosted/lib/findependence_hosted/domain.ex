defmodule FindependenceHosted.Domain do
  @moduledoc """
  A household's sealed state in PostgreSQL (WI-074; REV-099 G2; DP-001 8.2). The rows hold the same pieces as
  the local form's vault, and `load/1` assembles them into that shape, so the shared envelope code
  (`FindependenceShared.Envelope`) builds a member's view and seals changes exactly as it does locally;
  `write/3` stores what a save changed. Content, ledger entries, readings, personal records, and sealed keys are
  stored encoded as the envelope code produces them (ciphertext); owners, grantees, recipients, and proposals
  are rows with foreign keys (REQ-186 AC-2, REQ-187).

  A member is their membership id (REV-097 F1). Each member has a personal key sealed to their public key and a
  record of pinned public keys under it (REV-099 G4). A member pins every other member's key the first time
  their own operation runs with that member present (`pin/2`), and a key that later differs is reported and never
  sealed to, as the local form's pins; the key a member first sees is trusted (as SSH trusts a host key).

  WI-079 (FND-04): each account's Ed25519 signing public key (`accounts.signing_public_key`) is loaded as the
  member's `sign_pub` and pinned the same way, beside the public keys in the pins record. The hosted form has no
  data from before signing, so its views have an empty legacy record: every box must be signed.
  """

  import Ecto.Query

  alias FindependenceHosted.Repo
  alias FindependenceHosted.Schemas

  alias FindependenceHosted.Schemas.{Account, Household, Membership}

  alias FindependenceHosted.{RequestRefs, StateLedger, StateSeal}
  alias FindependenceShared.{Crypto, Envelope}

  defmodule View do
    @moduledoc """
    One member's view of their household (the fields `FindependenceShared.Envelope` works on), held for one
    request or operation, never stored (REQ-183).
    """
    defstruct [
      :household_id,
      :vault,
      :member,
      :pub,
      :priv,
      :personal,
      :household,
      :baseline,
      :pins,
      # WI-079: pinned signing keys; nothing here predates signing, so the legacy record is always empty
      sign_pins: %{},
      legacy: MapSet.new(),
      before_signing: %{},
      item_keys: %{},
      entry_keys: %{},
      reading_keys: %{},
      integrity: []
    ]
  end

  # ---------------------------------------------------------------------------
  # Key material for a new membership

  @doc """
  A membership's key material: a new personal key sealed to the member's public key, and the pins under it,
  holding the public keys of the household's members as they are now, the member's own included (G4).
  """
  def membership_keys(household_id, membership_id, pub) do
    personal = Crypto.random_key()
    hid = hid(household_id)

    keys =
      from(m in Membership,
        join: a in Account,
        on: a.id == m.account_id,
        where: m.household_id == ^household_id,
        select: {m.id, a.public_key, a.signing_public_key}
      )
      |> Repo.all()

    pins = keys |> Map.new(fn {m, pub, _} -> {m, pub} end) |> Map.put(membership_id, pub)
    sign_pins = for {m, _, spub} <- keys, is_binary(spub), into: %{}, do: {m, spub}

    %{
      key_box: Envelope.encode(Crypto.seal(pub, personal, key_aad(hid, membership_id))),
      pins_box: pins_box(hid, membership_id, personal, pins, sign_pins)
    }
  end

  # ---------------------------------------------------------------------------
  # Views

  @doc """
  The member's view of their household now, from the session's unwrapped keys (for reading). Returns nil if the
  session has no household.
  """
  def view(%{membership: nil}), do: nil

  def view(%{membership: %{id: mid, household_id: hid}, private_key: priv, public_key: pub}) do
    state = load(hid)
    %{key_box: key_box, pins_box: pins_box} = Repo.get!(Membership, mid)
    {:ok, personal} = Crypto.open(pub, priv, Envelope.decode(key_box), key_aad(state.hid, mid))

    {:ok, bin} = Crypto.decrypt(personal, Envelope.decode(pins_box), pins_aad(state.hid, mid))
    {pins, sign_pins} = unpack_pins(Envelope.decode(bin))

    %View{
      household_id: hid,
      vault: state,
      member: mid,
      pub: pub,
      priv: priv,
      personal: personal,
      pins: pins,
      sign_pins: sign_pins
    }
    |> Envelope.build()
    |> RequestRefs.out()
  end

  @doc """
  The view rebuilt on `state` with the keys it already holds; its requests keyed as members see them
  (REQ-199, `FindependenceHosted.RequestRefs`).
  """
  def refresh(%View{} = v, state), do: v |> Envelope.refresh(state) |> RequestRefs.out()

  @doc """
  Pins the public key of every member not yet pinned (G4), storing the pins if they changed. Keys already
  pinned are left as they are; a changed one is what `Envelope.integrity_issues/1` reports.
  """
  def pin(%View{} = v, state) do
    new =
      for {m, %{pub: pub}} <- state.members, not Map.has_key?(v.pins, m), into: %{}, do: {m, pub}

    # WI-079: signing keys likewise, once published
    new_sign =
      for {m, %{sign_pub: spub}} <- state.members,
          is_binary(spub),
          not Map.has_key?(v.sign_pins, m),
          into: %{},
          do: {m, spub}

    if new == %{} and new_sign == %{} do
      v
    else
      pins = Map.merge(v.pins, new)
      sign_pins = Map.merge(v.sign_pins, new_sign)

      from(m in Membership, where: m.id == ^v.member)
      |> Repo.update_all(
        set: [pins_box: pins_box(state.hid, v.member, v.personal, pins, sign_pins)]
      )

      %{v | pins: pins, sign_pins: sign_pins}
    end
  end

  # ---------------------------------------------------------------------------
  # Loading

  @doc """
  The household's sealed state, in the local vault's shape, after its checks: the block opens under the server's
  key for this household and change counter (WI-086), the code over the records verifies (REQ-198), and the
  counter is not below the one recorded outside the database (REQ-198 AC-5). Records that fail any of them raise
  `FindependenceHosted.HouseholdTampered`. The rows are read holding a share lock on the household's row: every
  change holds its update lock (`lock!/1`), so none can commit between the reads.
  """
  def load(household_id) do
    {:ok, state} =
      Repo.transaction(fn ->
        from(h in Household, where: h.id == ^household_id, lock: "FOR SHARE") |> Repo.all()
        load_checked(household_id)
      end)

    state
  end

  defp load_checked(household_id) do
    household = Repo.get!(Household, household_id)

    with {:ok, held} <- open_box(household),
         {:ok, names} <- names(household_id),
         state = assemble(household_id, held),
         true <-
           StateSeal.valid?(household_id, household.version, state, names, household.state_mac) ||
             :code,
         :ok <- StateLedger.check(household_id, household.version) do
      state
    else
      reason ->
        require Logger

        Logger.error(
          "household records failed their check (REQ-198): household #{household_id} (#{inspect(reason)})"
        )

        raise FindependenceHosted.HouseholdTampered, household_id: household_id
    end
  end

  @doc """
  Stores a household's records (`held`: items, proposals, next_proposal, personal) as a new block under the next
  change counter, with the code over them (REQ-198); returns `{:ok, counter}`, for the caller to record in the
  ledger outside the database once its transaction commits (`FindependenceHosted.StateLedger.record/2`).
  """
  def store!(household_id, held) do
    household = Repo.get!(Household, household_id)

    # past both the database's counter and the ledger's, so a reseal after a deliberate restore from backup
    # (DEPLOY.md section 8) brings the household back
    version = max(household.version, StateLedger.latest(household_id) || 0) + 1
    {:ok, names} = names(household_id)
    mac = StateSeal.mac(household_id, version, assemble(household_id, held), names)

    from(h in Household, where: h.id == ^household_id)
    |> Repo.update_all(
      set: [state_box: seal_box(household_id, version, held), version: version, state_mac: mac]
    )

    {:ok, version}
  end

  @doc """
  Writes a fresh block and code over a household's records as they are now (a new household's empty records, a
  join, or an operator's reseal after review). Only for records already checked, or none.
  """
  def seal!(household_id) do
    household = Repo.get!(Household, household_id)

    held =
      case open_box(household) do
        {:ok, held} -> held
        :none -> empty()
        :error -> raise FindependenceHosted.HouseholdTampered, household_id: household_id
      end

    store!(household_id, held)
  end

  @doc """
  The household's records as the block holds them, opened without the other checks: `{:ok, held}`, `:none` for a
  household with no block yet, or `:error`. For an operator's review of refused records (DEPLOY.md section 8) and
  for tests that play the operator; everything else reads through `load/1`.
  """
  def open(household_id), do: open_box(Repo.get!(Household, household_id))

  @doc "The household's change counter as stored, or nil (for an operator's review; not a check)."
  def version(household_id),
    do: Repo.one(from(h in Household, where: h.id == ^household_id, select: h.version))

  @doc "A new household's records: nothing yet."
  def empty, do: %{items: %{}, proposals: %{}, next_proposal: 1, personal: %{}}

  # the members (from the memberships and accounts) and the block's records, in the vault's shape
  defp assemble(household_id, held) do
    members =
      from(m in Membership,
        join: a in Account,
        on: a.id == m.account_id,
        where: m.household_id == ^household_id,
        order_by: [m.inserted_at, m.id],
        select: {m.id, a.public_key, a.signing_public_key}
      )
      |> Repo.all()

    %{
      hid: hid(household_id),
      members: Map.new(members, fn {m, pub, spub} -> {m, %{pub: pub, sign_pub: spub}} end),
      member_order: Enum.map(members, &elem(&1, 0)),
      items: held.items,
      proposals: held.proposals,
      next_proposal: held.next_proposal,
      personal: held.personal
    }
  end

  # ---------------------------------------------------------------------------
  # The block and the names (WI-086, REQ-200)

  @box_info "findependence household box v1"
  @name_info "findependence member name v1"
  @name_index_info "findependence member name index v1"

  defp seal_box(household_id, version, held) do
    plain = Envelope.encode(Map.take(held, [:items, :proposals, :next_proposal, :personal]))
    pack(Crypto.encrypt(server_key(@box_info), plain, box_aad(household_id, version)))
  end

  defp open_box(%Household{state_box: nil, version: 0}), do: :none
  defp open_box(%Household{state_box: nil}), do: :error

  defp open_box(%Household{id: id, state_box: box, version: version}) do
    with %{} = sealed <- unpack(box),
         {:ok, plain} <- Crypto.decrypt(server_key(@box_info), sealed, box_aad(id, version)),
         %{items: _, proposals: _, next_proposal: _, personal: _} = held <- Envelope.decode(plain) do
      {:ok, held}
    else
      _ -> :error
    end
  end

  defp box_aad(household_id, version),
    do: @box_info <> hid(household_id) <> <<version::64>>

  @doc "The encrypted display name and its keyed hash, for a membership row (REQ-200)."
  def name_fields(household_id, membership_id, name) do
    %{
      name_box:
        pack(Crypto.encrypt(server_key(@name_info), name, name_aad(household_id, membership_id))),
      name_hmac: name_hmac(household_id, name)
    }
  end

  @doc "A membership's display name, decrypted, or :error for one changed outside the service."
  def name_of(%Membership{household_id: hid, id: mid, name_box: box}) do
    case unpack(box) do
      %{} = sealed ->
        case Crypto.decrypt(server_key(@name_info), sealed, name_aad(hid, mid)) do
          {:ok, name} -> name
          :error -> :error
        end

      _ ->
        :error
    end
  end

  @doc "Every member's display name in a household, by membership id: `{:ok, map}` or `:error`."
  def names(household_id) do
    names =
      from(m in Membership, where: m.household_id == ^household_id)
      |> Repo.all()
      |> Map.new(&{&1.id, name_of(&1)})

    if Enum.any?(names, fn {_, n} -> n == :error end), do: :error, else: {:ok, names}
  end

  defp name_hmac(household_id, name),
    do: :crypto.mac(:hmac, :sha256, server_key(@name_index_info), [hid(household_id), name])

  defp name_aad(household_id, membership_id),
    do: @name_info <> hid(household_id) <> Ecto.UUID.dump!(membership_id)

  defp server_key(info),
    do:
      Crypto.hkdf(
        Application.fetch_env!(:findependence_hosted, :household_state_key),
        "",
        info,
        32
      )

  # nonce (12 bytes) <> tag (16 bytes) <> ciphertext
  defp pack(%{n: n, t: t, c: c}), do: n <> t <> c
  defp unpack(<<n::binary-12, t::binary-16, c::binary>>), do: %{n: n, t: t, c: c}
  defp unpack(_), do: nil

  @doc "Locks the household's row for the rest of the transaction (REV-099 G5)."
  def lock!(household_id) do
    from(h in Household, where: h.id == ^household_id, lock: "FOR UPDATE") |> Repo.one!()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Writing

  @doc """
  Stores the household after a change: `new` (the vault's shape) as the next block (`store!/2`); a member no
  longer in it (who has left) loses their membership row and their invitation codes; and a household whose last
  member has left is removed. Returns `{:ok, departed, counter}` (counter nil when the household went).
  """
  def write(household_id, old, new) do
    hh = household_id
    departed = for {m, _} <- old.members, not Map.has_key?(new.members, m), do: m

    for m <- departed do
      Repo.delete_all(from(i in Schemas.Invitation, where: i.created_by == ^m))
      Repo.delete_all(from(ms in Membership, where: ms.id == ^m and ms.household_id == ^hh))
    end

    # The last member has left: nothing is owned (core refuses a leaver who owns anything), so the household
    # goes (REQ-189).
    if departed != [] and not Repo.exists?(from(ms in Membership, where: ms.household_id == ^hh)) do
      Repo.delete_all(from(h in Household, where: h.id == ^hh))
      {:ok, departed, nil}
    else
      {:ok, version} = store!(hh, new)
      {:ok, departed, version}
    end
  end

  # ---------------------------------------------------------------------------

  # The household's identifier as the envelope's associated data uses it (16 bytes, as the local vault's).
  defp hid(household_id), do: Ecto.UUID.dump!(household_id)

  defp key_aad(hid, m), do: Envelope.aad(hid, {:membership_key, m})
  defp pins_aad(hid, m), do: Envelope.aad(hid, {:pins, m})

  # WI-079: the pins record holds the public keys and the signing keys pinned
  defp pins_box(hid, m, personal, pins, sign_pins),
    do:
      Envelope.encode(
        Crypto.encrypt(
          personal,
          Envelope.encode(%{pins: pins, sign_pins: sign_pins}),
          pins_aad(hid, m)
        )
      )

  # a record written before WI-079 holds only the public keys
  defp unpack_pins(%{pins: pins, sign_pins: sign_pins}), do: {pins, sign_pins}
  defp unpack_pins(pins) when is_map(pins), do: {pins, %{}}
end
