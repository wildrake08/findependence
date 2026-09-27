defmodule Findependence.Projection do
  @moduledoc """
  CAP-007 and CAP-013 calculations (MEC-019). Everything is computed on request from what the
  member owns and can see; nothing here is stored, and no result is scored, ranked, or labelled.

  - `project/4`: the next twelve months, as things are or with a plan (REQ-141, REQ-143, REQ-144).
  - `payoff/3`: months and interest to clear a debt at a payment (REQ-145).
  - `cover/2` and `set_asides/2`: how long savings would last, and goal set-asides (REQ-146/147).
  """

  alias Findependence.{Alignment, Balances, Plans, View}

  @doc "The twelve months after `today`'s month, as \"YYYY-MM\"."
  def months(%Date{} = today) do
    first = Findependence.Schedule.add_months(%{today | day: 1}, 1)
    for k <- 0..11, do: first |> Findependence.Schedule.add_months(k) |> key()
  end

  defp key(%Date{year: y, month: m}),
    do: "#{y}-#{String.pad_leading(Integer.to_string(m), 2, "0")}"

  @doc """
  The next twelve months for `member` (REQ-141), or with `plan` applied (REQ-143):

  `%{start: %{cash, on, accounts} | nil, months: [%{month, in, out, net, cash}], debts: [debt]}`,
  where each debt is `%{id, name, balance, months: [balance], interest, paid_off}` (`paid_off` is a
  month, or nil when it isn't paid off within twelve months). Planned borrowing appears as debts
  with `planned: true`. `cash` is nil when the member can see no account with a balance.
  """
  def project(h, member, %Date{} = today, plan \\ nil) do
    ms = months(today)
    visible = View.visible_items(h, member)
    owned = Enum.filter(visible, &(member in &1.owners and Plans.money?(&1)))
    steps = if plan, do: Enum.map(plan.steps, & &1.step), else: []
    off = switched_off(steps, Plans.depends(h, member))

    accounts =
      for i <- visible,
          i.attrs[:kind] == :account,
          r = Balances.latest(h, member, i.id),
          do: {i, r}

    start =
      if accounts == [],
        do: nil,
        else: %{
          cash: accounts |> Enum.map(fn {_, r} -> r.balance end) |> Enum.sum(),
          on: accounts |> Enum.map(fn {_, r} -> r.on end) |> Enum.max(),
          accounts: accounts |> Enum.map(fn {i, _} -> i.id end) |> Enum.sort()
        }

    added = for {:add, attrs, from} <- steps, do: {%{attrs: attrs}, from}
    borrowed = for {:borrow, b, from} <- steps, do: {b, from}

    plan_debts =
      for {b, from} <- borrowed do
        run_debt(b.amount, b.rate_bp, b.payment, ms, from)
        |> Map.merge(%{
          id: nil,
          name: "Planned borrowing",
          planned: true,
          from: from,
          amount: b.amount
        })
      end

    {rows, _} =
      Enum.map_reduce(Enum.with_index(ms), start && start.cash, fn {mo, k}, cash ->
        real =
          for i <- owned, not off?(off, i.id, mo), a = monthly(i, mo), a != 0, do: a

        planned = for {i, from} <- added, mo >= from, a = monthly(i, mo), a != 0, do: a

        borrowing =
          for d <- plan_debts do
            if(d.from == mo, do: d.amount, else: 0) - Enum.at(d.payments, k)
          end

        flows = real ++ planned ++ borrowing
        inn = flows |> Enum.filter(&(&1 > 0)) |> Enum.sum()
        out = flows |> Enum.filter(&(&1 < 0)) |> Enum.sum()
        cash = cash && cash + inn + out
        {%{month: mo, in: inn, out: out, net: inn + out, cash: cash}, cash}
      end)

    debts =
      for i <- visible, i.attrs[:kind] == :debt, r = Balances.latest(h, member, i.id) do
        run_debt(r.balance, r.rate_bp, r.min_payment, ms, nil)
        |> Map.merge(%{id: i.id, name: i.attrs[:label], planned: false})
      end
      |> Enum.sort_by(& &1.name)

    %{start: start, months: rows, debts: debts ++ plan_debts}
  end

  # item id => the earliest month it is switched off from; a switched-off job takes the items
  # marked as depending on it with it (REQ-144)
  defp switched_off(steps, marks) do
    direct = for {:switch_off, ids, from} <- steps, id <- ids, do: {id, from}
    dependents = for {id, from} <- direct, {i, ^id} <- marks, do: {i, from}

    Enum.reduce(direct ++ dependents, %{}, fn {id, from}, acc ->
      Map.update(acc, id, from, &min(&1, from))
    end)
  end

  defp off?(off, id, mo), do: (from = off[id]) != nil and mo >= from

  # An item's amount in month `mo`: repeating items at their per-month amount; a dated one-off in
  # its own month; an undated one-off not at all (REQ-141).
  defp monthly(%{attrs: attrs} = i, mo) do
    case {attrs[:amount], Alignment.frequency(i)} do
      {a, :one_off} when is_integer(a) ->
        case Findependence.Schedule.date(i) do
          %Date{} = d -> if key(d) == mo, do: a, else: 0
          nil -> 0
        end

      {a, f} when is_integer(a) ->
        Alignment.per_month(a, f)

      _ ->
        0
    end
  end

  # A debt month by month: interest added, then the payment (never more than is owed). Borrowing
  # starts in `from` (no payment that month); an existing debt starts now.
  defp run_debt(balance, rate_bp, payment, ms, from) do
    {bals, {_, interest, paid_off, payments}} =
      Enum.map_reduce(ms, {nil, 0, nil, []}, fn mo, {bal, int, paid, pays} ->
        cond do
          from != nil and mo < from ->
            {0, {nil, int, paid, pays ++ [0]}}

          from != nil and mo == from ->
            {balance, {balance, int, paid, pays ++ [0]}}

          true ->
            bal = bal || balance

            i =
              if bal > 0,
                do: Balances.monthly_interest(%{balance: bal, rate_bp: rate_bp}),
                else: 0

            pay = min(payment, bal + i)
            bal = bal + i - pay
            paid = paid || if(bal == 0 and pay > 0, do: mo, else: nil)
            {bal, {bal, int + i, paid, pays ++ [pay]}}
        end
      end)

    %{balance: balance, months: bals, interest: interest, paid_off: paid_off, payments: payments}
  end

  @doc """
  Months to clear `balance` paying `payment` a month at `rate_bp`, and the interest paid meanwhile
  (REQ-145): `{:ok, months, interest}`, or `:never` when the payment doesn't cover a month's interest.
  Checked up to 100 years.
  """
  def payoff(balance, rate_bp, payment) when balance >= 0 and payment > 0 do
    first = Balances.monthly_interest(%{balance: balance, rate_bp: rate_bp})

    cond do
      balance == 0 -> {:ok, 0, 0}
      payment <= first -> :never
      true -> clear(balance, rate_bp, payment)
    end
  end

  # Month by month: interest added, then the payment (never more than is owed).
  defp clear(balance, rate_bp, payment) do
    Enum.reduce_while(1..1200, {balance, 0}, fn k, {bal, int} ->
      i = Balances.monthly_interest(%{balance: bal, rate_bp: rate_bp})
      bal = bal + i - min(payment, bal + i)
      if bal == 0, do: {:halt, {:ok, k, int + i}}, else: {:cont, {bal, int + i}}
    end)
    |> case do
      {:ok, _, _} = done -> done
      _ -> :never
    end
  end

  @doc """
  How long the savings accounts `member` can see would cover the money out of the items they own
  (REQ-146): `%{savings, monthly_out, months, goal, accounts}`; `months` is a float with one decimal,
  or nil with no money out or no savings reading.
  """
  def cover(h, member) do
    visible = View.visible_items(h, member)

    savings =
      for i <- visible,
          i.attrs[:kind] == :account,
          i.attrs[:account_type] == :savings,
          r = Balances.latest(h, member, i.id),
          do: {i.id, r.balance}

    out =
      for i <- visible,
          member in i.owners and Plans.money?(i),
          a = i.attrs[:amount],
          is_integer(a) and a < 0,
          (f = Alignment.frequency(i)) != :one_off,
          do: -Alignment.per_month(a, f)

    total_savings = savings |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    monthly_out = Enum.sum(out)

    months =
      if savings != [] and monthly_out > 0,
        do: Float.round(total_savings / monthly_out, 1),
        else: nil

    %{
      savings: total_savings,
      monthly_out: monthly_out,
      months: months,
      goal: Plans.goals(h, member).fund_months,
      accounts: savings |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    }
  end

  @doc """
  For each set-aside goal, the monthly money in linked (by the member's own links) to its value and
  what the rate sets aside (REQ-147): `[%{value_id, rate_bp, monthly_in, set_aside}]`.
  """
  def set_asides(h, member) do
    links = Alignment.links(h, member)

    for {v, bp} <- Plans.goals(h, member).set_aside, View.visible?(h, member, v) do
      monthly_in =
        for {i, ^v} <- links,
            item = h.items[i],
            a = item.attrs[:amount],
            is_integer(a) and a > 0,
            (f = Alignment.frequency(item)) != :one_off,
            reduce: 0 do
          acc -> acc + Alignment.per_month(a, f)
        end

      %{
        value_id: v,
        rate_bp: bp,
        monthly_in: monthly_in,
        set_aside: div(monthly_in * bp + 5_000, 10_000)
      }
    end
    |> Enum.sort_by(& &1.value_id)
  end
end
