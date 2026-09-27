defmodule FindependenceApp.Session do
  @moduledoc """
  One member's unlocked view of a vault.

  `open/4` decrypts exactly what the member may read; everything else becomes a placeholder:
  empty attributes, and `:sealed` ledger entries. Callers change `session.household` with the
  unmodified core API, then `save/1` re-encrypts: it seals item keys and ledger entries to exactly
  the members who may now read them (REQ-119, REQ-120) and writes the member's own personal
  record (REQ-121).

  Invariant: a session only changes items its member can read. `save/1` raises if any other item
  changed, which would mean the core let a member act on an item they cannot see.
  """

  alias FindependenceApp.{Crypto, Vault}
  alias Findependence.Household

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
  def refresh(%__MODULE__{} = s, vault), do: build(%{s | vault: vault})

  @doc "Encrypts the session's household back into a new vault, and returns the refreshed session."
  def save(%__MODULE__{} = s) do
    h = s.household
    v = s.vault
    departed = MapSet.difference(MapSet.new(Map.keys(v.members)), h.members)

    s =
      Enum.reduce(Map.keys(h.items), s, fn id, s ->
        if Map.has_key?(v.items, id),
          do: s,
          else: %{s | item_keys: Map.put(s.item_keys, id, Crypto.random_key())}
      end)

    items =
      Map.new(h.items, fn {id, item} ->
        old = v.items[id]

        if s.item_keys[id] do
          {id, encrypt_item(s, id, item, old)}
        else
          unchanged!(s, id, item, old)
          {id, old}
        end
      end)

    personal =
      v.personal
      |> Map.drop(MapSet.to_list(departed))
      |> then(fn p ->
        if s.member in h.members,
          do: Map.put(p, s.member, encrypt_personal(s)),
          else: Map.delete(p, s.member)
      end)

    vault = %{
      v
      | members: Map.drop(v.members, MapSet.to_list(departed)),
        items: items,
        proposals: h.proposals,
        next_proposal: h.next_proposal,
        personal: personal
    }

    %{s | vault: vault} |> build()
  end

  # ---------------------------------------------------------------------------
  # Decryption

  defp build(s) do
    v = s.vault
    base = Vault.empty_household(v)

    {items, ledger, item_keys, entry_keys, readings, reading_keys} =
      Enum.reduce(v.items, {%{}, %{}, %{}, %{}, %{}, %{}}, fn {id, rec},
                                                              {items, ledger, iks, eks, rds, rks} ->
        key = open_sealed(s, rec.keys[s.member], {:item_key, id, s.member})

        attrs =
          case key && Crypto.decrypt(key, rec.content, Vault.aad(v.hid, {:content, id})) do
            # WI-021: amounts stored before cents are converted in memory (stored content is immutable)
            {:ok, bin} -> bin |> Vault.decode() |> FindependenceApp.Money.normalize()
            _ -> %{}
          end

        {entries, eks} =
          Enum.map_reduce(rec.ledger, eks, fn e, eks ->
            ek = open_sealed(s, e.keys[s.member], {:entry_key, id, e.seq, s.member})

            case ek && Crypto.decrypt(ek, e.box, Vault.aad(v.hid, {:entry, id, e.seq})) do
              {:ok, bin} -> {Vault.decode(bin), Map.put(eks, {id, e.seq}, ek)}
              _ -> {:sealed, eks}
            end
          end)

        item = %{
          id: id,
          attrs: attrs,
          owners: MapSet.new(rec.owners),
          grantees: MapSet.new(rec.grantees)
        }

        # CAP-010 readings (REQ-132/133): each has its own key; placeholders for any not sealed to us
        {item_readings, rks} =
          Enum.map_reduce(Map.get(rec, :readings, []), rks, fn r, rks ->
            rk = open_sealed(s, r.keys[s.member], {:reading_key, id, r.seq, s.member})

            case rk && Crypto.decrypt(rk, r.box, Vault.aad(v.hid, {:reading, id, r.seq})) do
              {:ok, bin} -> {Vault.decode(bin), Map.put(rks, {id, r.seq}, rk)}
              _ -> {:sealed, rks}
            end
          end)

        rds = if item_readings == [], do: rds, else: Map.put(rds, id, item_readings)
        iks = if key, do: Map.put(iks, id, key), else: iks
        {Map.put(items, id, item), Map.put(ledger, id, entries), iks, eks, rds, rks}
      end)

    {links, deletions} = personal_record(s)
    existing = MapSet.new(Map.keys(items))
    # Links to items deleted by someone else are dropped here (ASM-018: ids are never reused).
    links = MapSet.filter(links, fn {i, val} -> i in existing and val in existing end)

    household = %Household{
      base
      | items: items,
        ledger: ledger,
        readings: readings,
        proposals: v.proposals,
        next_proposal: v.next_proposal,
        links: %{s.member => links},
        deletions: %{s.member => deletions}
    }

    %{
      s
      | household: household,
        baseline: household,
        item_keys: item_keys,
        entry_keys: entry_keys,
        reading_keys: reading_keys,
        integrity: integrity_check(s)
    }
  end

  @doc """
  Signs that the file was changed outside the app (WI-020). The plaintext structure is not
  authenticated, so these are detection heuristics, not proof of integrity:

  - `{:reader_without_key, item, member}`: a listed owner or grantee has no sealed key. Legitimate
    additions always come with a key, so this means the reader list was edited.
  - `{:owner_without_ledger_key, item, member}`: an owner cannot open some history entry.
  - `{:unknown_member_referenced, item, member}`: an item names someone who isn't a member.
  - `{:public_key_changed, member}`: a member's public key differs from the one pinned at setup.
  """
  def integrity_issues(%__MODULE__{integrity: issues}), do: issues

  defp integrity_check(s) do
    v = s.vault

    pin_issues =
      for {m, pinned} <- s.pins || %{},
          %{pub: pub} <- [v.members[m]],
          pub != pinned,
          do: {:public_key_changed, m}

    item_issues =
      for {id, rec} <- Enum.sort(v.items),
          issue <- item_integrity(v, id, rec),
          do: issue

    pin_issues ++ item_issues
  end

  defp item_integrity(v, id, rec) do
    readers = Enum.uniq(rec.owners ++ rec.grantees)

    unknown =
      for r <- readers, not Map.has_key?(v.members, r), do: {:unknown_member_referenced, id, r}

    keyless =
      for r <- readers,
          Map.has_key?(v.members, r),
          not Map.has_key?(rec.keys, r),
          do: {:reader_without_key, id, r}

    ledgerless =
      for o <- rec.owners,
          Map.has_key?(v.members, o),
          Enum.any?(rec.ledger, &(not Map.has_key?(&1.keys, o))),
          do: {:owner_without_ledger_key, id, o}

    # REQ-133: every reader holds the latest reading's key; every owner holds all of them
    reading_list = Map.get(rec, :readings, [])

    readingless =
      case List.last(reading_list) do
        nil ->
          []

        last ->
          for r <- readers,
              Map.has_key?(v.members, r),
              not Map.has_key?(last.keys, r) or
                (r in rec.owners and Enum.any?(reading_list, &(not Map.has_key?(&1.keys, r)))),
              do: {:reader_without_reading_key, id, r}
      end

    unknown ++ keyless ++ ledgerless ++ readingless
  end

  defp open_sealed(_s, nil, _ctx), do: nil

  defp open_sealed(s, sealed, ctx) do
    case Crypto.open(s.pub, s.priv, sealed, Vault.aad(s.vault.hid, ctx)) do
      {:ok, key} -> key
      :error -> nil
    end
  end

  defp personal_record(s) do
    case s.vault.personal[s.member] do
      nil ->
        {MapSet.new(), []}

      box ->
        {:ok, bin} =
          Crypto.decrypt(s.personal, box, Vault.aad(s.vault.hid, {:personal, s.member}))

        %{links: links, deletions: deletions} = Vault.decode(bin)
        {links, deletions}
    end
  end

  # ---------------------------------------------------------------------------
  # Encryption

  defp encrypt_item(s, id, item, old) do
    v = s.vault
    key = s.item_keys[id]
    presealed = presealed(s.household.proposals, s.household.members, id, item)
    readers = MapSet.union(MapSet.union(item.owners, item.grantees), presealed)
    ledger_readers = MapSet.union(item.owners, presealed)

    # WI-020: a key is sealed only to readers THIS session added. A reader who was already listed
    # in the loaded file but had no key can only have been written in by editing the file, so they
    # are never granted a key here (see integrity_issues/1).
    {was_reader, was_ledger_reader} = baseline_readers(s, id)
    grantable? = fn r, before -> Map.has_key?((old && old.keys) || %{}, r) or r not in before end

    content =
      if old,
        do: old.content,
        else: Crypto.encrypt(key, Vault.encode(item.attrs), Vault.aad(v.hid, {:content, id}))

    keys =
      for r <- readers, (old && old.keys[r]) || grantable?.(r, was_reader), into: %{} do
        {r, (old && old.keys[r]) || seal(s, r, key, {:item_key, id, r})}
      end

    old_entries = if old, do: old.ledger, else: []
    entries = s.household.ledger[id] || []

    kept =
      for e <- old_entries do
        %{
          e
          | keys:
              for r <- ledger_readers, e.keys[r] || r not in was_ledger_reader, into: %{} do
                {r, e.keys[r] || seal(s, r, entry_key!(s, id, e.seq), {:entry_key, id, e.seq, r})}
              end
        }
      end

    added =
      for entry <- Enum.drop(entries, length(old_entries)) do
        ek = Crypto.random_key()

        %{
          seq: entry.seq,
          box: Crypto.encrypt(ek, Vault.encode(entry), Vault.aad(v.hid, {:entry, id, entry.seq})),
          keys:
            for r <- ledger_readers,
                trusted_ledger_reader?(r, was_ledger_reader, old_entries),
                into: %{} do
              {r, seal(s, r, ek, {:entry_key, id, entry.seq, r})}
            end
        }
      end

    %{
      owners: Enum.sort(item.owners),
      grantees: Enum.sort(item.grantees),
      content: content,
      keys: keys,
      ledger: kept ++ added,
      readings: encrypt_readings(s, id, item, old, was_reader)
    }
  end

  # CAP-010 (REQ-132, REQ-133, CP-013 A): each reading has its own key. The latest is sealed to
  # everyone who can read the item; earlier ones to its owners only. Keys of anyone no longer
  # entitled are dropped. A new key goes only to a reader this session added or one who holds the
  # item key in the file as loaded, never to a reader written into the file by editing it (WI-020).
  defp encrypt_readings(s, id, item, old, was_reader) do
    v = s.vault
    old_readings = (old && Map.get(old, :readings)) || []
    readings = s.household.readings[id] || []
    latest = length(readings)
    item_readers = MapSet.union(item.owners, item.grantees)
    trusted? = fn r -> r not in was_reader or Map.has_key?((old && old.keys) || %{}, r) end
    entitled = fn seq -> if seq == latest, do: item_readers, else: item.owners end

    kept =
      for r <- old_readings do
        %{
          r
          | keys:
              for m <- entitled.(r.seq), r.keys[m] || trusted?.(m), into: %{} do
                {m,
                 r.keys[m] || seal(s, m, reading_key!(s, id, r.seq), {:reading_key, id, r.seq, m})}
              end
        }
      end

    added =
      for reading <- Enum.drop(readings, length(old_readings)) do
        rk = Crypto.random_key()

        %{
          seq: reading.seq,
          box:
            Crypto.encrypt(
              rk,
              Vault.encode(reading),
              Vault.aad(v.hid, {:reading, id, reading.seq})
            ),
          keys:
            for m <- entitled.(reading.seq), trusted?.(m), into: %{} do
              {m, seal(s, m, rk, {:reading_key, id, reading.seq, m})}
            end
        }
      end

    kept ++ added
  end

  defp reading_key!(s, id, seq) do
    s.reading_keys[{id, seq}] ||
      raise ArgumentError,
            "#{inspect(s.member)} must re-seal reading #{seq} of #{inspect(id)} but cannot read it"
  end

  # Once every current owner has consented to adding members to a value, those prospective
  # members may read it (REQ-115), so it is sealed to them as well (REQ-119, REQ-120).
  defp presealed(proposals, members, id, item) do
    if Map.get(item.attrs, :kind) == :value do
      for {_, %{item_id: ^id, change: {:owners, new}, consents: c}} <- proposals,
          MapSet.subset?(item.owners, c),
          m <- MapSet.difference(new, item.owners),
          m in members,
          into: MapSet.new(),
          do: m
    else
      MapSet.new()
    end
  end

  # Readers of item `id` in the file as loaded, before this session's changes.
  defp baseline_readers(s, id) do
    case s.baseline.items[id] do
      nil ->
        {MapSet.new(), MapSet.new()}

      item ->
        pre = presealed(s.baseline.proposals, s.baseline.members, id, item)

        {MapSet.union(MapSet.union(item.owners, item.grantees), pre),
         MapSet.union(item.owners, pre)}
    end
  end

  # A ledger reader who was already listed but holds no key to any existing entry was written in by
  # editing the file (WI-020).
  defp trusted_ledger_reader?(r, was, old_entries),
    do: r not in was or old_entries == [] or Enum.any?(old_entries, &Map.has_key?(&1.keys, r))

  defp seal(s, recipient, key, ctx) do
    case s.vault.members[recipient] do
      # the pinned key when there is one, never a key swapped into the plaintext file (WI-020)
      %{pub: pub} ->
        Crypto.seal((s.pins && s.pins[recipient]) || pub, key, Vault.aad(s.vault.hid, ctx))

      nil ->
        raise ArgumentError, "cannot seal to unknown member #{inspect(recipient)}"
    end
  end

  defp entry_key!(s, id, seq) do
    s.entry_keys[{id, seq}] ||
      raise ArgumentError,
            "#{inspect(s.member)} must re-seal ledger entry #{seq} of #{inspect(id)} but cannot read it"
  end

  defp encrypt_personal(s) do
    record = %{
      links: Map.get(s.household.links, s.member, MapSet.new()),
      deletions: Map.get(s.household.deletions, s.member, [])
    }

    Crypto.encrypt(
      s.personal,
      Vault.encode(record),
      Vault.aad(s.vault.hid, {:personal, s.member})
    )
  end

  defp unchanged!(s, id, item, old) do
    same? =
      old != nil and Enum.sort(item.owners) == old.owners and
        Enum.sort(item.grantees) == old.grantees and
        length(s.household.ledger[id] || []) == length(old.ledger) and
        length(s.household.readings[id] || []) == length(Map.get(old, :readings, []))

    unless same?,
      do:
        raise(
          ArgumentError,
          "#{inspect(s.member)} changed item #{inspect(id)} without being able to read it"
        )
  end
end
