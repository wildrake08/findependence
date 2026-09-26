defmodule Findependence.Alignment do
  @moduledoc """
  CAP-003 value articulation and CAP-004 activity-value linking (sentinel 2, OUT-002).

  - MEC-008 values as owned items: REQ-111. A value is an ordinary item with `kind: :value`,
    so ownership, grants, exit, and the ledger (REQ-101..110) apply unchanged. There are no
    predefined values.
  - MEC-009 private member links: REQ-112, REQ-114. Links belong to the member who made them.
    No function returns another member's links.
  - MEC-010 visibility-scoped distribution: REQ-126 (superseding REQ-113), REQ-114. Per-month
    and one-off sums of money in and out, and counts, with no score, rank, threshold, or label
    (PRI-001).

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

  @frequencies [:one_off, :weekly, :biweekly, :monthly, :yearly]

  @doc "How often an item can happen (REQ-127). An item with none recorded counts as `:one_off`."
  def frequencies, do: @frequencies

  @doc "An item's frequency, `:one_off` when none (or an unknown one) is recorded."
  def frequency(%{attrs: attrs}) do
    f = Map.get(attrs, :frequency)
    if f in @frequencies, do: f, else: :one_off
  end

  @doc """
  A recurring amount as a per-month amount, rounded half away from zero to the smallest unit
  (REQ-126): weekly x 52/12, every two weeks x 26/12, monthly x 1, yearly / 12. `nil` for one-off.
  """
  def per_month(_amount, :one_off), do: nil
  def per_month(amount, :monthly), do: amount
  def per_month(amount, :weekly), do: round_div(amount * 52, 12)
  def per_month(amount, :biweekly), do: round_div(amount * 26, 12)
  def per_month(amount, :yearly), do: round_div(amount, 12)

  defp round_div(n, d) when n < 0, do: -round_div(-n, d)
  defp round_div(n, d), do: div(2 * n + d, 2 * d)

  @doc """
  The distribution of the member's visible activity across the values visible to them (REQ-126).

  Returns `%{by_value: %{value_id => bucket}, unlinked: bucket}`, where each bucket is
  `%{count: n, per_month: %{in: n, out: n}, one_off: %{in: n, out: n}}`. Recurring items are
  converted to per-month amounts one by one, then summed; one-off items are summed apart. `in`
  is the sum of positive amounts and `out` the sum of negative ones. An item linked to several
  values counts toward each, so buckets are not a partition. Nothing in the result evaluates,
  ranks, or labels.
  """
  def distribution(h, member, key \\ :amount) do
    visible = View.visible_items(h, member)
    {values, activity} = Enum.split_with(visible, &value?/1)
    links = links(h, member)

    by_value =
      Map.new(values, fn v ->
        linked = for a <- activity, {a.id, v.id} in links, do: a
        {v.id, bucket(linked, key)}
      end)

    linked_ids = MapSet.new(links, &elem(&1, 0))
    unlinked = for a <- activity, a.id not in linked_ids, do: a

    %{by_value: by_value, unlinked: bucket(unlinked, key)}
  end

  defp bucket(items, key) do
    empty = %{count: length(items), per_month: %{in: 0, out: 0}, one_off: %{in: 0, out: 0}}

    Enum.reduce(items, empty, fn item, acc ->
      case Map.get(item.attrs, key) do
        amount when is_integer(amount) and amount != 0 ->
          {part, value} =
            case frequency(item) do
              :one_off -> {:one_off, amount}
              f -> {:per_month, per_month(amount, f)}
            end

          side = if value > 0, do: :in, else: :out
          update_in(acc, [part, side], &(&1 + value))

        _ ->
          acc
      end
    end)
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
