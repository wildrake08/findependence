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
    item_keys: %{},
    entry_keys: %{}
  ]

  @doc "Unlocks `member`. A wrong passphrase or unknown member is `{:error, :bad_credentials}`."
  def open(vault, member, passphrase) do
    with %{salt: salt, pub: pub, secret: box} <- vault.members[member],
         kek =
           Crypto.derive_key(passphrase, salt, vault.iterations, unsafe_test: vault.unsafe_test),
         {:ok, bin} <- Crypto.decrypt(kek, box, Vault.aad(vault.hid, {:member, member})) do
      %{priv: priv, personal: personal} = Vault.decode(bin)

      {:ok,
       build(%__MODULE__{vault: vault, member: member, pub: pub, priv: priv, personal: personal})}
    else
      _ -> {:error, :bad_credentials}
    end
  end

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

    {items, ledger, item_keys, entry_keys} =
      Enum.reduce(v.items, {%{}, %{}, %{}, %{}}, fn {id, rec}, {items, ledger, iks, eks} ->
        key = open_sealed(s, rec.keys[s.member], {:item_key, id, s.member})

        attrs =
          case key && Crypto.decrypt(key, rec.content, Vault.aad(v.hid, {:content, id})) do
            {:ok, bin} -> Vault.decode(bin)
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

        iks = if key, do: Map.put(iks, id, key), else: iks
        {Map.put(items, id, item), Map.put(ledger, id, entries), iks, eks}
      end)

    {links, deletions} = personal_record(s)
    existing = MapSet.new(Map.keys(items))
    # Links to items deleted by someone else are dropped here (ASM-018: ids are never reused).
    links = MapSet.filter(links, fn {i, val} -> i in existing and val in existing end)

    household = %Household{
      base
      | items: items,
        ledger: ledger,
        proposals: v.proposals,
        next_proposal: v.next_proposal,
        links: %{s.member => links},
        deletions: %{s.member => deletions}
    }

    %{s | household: household, baseline: household, item_keys: item_keys, entry_keys: entry_keys}
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
    readers = MapSet.union(MapSet.union(item.owners, item.grantees), presealed(s, id, item))
    ledger_readers = MapSet.union(item.owners, presealed(s, id, item))

    content =
      if old,
        do: old.content,
        else: Crypto.encrypt(key, Vault.encode(item.attrs), Vault.aad(v.hid, {:content, id}))

    keys =
      Map.new(readers, fn r ->
        {r, (old && old.keys[r]) || seal(s, r, key, {:item_key, id, r})}
      end)

    old_entries = if old, do: old.ledger, else: []
    entries = s.household.ledger[id] || []

    kept =
      for e <- old_entries do
        %{
          e
          | keys:
              Map.new(ledger_readers, fn r ->
                {r, e.keys[r] || seal(s, r, entry_key!(s, id, e.seq), {:entry_key, id, e.seq, r})}
              end)
        }
      end

    added =
      for entry <- Enum.drop(entries, length(old_entries)) do
        ek = Crypto.random_key()

        %{
          seq: entry.seq,
          box: Crypto.encrypt(ek, Vault.encode(entry), Vault.aad(v.hid, {:entry, id, entry.seq})),
          keys:
            Map.new(ledger_readers, fn r ->
              {r, seal(s, r, ek, {:entry_key, id, entry.seq, r})}
            end)
        }
      end

    %{
      owners: Enum.sort(item.owners),
      grantees: Enum.sort(item.grantees),
      content: content,
      keys: keys,
      ledger: kept ++ added
    }
  end

  # Once every current owner has consented to adding members to a value, those prospective
  # members may read it (REQ-115), so it is sealed to them as well (REQ-119, REQ-120).
  defp presealed(s, id, item) do
    if Map.get(item.attrs, :kind) == :value do
      for {_, %{item_id: ^id, change: {:owners, new}, consents: c}} <- s.household.proposals,
          MapSet.subset?(item.owners, c),
          m <- MapSet.difference(new, item.owners),
          m in s.household.members,
          into: MapSet.new(),
          do: m
    else
      MapSet.new()
    end
  end

  defp seal(s, recipient, key, ctx) do
    case s.vault.members[recipient] do
      %{pub: pub} -> Crypto.seal(pub, key, Vault.aad(s.vault.hid, ctx))
      nil -> raise ArgumentError, "cannot seal to unknown member #{inspect(recipient)}"
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
        length(s.household.ledger[id] || []) == length(old.ledger)

    unless same?,
      do:
        raise(
          ArgumentError,
          "#{inspect(s.member)} changed item #{inspect(id)} without being able to read it"
        )
  end
end
