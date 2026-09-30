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

  alias FindependenceHosted.Schemas.{
    Account,
    Household,
    Item,
    ItemReader,
    LedgerEntry,
    Membership,
    PersonalRecord,
    Proposal,
    ProposalMember,
    Reading,
    SealedKey
  }

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
  end

  @doc "The view rebuilt on `state` with the keys it already holds."
  def refresh(%View{} = v, state), do: Envelope.refresh(v, state)

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

  @doc "The household's sealed state, in the local vault's shape."
  def load(household_id) do
    household = Repo.get!(Household, household_id)
    by_household = fn schema -> from(r in schema, where: r.household_id == ^household_id) end

    members =
      from(m in Membership,
        join: a in Account,
        on: a.id == m.account_id,
        where: m.household_id == ^household_id,
        order_by: [m.inserted_at, m.id],
        select: {m.id, a.public_key, a.signing_public_key}
      )
      |> Repo.all()

    readers = Repo.all(by_household.(ItemReader)) |> Enum.group_by(& &1.item_id)
    keys = Repo.all(by_household.(SealedKey)) |> Enum.group_by(&{&1.item_id, &1.kind, &1.seq})
    ledger = Repo.all(by_household.(LedgerEntry)) |> Enum.group_by(& &1.item_id)
    readings = Repo.all(by_household.(Reading)) |> Enum.group_by(& &1.item_id)
    targets = Repo.all(by_household.(ProposalMember)) |> Enum.group_by(& &1.number)

    keys_for = fn id, kind, seq ->
      Map.new(Map.get(keys, {id, kind, seq}, []), &{&1.membership_id, Envelope.decode(&1.sealed)})
    end

    boxes = fn rows, id, kind ->
      rows
      |> Map.get(id, [])
      |> Enum.sort_by(& &1.seq)
      |> Enum.map(
        &%{seq: &1.seq, box: Envelope.decode(&1.box), keys: keys_for.(id, kind, &1.seq)}
      )
    end

    items =
      Map.new(Repo.all(by_household.(Item)), fn item ->
        rs = Map.get(readers, item.id, [])

        role = fn r ->
          rs |> Enum.filter(&(&1.role == r)) |> Enum.map(& &1.membership_id) |> Enum.sort()
        end

        {item.id,
         %{
           owners: role.("owner"),
           grantees: role.("grantee"),
           content: Envelope.decode(item.content),
           keys: keys_for.(item.id, "item", 0),
           ledger: boxes.(ledger, item.id, "entry"),
           readings: boxes.(readings, item.id, "reading")
         }}
      end)

    proposals =
      Map.new(Repo.all(by_household.(Proposal)), fn p ->
        ms = Map.get(targets, p.number, [])
        of = fn r -> for m <- ms, m.role == r, into: MapSet.new(), do: m.membership_id end

        change =
          case p.kind do
            "owners" -> {:owners, of.("target")}
            "grant" -> {:grant, of.("target") |> Enum.to_list() |> hd()}
          end

        {p.number,
         %{
           item_id: p.item_id,
           change: change,
           proposed_by: p.proposed_by,
           consents: of.("consent")
         }}
      end)

    %{
      hid: hid(household_id),
      members: Map.new(members, fn {m, pub, spub} -> {m, %{pub: pub, sign_pub: spub}} end),
      member_order: Enum.map(members, &elem(&1, 0)),
      items: items,
      proposals: proposals,
      next_proposal: household.next_proposal,
      personal:
        Map.new(
          Repo.all(by_household.(PersonalRecord)),
          &{&1.membership_id, Envelope.decode(&1.box)}
        )
    }
  end

  @doc "Locks the household's row for the rest of the transaction (REV-099 G5)."
  def lock!(household_id) do
    from(h in Household, where: h.id == ^household_id, lock: "FOR UPDATE") |> Repo.one!()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Writing

  @doc """
  Stores what changed between `old` and `new` (both in the vault's shape): a changed item keeps its row and has
  its readers, keys, ledger entries, and readings replaced; proposals are replaced if any changed; personal records
  are replaced or removed; a member no longer in `new` (who has left) loses their membership row and their
  invitation codes; and a household whose last member has left is removed.
  """
  def write(household_id, old, new) do
    hh = household_id
    proposals_changed? = old.proposals != new.proposals

    if proposals_changed?, do: Repo.delete_all(from(p in Proposal, where: p.household_id == ^hh))

    for {id, _} <- old.items, not Map.has_key?(new.items, id), do: delete_item(hh, id)

    # A changed item keeps its row (proposals may refer to it) and has its parts replaced.
    for {id, rec} <- new.items, old.items[id] != rec do
      if Map.has_key?(old.items, id),
        do: replace_item(hh, id, rec),
        else: insert_item(hh, id, rec)
    end

    if proposals_changed?, do: insert_proposals(hh, new.proposals)

    if old.next_proposal != new.next_proposal do
      from(h in Household, where: h.id == ^hh)
      |> Repo.update_all(set: [next_proposal: new.next_proposal])
    end

    for {m, box} <- new.personal, old.personal[m] != box do
      Repo.insert!(%PersonalRecord{membership_id: m, household_id: hh, box: Envelope.encode(box)},
        on_conflict: [set: [box: Envelope.encode(box)]],
        conflict_target: :membership_id
      )
    end

    for {m, _} <- old.personal,
        not Map.has_key?(new.personal, m),
        do: Repo.delete_all(from(p in PersonalRecord, where: p.membership_id == ^m))

    departed = for {m, _} <- old.members, not Map.has_key?(new.members, m), do: m

    for m <- departed do
      Repo.delete_all(from(i in Schemas.Invitation, where: i.created_by == ^m))
      Repo.delete_all(from(ms in Membership, where: ms.id == ^m and ms.household_id == ^hh))
    end

    # The last member has left: nothing is owned (core refuses a leaver who owns anything), so the household
    # goes (REQ-189).
    if departed != [] and not Repo.exists?(from(ms in Membership, where: ms.household_id == ^hh)),
      do: Repo.delete_all(from(h in Household, where: h.id == ^hh))

    {:ok, departed}
  end

  defp delete_item(hh, id),
    do: Repo.delete_all(from(i in Item, where: i.household_id == ^hh and i.id == ^id))

  defp replace_item(hh, id, rec) do
    from(i in Item, where: i.household_id == ^hh and i.id == ^id)
    |> Repo.update_all(set: [content: Envelope.encode(rec.content)])

    for schema <- [ItemReader, SealedKey, LedgerEntry, Reading],
        do: Repo.delete_all(from(r in schema, where: r.household_id == ^hh and r.item_id == ^id))

    insert_parts(hh, id, rec)
  end

  defp insert_item(hh, id, rec) do
    Repo.insert!(%Item{household_id: hh, id: id, content: Envelope.encode(rec.content)})
    insert_parts(hh, id, rec)
  end

  defp insert_parts(hh, id, rec) do
    readers =
      for {role, ms} <- [{"owner", rec.owners}, {"grantee", rec.grantees}],
          m <- ms,
          do: %{household_id: hh, item_id: id, membership_id: m, role: role}

    Repo.insert_all(ItemReader, readers)

    boxes = fn list ->
      for b <- list, do: %{household_id: hh, item_id: id, seq: b.seq, box: Envelope.encode(b.box)}
    end

    Repo.insert_all(LedgerEntry, boxes.(rec.ledger))
    Repo.insert_all(Reading, boxes.(Map.get(rec, :readings, [])))

    item_keys = for {m, k} <- rec.keys, do: {"item", 0, m, k}
    entry_keys = for e <- rec.ledger, {m, k} <- e.keys, do: {"entry", e.seq, m, k}

    reading_keys =
      for r <- Map.get(rec, :readings, []), {m, k} <- r.keys, do: {"reading", r.seq, m, k}

    sealed = item_keys ++ entry_keys ++ reading_keys

    Repo.insert_all(
      SealedKey,
      for {kind, seq, m, k} <- sealed do
        %{
          household_id: hh,
          item_id: id,
          kind: kind,
          seq: seq,
          membership_id: m,
          sealed: Envelope.encode(k)
        }
      end
    )
  end

  defp insert_proposals(hh, proposals) do
    Repo.insert_all(
      Proposal,
      for {n, p} <- proposals do
        %{
          household_id: hh,
          number: n,
          item_id: p.item_id,
          kind: kind(p.change),
          proposed_by: p.proposed_by
        }
      end
    )

    members =
      for {n, p} <- proposals,
          {role, ms} <- [{"target", targets(p.change)}, {"consent", p.consents}],
          m <- ms,
          do: %{household_id: hh, number: n, membership_id: m, role: role}

    Repo.insert_all(ProposalMember, members)
  end

  defp kind({:owners, _}), do: "owners"
  defp kind({:grant, _}), do: "grant"
  defp targets({:owners, ms}), do: ms
  defp targets({:grant, m}), do: [m]

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
