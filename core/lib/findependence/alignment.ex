defmodule Findependence.Alignment do
  @moduledoc """
  CAP-003 value articulation and CAP-004 activity-value linking (sentinel 2, OUT-002).

  - MEC-008 values as owned items: REQ-111. A value is an ordinary item with `kind: :value`,
    so ownership, grants, exit, and the ledger (REQ-101..110) apply unchanged. There are no
    predefined values.
  - MEC-009 private member links: REQ-112, REQ-114. Links belong to the member who made them.
    No function returns another member's links.
  - MEC-010 visibility-scoped distribution: REQ-128 (superseding REQ-126 and REQ-113), REQ-114. Per-month
    and one-off sums of money in and out, and counts, with no score, rank, threshold, or label
    (PRI-001).

  A link whose item or value the member can no longer see is hidden, not deleted, and reappears
  if visibility is regained. Links to a deleted item are purged, so a reused id never inherits
  them (ASM-018).
  """

  alias Findependence.{Household, View}

  @doc "Records a value in the member's own words, as an item they own (REQ-111)."
  def add_value(h, actor, value_id, label) when is_binary(label) do
    label = String.trim(label)

    # REQ-157 (DEF-049): the rule a saved file is checked against: 1 to 200 characters
    if label == "" or String.length(label) > 200,
      do: {:error, :invalid_value},
      else: Household.add_item(h, actor, value_id, %{kind: :value, label: label})
  end

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

  # REQ-129 (CP-012): how often an item happens is one-off, irregular (the amount is the total for a
  # year), or an interval `{:every, n, unit}`. The presets the interface offers, in order:
  @frequencies [
    :one_off,
    {:every, 1, :week},
    {:every, 2, :week},
    {:every, 1, :month},
    {:every, 2, :month},
    {:every, 3, :month},
    {:every, 6, :month},
    {:every, 1, :year},
    :irregular
  ]

  # Values stored under REQ-127 read as the same intervals.
  @legacy %{
    weekly: {:every, 1, :week},
    biweekly: {:every, 2, :week},
    monthly: {:every, 1, :month},
    yearly: {:every, 1, :year}
  }

  @doc "The frequencies the interface offers (REQ-129), as stored."
  def frequencies, do: @frequencies

  @doc "Every atom a stored frequency can contain, for decoders that must know them in advance."
  def frequency_atoms,
    do: [:frequency, :one_off, :irregular, :every, :week, :month, :year | Map.keys(@legacy)]

  @doc """
  An item's frequency, normalized: `:one_off`, `:irregular`, or `{:every, n, unit}` with a positive
  whole `n` and `unit` one of `:week`, `:month`, `:year`. Legacy values read as their intervals; none,
  or anything unrecognized, reads as `:one_off` (REQ-128).
  """
  def frequency(%{attrs: attrs}), do: normalize(Map.get(attrs, :frequency))

  defp normalize(f) when f in [:one_off, :irregular], do: f

  defp normalize({:every, n, unit} = f)
       when is_integer(n) and n > 0 and unit in [:week, :month, :year], do: f

  defp normalize(f) when is_map_key(@legacy, f), do: @legacy[f]
  defp normalize(_), do: :one_off

  @doc """
  A recurring amount as a per-month amount, rounded half away from zero to the smallest unit
  (REQ-128): every N weeks x 52 / (12 N), every N months / N, every N years / (12 N), irregular
  (a yearly total) / 12. `nil` for one-off. Accepts legacy values too.
  """
  def per_month(amount, frequency) do
    case normalize(frequency) do
      :one_off -> nil
      :irregular -> round_div(amount, 12)
      {:every, n, :week} -> round_div(amount * 52, 12 * n)
      {:every, n, :month} -> round_div(amount, n)
      {:every, n, :year} -> round_div(amount, 12 * n)
    end
  end

  defp round_div(n, d) when n < 0, do: -round_div(-n, d)
  defp round_div(n, d), do: div(2 * n + d, 2 * d)

  @doc """
  The distribution of the member's visible activity across the values visible to them (REQ-128).

  Returns `%{by_value: %{value_id => bucket}, unlinked: bucket}`, where each bucket is
  `%{count: n, per_month: %{in: n, out: n}, one_off: %{in: n, out: n}}`. Recurring items are
  converted to per-month amounts one by one, then summed; one-off items are summed apart. `in`
  is the sum of positive amounts and `out` the sum of negative ones. An item linked to several
  values counts toward each, so buckets are not a partition. Nothing in the result evaluates,
  ranks, or labels.
  """
  def distribution(h, member, key \\ :amount) do
    visible = View.visible_items(h, member)
    # REQ-134: accounts and debts are not money in or out
    {values, activity} =
      visible
      |> Enum.reject(&(Findependence.Balances.balance?(&1) or Findependence.Plans.plan?(&1)))
      |> Enum.split_with(&value?/1)

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

      Findependence.Balances.balance?(item) ->
        {:error, :cannot_link_a_balance}

      Findependence.Plans.plan?(item) or Findependence.Plans.plan?(value) ->
        {:error, :cannot_link_a_plan}

      true ->
        :ok
    end
  end

  defp own(h, member), do: Map.get(h.links, member, MapSet.new())
  defp put_links(h, member, fun), do: %{h | links: Map.put(h.links, member, fun.(own(h, member)))}
end
