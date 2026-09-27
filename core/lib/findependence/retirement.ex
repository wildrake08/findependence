defmodule Findependence.Retirement do
  @moduledoc """
  CAP-012 retirement projection (MEC-021).

  Retirement accounts are accounts of kind 401(k) or IRA (`Balances.retirement?/1`), never cash
  (REQ-149). Each member's assumptions live with their goals in their own private record
  (REQ-150): birth year, retirement age, a yearly return after inflation in basis points, a monthly
  contribution to each retirement account they can see, a monthly Social Security estimate, and a
  target monthly income, all in cents of today's dollars. Nothing is filled in or suggested.

  `project/4` works month by month to January of the year the member reaches their retirement
  age (REQ-151), then how long the balance would last paying the difference between the target
  and the Social Security estimate (REQ-152). `sensitivity/3` repeats it with the return two points
  lower and higher and retirement two years earlier and later (REQ-153). Nothing is stored.
  """

  alias Findependence.{Balances, Plans, View}

  @fields [:birth_year, :retire_age, :return_bp, :ss_monthly, :target_monthly]
  @horizon_age 100

  @doc "Every atom the assumptions can contain, for decoders that must know them in advance."
  def format_atoms, do: [:retirement, :contributions | @fields]

  @doc "The member's assumptions, with nil for anything not set."
  def settings(h, m) do
    base = Map.new(@fields, &{&1, nil}) |> Map.put(:contributions, %{})
    Map.merge(base, Map.get(Plans.goals(h, m), :retirement, %{}))
  end

  @doc """
  Sets (or clears, with nil) one assumption (REQ-150). Refuses a value out of range with
  `{:error, :invalid_retirement}`.
  """
  def set(h, m, field, value) when field in @fields do
    if value == nil or valid_value?(field, value),
      do: {:ok, put(h, m, Map.put(settings(h, m), field, value))},
      else: {:error, :invalid_retirement}
  end

  def set(_h, _m, _field, _value), do: {:error, :invalid_retirement}

  @doc "True if `value` is allowed for the assumption `field` (REQ-150); nil is checked separately."
  def valid?(field, value) when field in @fields, do: valid_value?(field, value)
  def valid?(_field, _value), do: false

  defp valid_value?(:birth_year, y), do: is_integer(y) and y in 1900..2100
  defp valid_value?(:retire_age, a), do: is_integer(a) and a in 40..90
  defp valid_value?(:return_bp, bp), do: is_integer(bp) and bp in -500..1_500
  defp valid_value?(_money, c), do: is_integer(c) and c >= 0 and c <= 100_000_000

  @doc "Sets (or clears, with nil) the member's monthly contribution to a retirement account they can see."
  def set_contribution(h, m, account_id, cents) do
    a = h.items[account_id]

    cond do
      a == nil or not View.visible?(h, m, account_id) or not Balances.retirement?(a) ->
        {:error, :not_found}

      cents == nil ->
        s = settings(h, m)
        {:ok, put(h, m, %{s | contributions: Map.delete(s.contributions, account_id)})}

      valid_value?(:contribution, cents) and cents > 0 ->
        s = settings(h, m)
        {:ok, put(h, m, %{s | contributions: Map.put(s.contributions, account_id, cents)})}

      true ->
        {:error, :invalid_retirement}
    end
  end

  @doc "Removes every member's contribution to a deleted account (REQ-150)."
  def purge_item(h, id) do
    goals =
      Map.new(h.goals, fn
        {m, %{retirement: r} = g} ->
          {m, %{g | retirement: Map.update(r, :contributions, %{}, &Map.delete(&1, id))}}

        other ->
          other
      end)

    %{h | goals: goals}
  end

  defp put(h, m, s) do
    g = Map.put(Map.get(h.goals, m, %{}), :retirement, s)
    %{h | goals: Map.put(h.goals, m, g)}
  end

  @doc """
  The projection (REQ-151, REQ-152), with `overrides` replacing assumptions for this calculation
  only. `{:missing, fields}` when a birth year, a retirement age, or a return isn't set. Otherwise:

  `%{start: %{balance, accounts, read}, monthly_contribution, retire_year, retire_age, return_bp,
  rows: [%{year, age, contributed, growth, balance}], at_retirement, gap, lasts}`

  where `accounts` are the retirement accounts the member can see and `read` those with a balance;
  `gap` is the target less Social Security, or nil without a target; `lasts` is nil without a
  target, `:covered` when there is no difference to pay, `:beyond` when some would remain at age
  100, or `{:months, n}`.
  """
  def project(h, m, %Date{} = today, overrides \\ %{}) do
    s = Map.merge(settings(h, m), overrides)

    case Enum.filter([:birth_year, :retire_age, :return_bp], &(s[&1] == nil)) do
      [] -> run(h, m, today, s)
      missing -> {:missing, missing}
    end
  end

  defp run(h, m, today, s) do
    accounts = for i <- View.visible_items(h, m), Balances.retirement?(i), do: i.id

    read =
      for id <- accounts, r = Balances.latest(h, m, id), do: {id, r.balance}

    balance = read |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    monthly =
      s.contributions
      |> Enum.filter(fn {id, _} -> id in accounts end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

    retire_year = s.birth_year + s.retire_age

    # each month from this one until January of the retirement year: growth, then the contribution
    months =
      if retire_year > today.year,
        do:
          for(
            y <- today.year..(retire_year - 1),
            mo <- 1..12,
            {y, mo} >= {today.year, today.month},
            do: y
          ),
        else: []

    {rows, final} =
      months
      |> Enum.chunk_by(& &1)
      |> Enum.map_reduce(balance, fn [y | _] = ms, bal ->
        {bal2, growth} =
          Enum.reduce(ms, {bal, 0}, fn _, {b, g} ->
            i = grow(b, s.return_bp)
            {b + i + monthly, g + i}
          end)

        {%{
           year: y,
           age: y - s.birth_year,
           contributed: monthly * length(ms),
           growth: growth,
           balance: bal2
         }, bal2}
      end)

    gap = if s.target_monthly, do: s.target_monthly - (s.ss_monthly || 0)

    %{
      start: %{
        balance: balance,
        accounts: Enum.sort(accounts),
        read: read |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      },
      monthly_contribution: monthly,
      retire_year: retire_year,
      retire_age: s.retire_age,
      return_bp: s.return_bp,
      rows: rows,
      at_retirement: final,
      gap: gap,
      lasts:
        lasts(
          final,
          gap,
          s.return_bp,
          (@horizon_age - max(s.retire_age, today.year - s.birth_year)) * 12
        )
    }
  end

  defp lasts(_bal, nil, _bp, _limit), do: nil
  defp lasts(_bal, gap, _bp, _limit) when gap <= 0, do: :covered

  # month by month: growth, then the month's difference paid out
  defp lasts(bal, gap, bp, limit) do
    Enum.reduce_while(1..max(limit, 1), bal, fn k, b ->
      b = b + grow(b, bp) - gap

      cond do
        # paid in full for k months when it reaches exactly zero; for k - 1 when it runs short
        b == 0 -> {:halt, {:months, k}}
        b < 0 -> {:halt, {:months, k - 1}}
        true -> {:cont, b}
      end
    end)
    |> case do
      {:months, _} = done when bal > 0 -> done
      {:months, _} -> {:months, 0}
      _ -> :beyond
    end
  end

  defp grow(b, bp) when b > 0, do: Balances.monthly_interest(%{balance: b, rate_bp: bp})
  defp grow(_b, _bp), do: 0

  @doc """
  The result as entered and with one assumption changed at a time (REQ-153): the return two
  percentage points lower and higher, and retirement two years earlier and later. Each entry is
  `%{change, return_bp, retire_age, at_retirement, lasts}`; `change` is `:as_entered`,
  `{:return, -200 | 200}`, or `{:retire_age, -2 | 2}`. Changes outside the allowed ranges are left out.
  """
  def sensitivity(h, m, %Date{} = today) do
    case project(h, m, today) do
      {:missing, _} = missing ->
        missing

      base ->
        s = settings(h, m)

        changes =
          [{:return, -200}, {:return, 200}, {:retire_age, -2}, {:retire_age, 2}]
          |> Enum.filter(fn
            {:return, d} -> valid_value?(:return_bp, s.return_bp + d)
            {:retire_age, d} -> valid_value?(:retire_age, s.retire_age + d)
          end)

        [{:as_entered, base}] ++
          for {k, d} = change <- changes do
            o =
              if k == :return,
                do: %{return_bp: s.return_bp + d},
                else: %{retire_age: s.retire_age + d}

            {change, project(h, m, today, o)}
          end
    end
    |> case do
      {:missing, _} = missing ->
        missing

      list ->
        for {change, p} <- list,
            do: %{
              change: change,
              return_bp: p.return_bp,
              retire_age: p.retire_age,
              at_retirement: p.at_retirement,
              lasts: p.lasts
            }
    end
  end
end
