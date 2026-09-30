defmodule FindependenceShared.Envelope do
  @moduledoc """
  A member's view of a household's sealed state, shared by both forms (REV-099 G2; MEC-013, MEC-014;
  REQ-119..122). Moved without change from the local form's Session and Vault (WI-074).

  The state (called the vault, as in the local form) holds members' public keys; items with plaintext
  structure (owners, grantees), content encrypted under a per-item key, and that key sealed to each reader;
  ledger entries and readings, each under its own key sealed to its readers; proposals (plaintext
  structure, ASM-020); and each member's personal record under their personal key. The local form keeps it
  in the vault file; the hosted form in PostgreSQL rows.

  `build/2` decrypts exactly what the member may read; everything else becomes a placeholder: empty
  attributes, and `:sealed` ledger entries. Callers change `household` with the unmodified core API, then
  `save/2` re-encrypts: it seals item keys and ledger entries to exactly the members who may now read them
  and writes the member's own personal record.

  Invariant: a view only changes items its member can read. `save/2` raises if any other item changed,
  which would mean the core let a member act on an item they cannot see.

  A view is a map (each form's session struct) with the fields :vault, :member, :pub, :priv, :personal,
  :household, :baseline, :pins, :item_keys, :entry_keys, :reading_keys, and :integrity. All Household
  logic stays in core; this module only encrypts and decrypts.
  """

  alias FindependenceShared.Crypto
  alias Findependence.Household

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
                  :pins,
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
                  :unit,
                  :cents,
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
                  # REQ-129 frequencies, taken from core so the two lists cannot drift apart (CP-012)
                ] ++
                  Findependence.Alignment.frequency_atoms() ++
                  [:readings, :reading | Findependence.Balances.format_atoms()] ++
                  Findependence.Plans.format_atoms() ++
                  Findependence.Retirement.format_atoms() ++
                  Findependence.Import.format_atoms() ++
                  Findependence.Attach.format_atoms()

  @doc false
  def format_atoms, do: @format_atoms

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

  @doc """
  Rebuilds the session on a newer vault without the passphrase, using keys it has already
  unlocked. Used to serialize saves by different members on one device, so none is lost.
  """
  def refresh(s, vault, normalize \\ &Function.identity/1),
    do: build(%{s | vault: vault}, normalize)

  @doc "Encrypts the session's household back into a new vault, and returns the refreshed session."
  def save(s, normalize \\ &Function.identity/1) do
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

    build(%{s | vault: vault}, normalize)
  end

  # ---------------------------------------------------------------------------
  # Decryption

  @doc """
  The member's view of `s.vault`: decrypts what `s.member` may read, with placeholders for the rest.
  `normalize` converts an item's attributes as read (the local form's pre-cents amounts, WI-021).
  """
  def build(s, normalize \\ &Function.identity/1) do
    v = s.vault
    base = empty_household(v)

    {items, ledger, item_keys, entry_keys, readings, reading_keys} =
      Enum.reduce(v.items, {%{}, %{}, %{}, %{}, %{}, %{}}, fn {id, rec},
                                                              {items, ledger, iks, eks, rds, rks} ->
        key = open_sealed(s, rec.keys[s.member], {:item_key, id, s.member})

        attrs =
          case key && Crypto.decrypt(key, rec.content, aad(v.hid, {:content, id})) do
            # WI-021: amounts stored before cents are converted in memory (stored content is immutable)
            {:ok, bin} -> bin |> decode() |> normalize.()
            _ -> %{}
          end

        {entries, eks} =
          Enum.map_reduce(rec.ledger, eks, fn e, eks ->
            ek = open_sealed(s, e.keys[s.member], {:entry_key, id, e.seq, s.member})

            case ek && Crypto.decrypt(ek, e.box, aad(v.hid, {:entry, id, e.seq})) do
              {:ok, bin} -> {decode(bin), Map.put(eks, {id, e.seq}, ek)}
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

            case rk && Crypto.decrypt(rk, r.box, aad(v.hid, {:reading, id, r.seq})) do
              {:ok, bin} -> {decode(bin), Map.put(rks, {id, r.seq}, rk)}
              _ -> {:sealed, rks}
            end
          end)

        rds = if item_readings == [], do: rds, else: Map.put(rds, id, item_readings)
        iks = if key, do: Map.put(iks, id, key), else: iks
        {Map.put(items, id, item), Map.put(ledger, id, entries), iks, eks, rds, rks}
      end)

    {links, deletions, plans, depends, goals} = personal_record(s)
    existing = MapSet.new(Map.keys(items))
    # Links to items deleted by someone else are dropped here (ASM-018: ids are never reused).
    links = MapSet.filter(links, fn {i, val} -> i in existing and val in existing end)

    # DEF-061 (REV-102): so are contributions to retirement accounts someone else deleted (REQ-150 AC-9); both
    # are gone from the member's record at their next save.
    goals = drop_gone_contributions(goals, existing)

    household = %Household{
      base
      | items: items,
        ledger: ledger,
        readings: readings,
        proposals: v.proposals,
        next_proposal: v.next_proposal,
        links: %{s.member => links},
        deletions: %{s.member => deletions},
        plans: %{s.member => plans},
        depends: %{s.member => depends},
        goals: %{s.member => goals}
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
  def integrity_issues(%{integrity: issues}), do: issues

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
    case Crypto.open(s.pub, s.priv, sealed, aad(s.vault.hid, ctx)) do
      {:ok, key} -> key
      :error -> nil
    end
  end

  defp personal_record(s) do
    case s.vault.personal[s.member] do
      nil ->
        {MapSet.new(), [], %{}, MapSet.new(), %{}}

      box ->
        {:ok, bin} =
          Crypto.decrypt(s.personal, box, aad(s.vault.hid, {:personal, s.member}))

        %{links: links, deletions: deletions} = record = decode(bin)
        # MEC-019 (v0.3): plans, marks, and goals; absent in records written before
        {links, deletions, Map.get(record, :plans, %{}), Map.get(record, :depends, MapSet.new()),
         Map.get(record, :goals, %{})}
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
        else: Crypto.encrypt(key, encode(item.attrs), aad(v.hid, {:content, id}))

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
          box: Crypto.encrypt(ek, encode(entry), aad(v.hid, {:entry, id, entry.seq})),
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
              encode(reading),
              aad(v.hid, {:reading, id, reading.seq})
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
    # REQ-115, and REQ-148 for shared plans
    if Map.get(item.attrs, :kind) in [:value, :plan] do
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
        Crypto.seal((s.pins && s.pins[recipient]) || pub, key, aad(s.vault.hid, ctx))

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
      deletions: Map.get(s.household.deletions, s.member, []),
      plans: Map.get(s.household.plans, s.member, %{}),
      depends: Map.get(s.household.depends, s.member, MapSet.new()),
      goals: Map.get(s.household.goals, s.member, %{})
    }

    Crypto.encrypt(
      s.personal,
      encode(record),
      aad(s.vault.hid, {:personal, s.member})
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

  defp drop_gone_contributions(%{retirement: %{contributions: c} = r} = goals, existing),
    do: %{
      goals
      | retirement: %{r | contributions: Map.filter(c, fn {id, _} -> id in existing end)}
    }

  defp drop_gone_contributions(goals, _existing), do: goals
end
