defmodule Findependence.Exit do
  @moduledoc """
  CAP-002 independent exit: a member can take their record and leave without anyone else's
  cooperation.

  - MEC-005 sole-owner deletion: REQ-108
  - MEC-006 owner-scoped export: REQ-109
  - MEC-007 unilateral departure: REQ-110

  Leaving jointly owned items is `Findependence.Household.relinquish/3` (REQ-107), and
  transferring a solely owned item is `Findependence.Household.propose_owners/4`, which applies
  at once because the sole owner's consent is the only one needed.
  """

  alias Findependence.{Alignment, Household, Ledger}

  @doc """
  Deletes an item its `actor` solely owns (REQ-108). The item, its grants, its pending proposals,
  and its ledger are removed. Only a record of the item id and a per-deleter sequence number is
  kept, readable by the deleter through `Findependence.Ledger.deletions/2`. Grantees are not
  notified (ASM-016).
  """
  def delete(%Household{} = h, actor, item_id) do
    case h.items[item_id] do
      %{owners: owners} ->
        cond do
          actor not in owners -> {:error, :not_found}
          MapSet.size(owners) > 1 -> {:error, :not_sole_owner}
          true -> {:ok, remove_item(h, actor, item_id)}
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Everything `actor` currently owns, with each item's ledger, as plain data (REQ-109). It
  contains nothing the member does not own, not even items shared with them by grant.
  """
  def export(%Household{} = h, actor) do
    items =
      for {id, item} <- Enum.sort_by(h.items, &elem(&1, 0)), actor in item.owners do
        %{
          id: id,
          attrs: item.attrs,
          owners: Enum.sort(MapSet.to_list(item.owners)),
          grantees: Enum.sort(MapSet.to_list(item.grantees)),
          ledger: h.ledger[id]
        }
      end

    %{member: actor, items: items}
  end

  @doc """
  Removes `actor` from the household (REQ-110) once they own nothing. Every grant they hold is
  removed and recorded in that item's ledger, and every pending proposal that would grant to them
  or make them an owner is dropped. A member who still owns items is refused: relinquish,
  transfer, or delete first.
  """
  def leave(%Household{} = h, actor) do
    cond do
      actor not in h.members ->
        {:error, :not_a_member}

      Enum.any?(h.items, fn {_, item} -> actor in item.owners end) ->
        {:error, :still_owner}

      true ->
        h =
          for {id, item} <- h.items, actor in item.grantees, reduce: h do
            acc ->
              acc
              |> update_in([Access.key(:items), id, :grantees], &MapSet.delete(&1, actor))
              |> Ledger.record(id, actor, :grantee_departed, %{grantee: actor})
          end

        h
        |> Household.drop_proposals(&names?(&1.change, actor))
        |> Alignment.drop_member(actor)
        |> Map.update!(:members, &MapSet.delete(&1, actor))
        |> then(&{:ok, &1})
    end
  end

  defp names?({:grant, grantee}, actor), do: grantee == actor
  defp names?({:owners, owners}, actor), do: actor in owners

  defp remove_item(h, actor, item_id) do
    records = Map.get(h.deletions, actor, [])
    record = %{seq: length(records) + 1, item_id: item_id}

    %{
      h
      | items: Map.delete(h.items, item_id),
        ledger: Map.delete(h.ledger, item_id),
        deletions: Map.put(h.deletions, actor, records ++ [record])
    }
    |> Household.drop_proposals(&(&1.item_id == item_id))
    |> Alignment.purge_item(item_id)
  end
end
