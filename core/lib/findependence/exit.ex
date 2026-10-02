defmodule Findependence.Exit do
  @moduledoc """
  CAP-002 independent exit: a member can take their record and leave without anyone else's
  cooperation.

  - MEC-005 sole-owner deletion: REQ-108
  - MEC-012 owner-scoped export with own links (supersedes MEC-006): REQ-117
  - MEC-007 unilateral departure: REQ-110

  Leaving jointly owned items is `Findependence.Household.relinquish/3` (REQ-107), and
  transferring a solely owned item is `Findependence.Household.propose_owners/4`, which applies
  at once because the sole owner's consent is the only one needed.
  """

  alias Findependence.{Alignment, Household, Ledger, Plans, Retirement}

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
          # REQ-201 (CP-030 A): with the cooling-off on, the deletion waits, and the owner can cancel it
          h.cooling > 0 -> Household.propose_delete(h, actor, item_id)
          true -> {:ok, remove_item(h, actor, item_id)}
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Everything `actor` currently owns, with each item's ledger, plus their own links between items
  and values they both own, as plain data (REQ-117). It contains nothing the member does not own:
  not items shared with them by grant, and not links that touch such items.
  """
  def export(%Household{} = h, actor) do
    items =
      for {id, item} <- Enum.sort_by(h.items, &elem(&1, 0)), actor in item.owners do
        %{
          id: id,
          attrs: item.attrs,
          owners: Enum.sort(MapSet.to_list(item.owners)),
          grantees: Enum.sort(MapSet.to_list(item.grantees)),
          ledger: h.ledger[id],
          # REQ-131: an owner's own readings of their accounts and debts go with them
          readings: Map.get(h.readings, id, [])
        }
      end

    owned = MapSet.new(items, & &1.id)

    # REQ-117: only links whose item and value the member both owns; a link to someone else's
    # item would carry information about it out of the household (PRI-002).
    links =
      for {i, v} = link <- Enum.sort(Map.get(h.links, actor, MapSet.new())),
          i in owned and v in owned,
          do: link

    %{member: actor, items: items, links: links}
    |> Map.merge(personal(h, actor, owned))
  end

  # REQ-155: the member's own plans, marks, goals, and retirement assumptions, keeping only
  # references to entries the export contains.
  defp personal(h, actor, owned) do
    plans =
      for {id, p} <- Enum.sort_by(Plans.plans(h, actor), &elem(&1, 0)) do
        steps =
          for %{step: step} <- p.steps,
              step = keep_owned(step, owned),
              step != nil,
              do: step

        %{id: id, name: p.name, steps: steps}
      end

    marks = for {i, j} <- Plans.depends(h, actor), i in owned and j in owned, do: {i, j}
    g = Plans.goals(h, actor)
    r = Retirement.settings(h, actor)

    # REQ-164: which account an item goes through, where the member owns both
    attached =
      for {i, a} <- Findependence.Attach.attached(h, actor), i in owned and a in owned, do: {i, a}

    %{
      plans: plans,
      marks: Enum.sort(marks),
      attached: Enum.sort(attached),
      goals: %{
        fund_months: g.fund_months,
        set_aside: g.set_aside |> Enum.filter(fn {v, _} -> v in owned end) |> Enum.sort()
      },
      retirement: %{
        r
        | contributions:
            r.contributions |> Enum.filter(fn {a, _} -> a in owned end) |> Enum.sort()
      }
    }
  end

  defp keep_owned({:switch_off, ids, from}, owned) do
    case Enum.filter(ids, &(&1 in owned)) do
      [] -> nil
      kept -> {:switch_off, kept, from}
    end
  end

  defp keep_owned(step, _owned), do: step

  @doc """
  Removes `actor` from the household (REQ-110) once they own nothing. Every grant they hold is
  removed and recorded in that item's ledger, and every pending proposal that would grant to them,
  make them an owner, or that they made is dropped. Their agreement to anyone else's pending
  proposal is withdrawn, so nothing waiting on others still names them (WI-079: a leftover
  agreement kept a member who owned nothing from leaving the hosted form). A member who still owns
  items is refused: relinquish, transfer, or delete first.
  """
  def leave(%Household{} = h, actor) do
    cond do
      actor not in h.members ->
        {:error, :not_a_member}

      # REQ-201: leaving is never delayed; a deletion the member has scheduled takes effect as they leave
      (h2 = delete_scheduled(h, actor)) != h ->
        leave(h2, actor)

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
        |> Household.drop_proposals(
          &(names?(&1.change, actor) or Map.get(&1, :proposed_by) == actor)
        )
        |> Map.update!(:proposals, fn ps ->
          Map.new(ps, fn {n, p} -> {n, %{p | consents: MapSet.delete(p.consents, actor)}} end)
        end)
        |> Alignment.drop_member(actor)
        |> then(
          &%{
            &1
            | plans: Map.delete(&1.plans, actor),
              depends: Map.delete(&1.depends, actor),
              goals: Map.delete(&1.goals, actor)
          }
        )
        |> Map.update!(:members, &MapSet.delete(&1, actor))
        |> then(&{:ok, &1})
    end
  end

  defp names?({:grant, grantee}, actor), do: grantee == actor
  defp names?({:owners, owners}, actor), do: actor in owners
  defp names?(:delete, _actor), do: false

  defp delete_scheduled(h, actor) do
    for {_, %{change: :delete, proposed_by: ^actor, item_id: id}} <- Enum.sort(h.proposals),
        match?(%{owners: _}, h.items[id]),
        reduce: h do
      acc -> remove_item(acc, actor, id)
    end
  end

  @doc false
  def remove_item(h, actor, item_id) do
    records = Map.get(h.deletions, actor, [])
    record = %{seq: length(records) + 1, item_id: item_id}

    %{
      h
      | items: Map.delete(h.items, item_id),
        ledger: Map.delete(h.ledger, item_id),
        readings: Map.delete(h.readings, item_id),
        deletions: Map.put(h.deletions, actor, records ++ [record])
    }
    |> Household.drop_proposals(&(&1.item_id == item_id))
    |> Alignment.purge_item(item_id)
    |> Findependence.Plans.purge_item(item_id)
  end
end
