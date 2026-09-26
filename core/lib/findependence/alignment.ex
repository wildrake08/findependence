defmodule Findependence.Alignment do
  @moduledoc """
  CAP-003 value articulation and CAP-004 activity-value linking (sentinel 2, OUT-002).

  - MEC-008 values as owned items: REQ-111. A value is an ordinary item with `kind: :value`,
    so ownership, grants, exit, and the ledger (REQ-101..110) apply unchanged. There are no
    predefined values.
  - MEC-009 private member links: REQ-112, REQ-114. Links belong to the member who made them.
    No function returns another member's links.
  - MEC-010 visibility-scoped distribution: REQ-113, REQ-114. Sums and counts only, with no
    score, rank, threshold, or label (PRI-001).

  A link whose item or value the member can no longer see is hidden, not deleted, and reappears
  if visibility is regained. Links to a deleted item are purged, so a reused id never inherits
  them (ASM-018).
  """

  alias Findependence.{Household, View}

  @doc "Records a value in the member's own words, as an item they own (REQ-111)."
  def add_value(h, actor, value_id, label) when is_binary(label),
    do: Household.add_item(h, actor, value_id, %{kind: :value, label: label})

  @doc "True if the item is a value."
  def value?(%{attrs: attrs}), do: Map.get(attrs, :kind) == :value

  @doc """
  Links an item the member can see to a value the member can see (REQ-112). Anything invisible
  is reported as `:not_found`, exactly like a missing item.
  """
  def link(h, member, item_id, value_id) do
    with :ok <- linkable(h, member, item_id, value_id) do
      if MapSet.member?(own(h, member), {item_id, value_id}),
        do: {:error, :already_linked},
        else: {:ok, put_links(h, member, &MapSet.put(&1, {item_id, value_id}))}
    end
  end

  @doc "Removes one of the member's own links."
  def unlink(h, member, item_id, value_id) do
    if {item_id, value_id} in links(h, member),
      do: {:ok, put_links(h, member, &MapSet.delete(&1, {item_id, value_id}))},
      else: {:error, :not_found}
  end

  @doc "The member's own links whose item and value are both currently visible to them (REQ-112, REQ-114)."
  def links(h, member) do
    for {i, v} = link <- own(h, member),
        View.visible?(h, member, i) and View.visible?(h, member, v),
        do: link
  end

  @doc """
  The distribution of the member's visible activity across the values visible to them (REQ-113).

  Returns `%{by_value: %{value_id => %{sum: n, count: n}}, unlinked: %{sum: n, count: n}}`.
  An item linked to several values counts toward each, so per-value sums are not a partition.
  Nothing in the result evaluates, ranks, or labels.
  """
  def distribution(h, member, key \\ :amount) do
    visible = View.visible_items(h, member)
    {values, activity} = Enum.split_with(visible, &value?/1)
    links = links(h, member)
    amount = fn item -> Map.get(item.attrs, key, 0) end

    by_value =
      Map.new(values, fn v ->
        linked = for a <- activity, {a.id, v.id} in links, do: amount.(a)
        {v.id, %{sum: Enum.sum(linked), count: length(linked)}}
      end)

    linked_ids = MapSet.new(links, &elem(&1, 0))
    unlinked = for a <- activity, a.id not in linked_ids, do: amount.(a)

    %{by_value: by_value, unlinked: %{sum: Enum.sum(unlinked), count: length(unlinked)}}
  end

  @doc false
  # Called when an item is deleted, so a reused id never inherits old links (ASM-018).
  def purge_item(h, item_id) do
    links =
      Map.new(h.links, fn {m, set} ->
        {m, MapSet.reject(set, fn {i, v} -> i == item_id or v == item_id end)}
      end)

    %{h | links: links}
  end

  @doc false
  def drop_member(h, member), do: %{h | links: Map.delete(h.links, member)}

  defp linkable(h, member, item_id, value_id) do
    item = h.items[item_id]
    value = h.items[value_id]

    cond do
      not View.visible?(h, member, item_id) or not View.visible?(h, member, value_id) ->
        {:error, :not_found}

      not value?(value) ->
        {:error, :not_a_value}

      value?(item) ->
        {:error, :cannot_link_a_value}

      true ->
        :ok
    end
  end

  defp own(h, member), do: Map.get(h.links, member, MapSet.new())
  defp put_links(h, member, fun), do: %{h | links: Map.put(h.links, member, fun.(own(h, member)))}
end
