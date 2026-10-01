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
  :household, :baseline, :pins, :sign_pins, :legacy, :before_signing, :item_keys, :entry_keys,
  :reading_keys, and :integrity. All Household logic stays in core; this module only encrypts and decrypts.

  WI-079 (security review FND-01, FND-04):

  - **Signed boxes.** Every content box, ledger entry, and reading written carries its author (`a`) and the
    author's Ed25519 signature (`s`) over `term_to_binary({hid, context, author, nonce <> tag <> ciphertext})`,
    where context is the box's associated-data context. `build/2` shows a box only if the signature verifies
    under the author's pinned signing key and the author was entitled to write it (see `entitled_entry?/3`);
    otherwise the box is a placeholder and `integrity_issues/1` reports it. A box written before signing is
    accepted only if it is in the member's own record of boxes that were unsigned when they first opened the
    household after the upgrade (`:legacy`, hashes; local form only); it is then marked as written before
    signing (`written_before_signing/2`).
  - **Seal commitments.** Every seal written carries `k = HMAC-SHA256(sealed key, "findependence seal-commit
    v1" <> term_to_binary(recipient))`. A reader already present in the state as loaded is extended new keys
    only if the saving member can verify their existing seal's commitment under the key the member holds (or
    the seal is in the member's legacy record). A reader who fails is never sealed anything and is reported
    as `{:unverified_seal, item, member}` for as long as their seal stays.
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
                  # WI-079: signing keys and pins, signatures, seal commitments, the legacy record
                  :sign_pub,
                  :sign_pins,
                  :signers,
                  :legacy,
                  :a,
                  :s,
                  :k,
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

  @doc """
  Decodes stored bytes: `[:safe]`, so no atom is created, and plain data only: a term holding a function,
  pid, port, or reference raises `FindependenceShared.SafeTerm.UnsafeTermError` (WI-079, FND-02).
  """
  def decode(bin), do: FindependenceShared.SafeTerm.decode!(bin)

  @doc "The members still in the household, as a core Household would see them."
  def members(%{member_order: order, members: members}) when is_list(order) and is_map(members),
    do: Enum.filter(order, &Map.has_key?(members, &1))

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

    {sign_pub, signing} = Crypto.signing_keypair(s.priv)

    items =
      Map.new(h.items, fn {id, item} ->
        old = v.items[id]

        if s.item_keys[id] do
          {id, encrypt_item(s, id, item, old, signing)}
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

    # WI-079: the member's signing key is published with their other public key (the local form's members
    # map; the hosted form keeps it in the accounts table and ignores this copy).
    members =
      case v.members[s.member] do
        %{} = me -> Map.put(v.members, s.member, Map.put(me, :sign_pub, sign_pub))
        nil -> v.members
      end

    vault = %{
      v
      | members: Map.drop(members, MapSet.to_list(departed)),
        items: items,
        proposals: h.proposals,
        next_proposal: h.next_proposal,
        personal: personal
    }

    # WI-079: a departing member's signing key is kept (`:signers`), so what they signed can still be checked
    # by a member who first opens the household after they left.
    kept_signers =
      for m <- departed, %{sign_pub: pub} <- [v.members[m]], into: %{}, do: {m, pub}

    vault =
      if kept_signers == %{},
        do: vault,
        else: Map.put(vault, :signers, Map.merge(Map.get(v, :signers, %{}), kept_signers))

    build(%{s | vault: vault}, normalize)
  end

  # ---------------------------------------------------------------------------
  # Decryption

  @doc """
  The member's view of `s.vault`: decrypts what `s.member` may read, with placeholders for the rest.
  `normalize` converts an item's attributes as read (the local form's pre-cents amounts, WI-021).

  WI-079: signing keys published in the state are pinned on first sight (`:sign_pins`); a view whose
  `:legacy` is `:snapshot` (a local member's first opening after the upgrade) records every box and seal
  written before signing as its legacy record first. A box is shown only if genuine (see the moduledoc).
  """
  def build(s, normalize \\ &Function.identity/1) do
    s = s |> pin_signers() |> snapshot_legacy()
    v = s.vault
    base = empty_household(v)

    {items, ledger, item_keys, entry_keys, readings, reading_keys, issues, before} =
      Enum.reduce(v.items, {%{}, %{}, %{}, %{}, %{}, %{}, [], %{}}, fn {id, rec},
                                                                       {items, ledger, iks, eks,
                                                                        rds, rks, issues, before} ->
        key = open_sealed(s, rec.keys[s.member], {:item_key, id, s.member})
        owners = MapSet.new(rec.owners)

        # History first: who owned the item when is what entitles the other boxes' authors.
        {entries, eks, history} = open_ledger(s, id, rec, eks)

        content =
          case key && Crypto.decrypt(key, rec.content, aad(v.hid, {:content, id})) do
            {:ok, bin} ->
              status = box_status(s, {:content, id}, rec.content)
              {verdict(status, content_author?(status, owners, history)), bin}

            _ ->
              nil
          end

        # A content box that isn't genuine leaves the item unreadable, as if its key were missing: its
        # key is never used to seal anything (WI-079).
        {attrs, key, content_issues, content_legacy?} =
          case content do
            {:ok, bin} -> {bin |> decode() |> normalize.(), key, [], false}
            {:legacy, bin} -> {bin |> decode() |> normalize.(), key, [], true}
            {{:issue, kind}, _} -> {%{}, nil, [{kind, id, :content}], false}
            nil -> {%{}, nil, [], false}
          end

        item = %{
          id: id,
          attrs: attrs,
          owners: owners,
          grantees: MapSet.new(rec.grantees)
        }

        # CAP-010 readings (REQ-132/133): each has its own key; placeholders for any not sealed to us
        {item_readings, rks, reading_issues, readings_legacy?} =
          open_readings(s, id, rec, owners, history, rks)

        seal_issues = seal_issues(s, id, rec, key, eks, rks)

        rds = if item_readings == [], do: rds, else: Map.put(rds, id, item_readings)
        iks = if key, do: Map.put(iks, id, key), else: iks

        parts =
          for {part, true} <- [
                content: content_legacy?,
                history: history.legacy?,
                readings: readings_legacy?
              ],
              do: part

        before = if parts == [], do: before, else: Map.put(before, id, parts)

        {Map.put(items, id, item), Map.put(ledger, id, entries), iks, eks, rds, rks,
         [issues, history.issues, content_issues, reading_issues, seal_issues], before}
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

    box_issues = issues |> List.flatten() |> Enum.sort() |> Enum.uniq()

    %{
      s
      | household: household,
        baseline: household,
        item_keys: item_keys,
        entry_keys: entry_keys,
        reading_keys: reading_keys,
        before_signing: before,
        integrity: integrity_check(s) ++ box_issues
    }
  end

  @doc """
  Signs that the stored state was changed outside the app (WI-020, WI-079). The plaintext structure is not
  authenticated, so the first four are detection heuristics; the others are checked cryptographically, as
  far as the member's own keys reach:

  - `{:reader_without_key, item, member}`: a listed owner or grantee has no sealed key. Legitimate
    additions always come with a key, so this means the reader list was edited.
  - `{:owner_without_ledger_key, item, member}`: an owner cannot open some history entry.
  - `{:unknown_member_referenced, item, member}`: an item names someone who isn't a member.
  - `{:public_key_changed, member}`: a member's public key differs from the one pinned at setup.
  - `{:signing_key_changed, member}`: a member's published signing key differs from the one pinned.
  - `{:unverified_seal, item, member}`: a seal to `member` (of the item's key, or of a history entry's or
    balance's key the member holds) carries no valid commitment and was not there before signing began:
    it was not written by a holder of that key. Nothing new is sealed to that member.
  - `{:unsigned_box, item, where}`, `{:bad_signature, item, where}`, `{:signer_not_entitled, item, where}`:
    the item's content (`where` = `:content`), a history entry (`{:entry, seq}`), or a balance
    (`{:reading, seq}`) is unsigned (and not in the member's record of boxes from before signing), its
    signature does not verify under its author's pinned signing key, or its author could not have written
    it. It is not shown.
  """
  def integrity_issues(%{integrity: issues}), do: issues

  @doc """
  Which parts of item `id` the member's view accepted as written before signing began (WI-079): any of
  `:content`, `:history`, `:readings`. Empty for everything written since, and always in the hosted form.
  """
  def written_before_signing(s, id), do: Map.get(Map.get(s, :before_signing) || %{}, id, [])

  defp integrity_check(s) do
    v = s.vault

    pin_issues =
      for {m, pinned} <- s.pins || %{},
          %{pub: pub} <- [v.members[m]],
          pub != pinned,
          do: {:public_key_changed, m}

    signers = Map.get(v, :signers, %{})

    sign_pin_issues =
      for {m, pinned} <- Enum.sort(sign_pins(s)),
          published = get_in(v.members, [m, :sign_pub]) || signers[m],
          is_binary(published) and published != pinned,
          do: {:signing_key_changed, m}

    item_issues =
      for {id, rec} <- Enum.sort(v.items),
          issue <- item_integrity(v, id, rec),
          do: issue

    pin_issues ++ sign_pin_issues ++ item_issues
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

  # The item's history as the member can read it. Each entry is shown only if genuine; replaying the genuine
  # ones in order gives who owned the item before each, which is what entitles an entry's signer, and
  # everyone who has owned it (`ever`), which entitles the authors of its content and balances. An entry's key
  # is kept even when the entry is not shown, so the member's saves can still seal it to new owners.
  defp open_ledger(s, id, rec, eks) do
    init = %{
      owners: MapSet.new(),
      ever: MapSet.new(),
      created_by: nil,
      reading_by: %{},
      known?: false,
      legacy?: false,
      issues: []
    }

    {entries, {eks, history}} =
      Enum.map_reduce(rec.ledger, {eks, init}, fn e, {eks, h} ->
        ek = open_sealed(s, e.keys[s.member], {:entry_key, id, e.seq, s.member})
        ctx = {:entry, id, e.seq}

        case ek && Crypto.decrypt(ek, e.box, aad(s.vault.hid, ctx)) do
          {:ok, bin} ->
            entry = decode(bin)
            eks = Map.put(eks, {id, e.seq}, ek)
            status = box_status(s, ctx, e.box)

            case verdict(status, entitled_entry?(status, entry, h.owners)) do
              v when v in [:ok, :legacy] ->
                after_owners = owners_after(entry, h.owners)

                h = %{
                  h
                  | owners: after_owners,
                    ever: h.ever |> MapSet.union(h.owners) |> MapSet.union(after_owners),
                    created_by: created_by(entry, h.created_by),
                    reading_by: reading_by(entry, h.reading_by),
                    known?: true,
                    legacy?: h.legacy? or v == :legacy
                }

                {entry, {eks, h}}

              {:issue, kind} ->
                h = %{h | known?: true, issues: [{kind, id, {:entry, e.seq}} | h.issues]}
                {:sealed, {eks, h}}
            end

          _ ->
            {:sealed, {eks, h}}
        end
      end)

    {entries, eks, history}
  end

  defp open_readings(s, id, rec, owners, history, rks) do
    {list, {rks, issues, legacy?}} =
      Enum.map_reduce(Map.get(rec, :readings, []), {rks, [], false}, fn r,
                                                                        {rks, issues, legacy?} ->
        ctx = {:reading, id, r.seq}
        rk = open_sealed(s, r.keys[s.member], {:reading_key, id, r.seq, s.member})

        case rk && Crypto.decrypt(rk, r.box, aad(s.vault.hid, ctx)) do
          {:ok, bin} ->
            reading = decode(bin)
            rks = Map.put(rks, {id, r.seq}, rk)
            status = box_status(s, ctx, r.box)

            by_matches? =
              case status do
                {:signed, author} ->
                  not is_map(reading) or Map.get(reading, :by, author) == author

                _ ->
                  true
              end

            case verdict(status, by_matches? and reading_author?(status, r.seq, owners, history)) do
              :ok ->
                {reading, {rks, issues, legacy?}}

              :legacy ->
                {reading, {rks, issues, true}}

              {:issue, kind} ->
                {:sealed, {rks, [{kind, id, {:reading, r.seq}} | issues], legacy?}}
            end

          _ ->
            {:sealed, {rks, issues, legacy?}}
        end
      end)

    {list, rks, issues, legacy?}
  end

  # Seals to others that the member can check (they hold the sealed key) and that carry no valid commitment
  # and were not there before signing began (WI-079).
  defp seal_issues(s, id, rec, key, eks, rks) do
    item =
      if key,
        do:
          for({r, sealed} <- rec.keys, not vouched?(s, sealed, key, r, {:item_key, id, r}), do: r),
        else: []

    boxes = fn list, kind, keys ->
      for b <- list,
          k = keys[{id, b.seq}],
          k != nil,
          {r, sealed} <- b.keys,
          not vouched?(s, sealed, k, r, {kind, id, b.seq, r}),
          do: r
    end

    (item ++
       boxes.(rec.ledger, :entry_key, eks) ++
       boxes.(Map.get(rec, :readings, []), :reading_key, rks))
    |> Enum.uniq()
    |> Enum.map(&{:unverified_seal, id, &1})
  end

  # A seal is vouched for if its commitment verifies under the key it seals, or it was in the member's record
  # of seals written before commitments began.
  defp vouched?(s, sealed, key, recipient, ctx) do
    Crypto.commitment_valid?(key, recipient, Map.get(sealed, :k)) or
      legacy?(s, seal_hash(ctx, sealed))
  end

  # :ok, :legacy, or {:issue, kind}
  defp verdict({:signed, _author}, true), do: :ok
  defp verdict({:signed, _author}, false), do: {:issue, :signer_not_entitled}
  defp verdict(:legacy, _), do: :legacy
  defp verdict(:unsigned, _), do: {:issue, :unsigned_box}
  defp verdict(:bad_signature, _), do: {:issue, :bad_signature}

  # Content and balances are written by an owner. Who owned the item earlier is known only from its history,
  # which only owners read: a member who can read some of it (`known?`) requires a current owner or one its
  # genuine entries show; a member who can read none of it accepts any member whose signature verifies under
  # a pinned key (a former owner's content stays readable to those it is shared with after they stop owning).
  # WI-080 (REV-107; aligning with ASSESS-001 FND-04): who may have written a box is who owned the item when it
  # was written, as its genuine history shows. An item's details are written once, at creation, so their author
  # is whoever signed the history's :created entry; a balance's author is whoever its genuine :reading_added
  # entry names. Someone who owned the item once and gave it up can no longer add a balance others accept. A
  # member who can read none of the history (someone it is shared with) can't check this; for them a signature
  # under a pinned key is enough (recorded as a residual in WI-080).
  defp content_author?({:signed, author}, _owners, %{known?: true} = history),
    do: author == history.created_by

  defp content_author?({:signed, _author}, _owners, _history), do: true
  defp content_author?(_status, _owners, _history), do: false

  defp reading_author?({:signed, author}, seq, _owners, %{known?: true} = history),
    do: author in Map.get(history.reading_by, seq, [])

  defp reading_author?({:signed, _author}, _seq, _owners, _history), do: true
  defp reading_author?(_status, _seq, _owners, _history), do: false

  defp created_by(%{event: :created, by: [creator | _]}, nil), do: creator
  defp created_by(_entry, created_by), do: created_by

  defp reading_by(%{event: :reading_added, by: by, details: %{seq: seq}}, acc) when is_list(by),
    do: Map.put(acc, seq, by)

  defp reading_by(_entry, acc), do: acc

  # A history entry's signer is one of those it names as acting (`by`), and was entitled to act: an owner
  # before it, except for the first entry (the creator), a change of owners (a joining owner agrees too), and
  # a departing member's own departure.
  defp entitled_entry?({:signed, author}, %{by: by, event: event} = entry, owners)
       when is_list(by) do
    details = if is_map(entry[:details]), do: entry.details, else: %{}

    author in by and
      case event do
        :created -> MapSet.size(owners) == 0
        :owners_changed -> author in owners or author in List.wrap(details[:owners])
        :grantee_departed -> details[:grantee] == author
        _ -> author in owners
      end
  end

  defp entitled_entry?(_status, _entry, _owners), do: false

  defp owners_after(%{event: :created, details: %{owners: o}}, _before),
    do: MapSet.new(List.wrap(o))

  defp owners_after(%{event: :owners_changed, details: %{owners: o}}, _before),
    do: MapSet.new(List.wrap(o))

  defp owners_after(%{event: :owner_relinquished, details: %{owner: o}}, before),
    do: MapSet.delete(before, o)

  defp owners_after(_entry, before), do: before

  # {:signed, author}, :legacy, :unsigned, or :bad_signature
  defp box_status(s, ctx, box) do
    case box do
      %{a: author, s: sig} ->
        pub = sign_pins(s)[author]

        if pub && Crypto.verify(pub, signed_message(s.vault.hid, ctx, author, box), sig),
          do: {:signed, author},
          else: :bad_signature

      _ ->
        if legacy?(s, box_hash(ctx, box)), do: :legacy, else: :unsigned
    end
  end

  @doc false
  # What a box's signature covers (WI-079): the household, the box's associated-data context, its author, and
  # its nonce, tag, and ciphertext (fixed-length nonce and tag, so the concatenation is unambiguous).
  def signed_message(hid, ctx, author, %{n: n, c: c, t: t})
      when is_binary(n) and is_binary(c) and is_binary(t),
      do: :erlang.term_to_binary({hid, ctx, author, n <> t <> c})

  def signed_message(hid, ctx, author, _box), do: :erlang.term_to_binary({hid, ctx, author})

  defp sign_box(s, signing_priv, ctx, box) do
    sig = Crypto.sign(signing_priv, signed_message(s.vault.hid, ctx, s.member, box))
    Map.merge(box, %{a: s.member, s: sig})
  end

  # ---------------------------------------------------------------------------
  # Signing keys and the legacy record (WI-079)

  defp sign_pins(s), do: Map.get(s, :sign_pins) || %{}

  # The member's own signing key is derived from their private key; any other member's is pinned the first
  # time it is seen (trust on first use, as the hosted form's public keys). A pinned key that later differs
  # from the published one is reported and never used.
  defp pin_signers(s) do
    {own, _} = Crypto.signing_keypair(s.priv)
    pinned = sign_pins(s)

    # Members who left keep their signing key in `:signers` (local form); only someone the member's own pins
    # know from setup is pinned from there.
    departed =
      for {m, pub} <- Map.get(s.vault, :signers, %{}),
          not Map.has_key?(s.vault.members, m),
          Map.has_key?(s.pins || %{}, m),
          do: {m, %{sign_pub: pub}}

    new =
      for {m, %{sign_pub: pub}} <- Enum.to_list(s.vault.members) ++ departed,
          m != s.member,
          not Map.has_key?(pinned, m),
          is_binary(pub) and byte_size(pub) == 32,
          into: %{},
          do: {m, pub}

    %{s | sign_pins: pinned |> Map.merge(new) |> Map.put(s.member, own)}
  end

  defp legacy?(s, hash) do
    case Map.get(s, :legacy) do
      %MapSet{} = set -> hash in set
      _ -> false
    end
  end

  # A local member's first opening after the upgrade: every box without a signature and every seal without
  # a commitment in the file now was written before signing began (or tampered in before this moment; that
  # residual is documented), and is recorded, as hashes, in the member's own encrypted secret.
  defp snapshot_legacy(%{legacy: :snapshot} = s) do
    set =
      for {id, rec} <- s.vault.items,
          hash <- legacy_hashes(id, rec),
          into: MapSet.new(),
          do: hash

    %{s | legacy: set}
  end

  defp snapshot_legacy(s), do: s

  defp legacy_hashes(id, rec) do
    boxes = fn list, kind, key_kind ->
      for b <- list,
          h <-
            unsigned_hash({kind, id, b.seq}, b.box) ++
              for(
                {r, sealed} <- b.keys,
                h <- uncommitted_hash({key_kind, id, b.seq, r}, sealed),
                do: h
              ),
          do: h
    end

    unsigned_hash({:content, id}, rec.content) ++
      for({r, sealed} <- rec.keys, h <- uncommitted_hash({:item_key, id, r}, sealed), do: h) ++
      boxes.(rec.ledger, :entry, :entry_key) ++
      boxes.(Map.get(rec, :readings, []), :reading, :reading_key)
  end

  defp unsigned_hash(_ctx, %{s: _}), do: []
  defp unsigned_hash(ctx, box), do: [box_hash(ctx, box)]
  defp uncommitted_hash(_ctx, %{k: _}), do: []
  defp uncommitted_hash(ctx, sealed), do: [seal_hash(ctx, sealed)]

  defp box_hash(ctx, box),
    do: short_hash({ctx, Map.get(box, :n), Map.get(box, :c), Map.get(box, :t)})

  defp seal_hash(ctx, sealed),
    do:
      short_hash(
        {ctx, Map.get(sealed, :e), Map.get(sealed, :n), Map.get(sealed, :c), Map.get(sealed, :t)}
      )

  defp short_hash(term),
    do: binary_part(:crypto.hash(:sha256, :erlang.term_to_binary(term)), 0, 16)

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

  defp encrypt_item(s, id, item, old, signing) do
    v = s.vault
    key = s.item_keys[id]
    presealed = presealed(s.household.proposals, s.household.members, id, item)
    readers = MapSet.union(MapSet.union(item.owners, item.grantees), presealed)
    ledger_readers = MapSet.union(item.owners, presealed)
    old_entries = if old, do: old.ledger, else: []

    # WI-020, WI-079: a key is sealed only to readers THIS session added, or to readers already listed whose
    # existing seal the member can verify: its commitment verifies under the key the member holds (so it was
    # written by a holder of that key), or it is in the member's record from before commitments began. A
    # reader listed in the loaded state without a key, or with a seal the member can't verify, can only have
    # been written in by editing the state, and is never given a key here (see integrity_issues/1).
    {was_reader, was_ledger_reader} = baseline_readers(s, id)

    verified_reader? = fn r ->
      sealed = old && old.keys[r]
      sealed != nil and vouched?(s, sealed, key, r, {:item_key, id, r})
    end

    # Evidence of being entitled to the item's history: a vouched seal of one of its entries' keys. A member
    # who holds none of them (a departing member who could see the item writes its last entry) has only the
    # item key to check against.
    held_entries = Enum.filter(old_entries, &s.entry_keys[{id, &1.seq}])

    verified_ledger_reader? = fn r ->
      if held_entries == [] do
        verified_reader?.(r)
      else
        Enum.any?(held_entries, fn e ->
          sealed = e.keys[r]

          sealed != nil and
            vouched?(s, sealed, s.entry_keys[{id, e.seq}], r, {:entry_key, id, e.seq, r})
        end)
      end
    end

    trusted = %{
      reader: fn r -> r not in was_reader or verified_reader?.(r) end,
      ledger: fn r -> r not in was_ledger_reader or verified_ledger_reader?.(r) end
    }

    content =
      if old,
        do: old.content,
        else:
          sign_box(
            s,
            signing,
            {:content, id},
            Crypto.encrypt(key, encode(item.attrs), aad(v.hid, {:content, id}))
          )

    keys =
      for r <- readers, (old && old.keys[r]) || r not in was_reader, into: %{} do
        {r, (old && old.keys[r]) || seal(s, r, key, {:item_key, id, r})}
      end

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
        ctx = {:entry, id, entry.seq}

        %{
          seq: entry.seq,
          box: sign_box(s, signing, ctx, Crypto.encrypt(ek, encode(entry), aad(v.hid, ctx))),
          keys:
            for r <- ledger_readers, trusted.ledger.(r), into: %{} do
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
      readings: encrypt_readings(s, id, item, old, trusted, signing)
    }
  end

  # CAP-010 (REQ-132, REQ-133, CP-013 A): each reading has its own key. The latest is sealed to
  # everyone who can read the item; earlier ones to its owners only. Keys of anyone no longer
  # entitled are dropped. A new key goes only to a reader this session added or one whose existing seal the
  # member verified (WI-020, WI-079): for the latest, a seal of the item key; for earlier ones, which only
  # owners read, a seal of a history entry's key.
  defp encrypt_readings(s, id, item, old, trusted, signing) do
    v = s.vault
    old_readings = (old && Map.get(old, :readings)) || []
    readings = s.household.readings[id] || []
    latest = length(readings)
    item_readers = MapSet.union(item.owners, item.grantees)
    entitled = fn seq -> if seq == latest, do: item_readers, else: item.owners end
    trusted? = fn m, seq -> if seq == latest, do: trusted.reader.(m), else: trusted.ledger.(m) end

    kept =
      for r <- old_readings do
        %{
          r
          | keys:
              for m <- entitled.(r.seq), r.keys[m] || trusted?.(m, r.seq), into: %{} do
                {m,
                 r.keys[m] || seal(s, m, reading_key!(s, id, r.seq), {:reading_key, id, r.seq, m})}
              end
        }
      end

    added =
      for reading <- Enum.drop(readings, length(old_readings)) do
        rk = Crypto.random_key()
        ctx = {:reading, id, reading.seq}

        %{
          seq: reading.seq,
          box: sign_box(s, signing, ctx, Crypto.encrypt(rk, encode(reading), aad(v.hid, ctx))),
          keys:
            for m <- entitled.(reading.seq), trusted?.(m, reading.seq), into: %{} do
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

  # Every seal carries its commitment (WI-079).
  defp seal(s, recipient, key, ctx) do
    case s.vault.members[recipient] do
      # the pinned key when there is one, never a key swapped into the plaintext file (WI-020)
      %{pub: pub} ->
        (s.pins && s.pins[recipient])
        |> Kernel.||(pub)
        |> Crypto.seal(key, aad(s.vault.hid, ctx))
        |> Map.put(:k, Crypto.commit(key, recipient))

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
