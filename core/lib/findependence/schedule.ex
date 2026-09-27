defmodule Findependence.Schedule do
  @moduledoc """
  CAP-011 dated cash flow (MEC-018).

  An item may carry one date on which it happens (`attrs.on`, an ISO 8601 string; REQ-136). Its
  other dates are computed from that date and its interval (REQ-137), so nothing needs editing as
  time passes. The running balance starts from the sum of the latest readings of the member's
  visible checking accounts and applies every dated occurrence after the most recent of those
  readings' dates (REQ-138, REQ-139). Everything is computed over what the member can see.
  """

  alias Findependence.{Alignment, Balances, View}

  @doc "The item's date, or nil when it has none or an invalid one."
  def date(%{attrs: attrs}) do
    with on when is_binary(on) <- Map.get(attrs, :on),
         {:ok, d} <- Date.from_iso8601(on) do
      d
    else
      _ -> nil
    end
  end

  @doc """
  The dates on which `item` happens between `from` and `to`, inclusive (REQ-137): never before its
  own date; every 7N days for every N weeks; the same day of the month, or the month's last day,
  for every N months or years; its date once for a one-off; none for irregular items.
  """
  def occurrences(item, %Date{} = from, %Date{} = to) do
    case {date(item), Alignment.frequency(item)} do
      {nil, _} -> []
      {_, :irregular} -> []
      {d, :one_off} -> if in_range?(d, from, to), do: [d], else: []
      {d, {:every, n, :week}} -> stepped(d, from, to, fn k -> Date.add(d, 7 * n * k) end)
      {d, {:every, n, :month}} -> stepped(d, from, to, fn k -> add_months(d, n * k) end)
      {d, {:every, n, :year}} -> stepped(d, from, to, fn k -> add_months(d, 12 * n * k) end)
    end
  end

  defp in_range?(d, from, to), do: Date.compare(d, from) != :lt and Date.compare(d, to) != :gt

  # k = 0, 1, 2, ... until past `to`; keeps those on or after `from`
  defp stepped(anchor, from, to, at) do
    if Date.compare(anchor, to) == :gt do
      []
    else
      Stream.iterate(0, &(&1 + 1))
      |> Stream.map(at)
      |> Enum.take_while(&(Date.compare(&1, to) != :gt))
      |> Enum.filter(&(Date.compare(&1, from) != :lt))
    end
  end

  @doc "`date` plus `months` months, on the same day of the month or the month's last day."
  def add_months(%Date{year: y, month: m, day: d}, months) do
    total = y * 12 + (m - 1) + months
    {year, month} = {div(total, 12), rem(total, 12) + 1}
    Date.new!(year, month, min(d, Date.days_in_month(Date.new!(year, month, 1))))
  end

  @doc """
  Day-by-day cash flow for `member` from `from` for `days` days (REQ-138, REQ-139).

  Returns `%{start: start, days: [%{date, entries: [{item, amount}], balance}]}`. `start` is nil
  when the member can see no checking account with a reading; then `balance` is nil on every day.
  Otherwise it is `%{balance, on, accounts}`: the sum of the latest readings, the most recent of
  their dates, and the accounts' ids, and each day's balance applies every dated occurrence after
  `on`, including days before `from`.
  """
  def cash_flow(h, member, %Date{} = from, days) when days > 0 do
    to = Date.add(from, days - 1)
    visible = View.visible_items(h, member)
    activity = Enum.reject(visible, &(Balances.balance?(&1) or Alignment.value?(&1)))

    checking =
      for i <- visible,
          i.attrs[:kind] == :account,
          i.attrs[:account_type] == :checking,
          r = Balances.latest(h, member, i.id),
          do: {i, r}

    start =
      case checking do
        [] ->
          nil

        list ->
          on = list |> Enum.map(fn {_, r} -> Date.from_iso8601!(r.on) end) |> Enum.max(Date)

          %{
            balance: Enum.sum(Enum.map(list, fn {_, r} -> r.balance end)),
            on: on,
            accounts: list |> Enum.map(fn {i, _} -> i.id end) |> Enum.sort()
          }
      end

    flows_from = if start, do: Enum.min([Date.add(start.on, 1), from], Date), else: from

    by_day =
      for item <- activity,
          is_integer(item.attrs[:amount]),
          d <- occurrences(item, flows_from, to),
          reduce: %{} do
        acc ->
          Map.update(acc, d, [{item, item.attrs[:amount]}], &[{item, item.attrs[:amount]} | &1])
      end

    before =
      if start,
        do:
          by_day
          |> Enum.filter(fn {d, _} ->
            Date.compare(d, from) == :lt and Date.compare(d, start.on) == :gt
          end)
          |> Enum.flat_map(&elem(&1, 1))
          |> Enum.map(&elem(&1, 1))
          |> Enum.sum(),
        else: 0

    {rows, _} =
      Enum.map_reduce(0..(days - 1), start && start.balance + before, fn k, bal ->
        d = Date.add(from, k)
        entries = by_day |> Map.get(d, []) |> Enum.sort_by(fn {i, a} -> {a, title(i)} end)
        # the reading already reflects anything on or before its own date
        applies? = start != nil and Date.compare(d, start.on) == :gt
        bal = if applies?, do: bal + Enum.sum(Enum.map(entries, &elem(&1, 1))), else: bal
        {%{date: d, entries: entries, balance: bal}, bal}
      end)

    %{start: start, days: rows}
  end

  @doc """
  Money-out items the member can see that happen less often than monthly, with what setting aside
  each month would take to cover them (REQ-140): `%{total: cents, items: [{item, cents}]}`, in
  positive cents, largest first.
  """
  def set_asides(h, member) do
    items =
      for i <- View.visible_items(h, member),
          not Balances.balance?(i) and not Alignment.value?(i),
          a = i.attrs[:amount],
          is_integer(a) and a < 0,
          lumpy?(Alignment.frequency(i)) do
        {i, -Alignment.per_month(a, Alignment.frequency(i))}
      end
      |> Enum.sort_by(fn {i, c} -> {-c, title(i)} end)

    %{total: items |> Enum.map(&elem(&1, 1)) |> Enum.sum(), items: items}
  end

  # Less often than monthly: every 2+ months, any number of years, irregular, every 5+ weeks.
  defp lumpy?(:irregular), do: true
  defp lumpy?({:every, n, :month}), do: n >= 2
  defp lumpy?({:every, _n, :year}), do: true
  defp lumpy?({:every, n, :week}), do: n >= 5
  defp lumpy?(_), do: false

  defp title(i), do: i.attrs[:note] || i.attrs[:label] || ""
end
