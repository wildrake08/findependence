defmodule Findependence.View do
  @moduledoc """
  MEC-002, read side: deny-by-default visibility.

  - REQ-102: a member can read an item if and only if they own it or hold a grant for it.
  - REQ-106: every aggregate is computed only over the items visible to the requesting member,
    so totals never carry information from items the member cannot see.

  Every read goes through `visible_items/2`.
  """

  @doc "True if `member` may read the item. Missing and invisible items are indistinguishable."
  def visible?(h, member, item_id) do
    case h.items[item_id] do
      %{owners: o, grantees: g} -> member in o or member in g
      nil -> false
    end
  end

  @doc "The items visible to `member`, as read-only views."
  def visible_items(h, member) do
    for {id, _} <- h.items, visible?(h, member, id), do: view(h.items[id], member)
  end

  @doc "One item, or `{:error, :not_found}` whether it is missing or merely invisible."
  def get(h, member, item_id) do
    if visible?(h, member, item_id),
      do: {:ok, view(h.items[item_id], member)},
      else: {:error, :not_found}
  end

  @doc """
  Folds `fun` over the items visible to `member` (REQ-106). This is the only aggregation
  entry point.
  """
  def reduce(h, member, acc, fun), do: Enum.reduce(visible_items(h, member), acc, fun)

  @doc "Sums a numeric attribute over the items visible to `member`; items without it count as 0."
  def sum(h, member, key),
    do: reduce(h, member, 0, fn item, acc -> acc + Map.get(item.attrs, key, 0) end)

  # Owners see who else has access. A grantee sees the item and its owners, but not other grantees (ASM-014).
  defp view(item, member) do
    base = %{id: item.id, attrs: item.attrs, owners: Enum.sort(MapSet.to_list(item.owners))}

    if member in item.owners,
      do: Map.put(base, :grantees, Enum.sort(MapSet.to_list(item.grantees))),
      else: base
  end
end
