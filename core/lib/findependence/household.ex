defmodule Findependence.Household do
  @moduledoc """
  Consent-governed ownership and visibility of a household's economic items (CAP-001).

  A pure data structure: every operation takes the acting member and returns
  `{:ok, household}` (`{:ok, household, proposal_id}` for proposals) or `{:error, reason}`. There is no persistence, network, or process
  state. The rules are enforced at this API; code that reads the struct directly bypasses
  them, so this is not a security boundary (ASM-013).

  - MEC-004 owner-set item model with unilateral self-removal (supersedes MEC-001): REQ-101, REQ-107
  - MEC-002 deny-by-default visibility (write side): REQ-103
  - MEC-003 per-item change ledger: REQ-105, via `Findependence.Ledger`

  Reads and aggregates are in `Findependence.View` (REQ-102, REQ-106).
  """

  alias Findependence.Ledger

  @enforce_keys [:members]
  defstruct members: MapSet.new(),
            items: %{},
            proposals: %{},
            ledger: %{},
            deletions: %{},
            links: %{},
            readings: %{},
            next_proposal: 1

  @type member :: term()
  @type item_id :: term()
  @type t :: %__MODULE__{}

  @doc "A household with the given members and no items."
  def new(members) when is_list(members), do: %__MODULE__{members: MapSet.new(members)}

  @doc """
  Adds an item owned by `actor` alone. Joint ownership is reached through
  `propose_owners/4`, so nobody becomes an owner without the consent of the current owners.
  """
  def add_item(%__MODULE__{} = h, actor, item_id, attrs \\ %{}) do
    cond do
      not member?(h, actor) ->
        {:error, :not_a_member}

      Map.has_key?(h.items, item_id) ->
        {:error, :item_exists}

      true ->
        item = %{id: item_id, attrs: attrs, owners: MapSet.new([actor]), grantees: MapSet.new()}

        h
        |> put_in([Access.key(:items), item_id], item)
        |> Ledger.record(item_id, actor, :created, %{owners: [actor]})
        |> ok()
    end
  end

  @doc """
  Proposes replacing the owner set of an item (REQ-104). Only a current owner may propose, so
  no member can add themselves. The new owner set must be non-empty and contain only
  members (REQ-101). The change is applied once every current owner has consented.
  """
  def propose_owners(h, actor, item_id, new_owners) do
    new_owners = MapSet.new(new_owners)

    with {:ok, item} <- owned_item(h, actor, item_id),
         :ok <- valid_owner_set(h, new_owners) do
      if MapSet.equal?(new_owners, item.owners),
        do: {:error, :no_change},
        else: propose(h, actor, item_id, {:owners, new_owners})
    end
  end

  @doc """
  Proposes a visibility grant to `grantee` (REQ-103). Only an owner may propose. With a
  single owner the grant takes effect at once; with several, it takes effect once every
  current owner has consented.
  """
  def propose_grant(h, actor, item_id, grantee) do
    with {:ok, item} <- owned_item(h, actor, item_id) do
      cond do
        not member?(h, grantee) -> {:error, :not_a_member}
        grantee in item.owners -> {:error, :already_owner}
        grantee in item.grantees -> {:error, :already_granted}
        true -> propose(h, actor, item_id, {:grant, grantee})
      end
    end
  end

  @doc "Revokes a grant (REQ-103). Any single owner may revoke; nobody else can."
  def revoke_grant(h, actor, item_id, grantee) do
    with {:ok, item} <- owned_item(h, actor, item_id) do
      if grantee in item.grantees do
        h
        |> update_in([Access.key(:items), item_id, :grantees], &MapSet.delete(&1, grantee))
        |> Ledger.record(item_id, actor, :grant_revoked, %{grantee: grantee})
        |> drop_stale_proposals(item_id)
        |> ok()
      else
        {:error, :not_granted}
      end
    end
  end

  @doc """
  Records `actor`'s consent to a pending proposal. The proposal is applied once the consents
  cover the item's owners *at that moment*: if the owners change while it is pending, the new
  owners must consent too.
  """
  def consent(h, actor, proposal_id) do
    with {:ok, proposal} <- fetch_proposal(h, proposal_id),
         :ok <- may_consent(h, actor, proposal) do
      h
      |> update_in([Access.key(:proposals), proposal_id, :consents], &MapSet.put(&1, actor))
      |> apply_if_consented(proposal_id)
      |> ok()
    end
  end

  @doc """
  Removes `actor` from an item's owners without anyone else's consent (REQ-107, CP-003). Only
  allowed while another owner remains; a sole owner must transfer or delete instead
  (`Findependence.Exit.delete/3`). Pending proposals on the item that the relinquishing owner
  made, or that would restore them as an owner, are dropped.
  """
  def relinquish(h, actor, item_id) do
    with {:ok, item} <- owned_item(h, actor, item_id) do
      if MapSet.size(item.owners) == 1 do
        {:error, :sole_owner}
      else
        h
        |> update_in([Access.key(:items), item_id, :owners], &MapSet.delete(&1, actor))
        |> Ledger.record(item_id, actor, :owner_relinquished, %{owner: actor})
        |> drop_proposals(fn p ->
          p.item_id == item_id and (p.proposed_by == actor or restores_owner?(p.change, actor))
        end)
        |> drop_stale_proposals(item_id)
        |> ok()
      end
    end
  end

  defp restores_owner?({:owners, owners}, member), do: member in owners
  defp restores_owner?(_, _), do: false

  @doc false
  def drop_proposals(h, pred),
    do: Map.update!(h, :proposals, &Map.reject(&1, fn {_, p} -> pred.(p) end))

  @doc """
  Withdraws a pending proposal (REQ-125). The member who made it, or any current owner of its
  item, may withdraw it. A proposer who has stopped owning the item has already lost their
  proposals (REQ-107), so in practice this means any current owner. Grantees and prospective
  joiners cannot withdraw; a joiner declines by not agreeing. Nothing about the item changes, so
  nothing is written to the ledger.
  """
  def withdraw(h, actor, proposal_id) do
    with {:ok, proposal} <- fetch_proposal(h, proposal_id),
         {:ok, _item} <- owned_item(h, actor, proposal.item_id) do
      {:ok, Map.update!(h, :proposals, &Map.delete(&1, proposal_id))}
    end
  end

  @doc "Pending proposals visible to `actor`: those on items `actor` owns."
  def pending(h, actor) do
    for {id, p} <- Enum.sort(h.proposals),
        item = h.items[p.item_id],
        view = pending_view(item, p, actor) do
      Map.merge(
        %{id: id, item_id: p.item_id, change: p.change, consents: Enum.sort(p.consents)},
        view
      )
    end
  end

  # Owners see every proposal on their items. A member being added to a value sees the proposal,
  # with the value's attributes, only once every current owner has consented (REQ-115).
  defp pending_view(item, p, actor) do
    cond do
      actor in item.owners ->
        %{}

      actor in joiners(item, p) and MapSet.subset?(item.owners, p.consents) ->
        %{attrs: item.attrs}

      true ->
        nil
    end
  end

  defp may_consent(h, actor, p) do
    item = h.items[p.item_id]
    if pending_view(item, p, actor), do: :ok, else: {:error, :not_found}
  end

  # Members a proposal would add to a value item; they must consent too (REQ-115).
  defp joiners(item, %{change: {:owners, new_owners}}) do
    if Map.get(item.attrs, :kind) == :value,
      do: MapSet.difference(new_owners, item.owners),
      else: MapSet.new()
  end

  defp joiners(_item, _proposal), do: MapSet.new()

  # ---------------------------------------------------------------------------

  defp propose(h, actor, item_id, change) do
    id = h.next_proposal

    proposal = %{
      item_id: item_id,
      change: change,
      proposed_by: actor,
      consents: MapSet.new([actor])
    }

    h
    |> Map.update!(:proposals, &Map.put(&1, id, proposal))
    |> Map.put(:next_proposal, id + 1)
    |> apply_if_consented(id)
    |> then(&{:ok, &1, id})
  end

  defp apply_if_consented(h, proposal_id) do
    %{item_id: item_id, change: change, consents: consents} = proposal = h.proposals[proposal_id]
    item = h.items[item_id]
    required = MapSet.union(item.owners, joiners(item, proposal))

    if MapSet.subset?(required, consents) do
      h
      |> Map.update!(:proposals, &Map.delete(&1, proposal_id))
      # Record who actually consented, never assume it from the owner set (REQ-105).
      |> apply_change(item_id, change, MapSet.to_list(MapSet.intersection(consents, required)))
      |> drop_stale_proposals(item_id)
    else
      h
    end
  end

  defp apply_change(h, item_id, {:owners, new_owners}, consented_by) do
    h
    |> update_in([Access.key(:items), item_id], fn item ->
      # A member who becomes an owner no longer needs a grant.
      %{item | owners: new_owners, grantees: MapSet.difference(item.grantees, new_owners)}
    end)
    |> Ledger.record(item_id, consented_by, :owners_changed, %{owners: MapSet.to_list(new_owners)})
  end

  defp apply_change(h, item_id, {:grant, grantee}, consented_by) do
    h
    |> update_in([Access.key(:items), item_id, :grantees], &MapSet.put(&1, grantee))
    |> Ledger.record(item_id, consented_by, :granted, %{grantee: grantee})
  end

  # Proposals that no longer make sense after a change are dropped rather than left to apply later.
  defp drop_stale_proposals(h, item_id) do
    item = h.items[item_id]

    stale? = fn
      %{item_id: ^item_id, change: {:grant, g}} -> g in item.owners or g in item.grantees
      %{item_id: ^item_id, change: {:owners, o}} -> MapSet.equal?(o, item.owners)
      _ -> false
    end

    Map.update!(h, :proposals, &Map.reject(&1, fn {_, p} -> stale?.(p) end))
  end

  defp owned_item(h, actor, item_id) do
    case h.items[item_id] do
      # A non-owner cannot tell a missing item from an invisible one (REQ-102, ASM-014).
      %{owners: owners} = item -> if actor in owners, do: {:ok, item}, else: {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp fetch_proposal(h, id) do
    case h.proposals[id] do
      nil -> {:error, :not_found}
      p -> {:ok, p}
    end
  end

  defp valid_owner_set(h, owners) do
    cond do
      MapSet.size(owners) == 0 -> {:error, :no_owners}
      not MapSet.subset?(owners, h.members) -> {:error, :not_a_member}
      true -> :ok
    end
  end

  defp member?(h, m), do: m in h.members
  defp ok(h), do: {:ok, h}
end
