defmodule Findependence.Balances do
  @moduledoc """
  CAP-010 balances and debts (MEC-017, CP-013 A).

  An account or a debt is an ordinary item of its own kind (REQ-130), so ownership, sharing,
  exit, and history apply unchanged. Its name and kind are fixed; what changes over time is kept
  as append-only readings (REQ-131): for an account, its balance; for a debt, the amount owed, the
  interest rate in basis points, and the minimum payment. Every reading has the date it is as of,
  as an ISO 8601 string.

  Anyone who can read the item can read its latest reading; its owners can read all of them
  (REQ-132). Accounts and debts are not money in or out (REQ-134).
  """

  alias Findependence.{Household, Ledger, View}

  @account_types [:checking, :savings, :other, :retirement_401k, :ira]
  # CAP-012 (REQ-149): retirement accounts are accounts, but never cash
  @retirement_types [:retirement_401k, :ira]
  @debt_types [:card, :heloc, :loan, :other]

  def account_types, do: @account_types
  def retirement_types, do: @retirement_types
  def debt_types, do: @debt_types

  @doc "Every atom an account, a debt, or a reading can contain, for decoders that must know them in advance."
  def format_atoms,
    do:
      [
        :account,
        :debt,
        :account_type,
        :debt_type,
        :balance,
        :rate_bp,
        :min_payment,
        :on,
        :reading_added
      ] ++
        @account_types ++ @debt_types

  @doc "Adds an account the actor owns alone (REQ-130)."
  def add_account(h, actor, id, label, type)
      when is_binary(label) and label != "" and type in @account_types,
      do: Household.add_item(h, actor, id, %{kind: :account, label: label, account_type: type})

  def add_account(_h, _actor, _id, _label, _type), do: {:error, :invalid_balance}

  @doc "Adds a debt the actor owns alone (REQ-130)."
  def add_debt(h, actor, id, label, type)
      when is_binary(label) and label != "" and type in @debt_types,
      do: Household.add_item(h, actor, id, %{kind: :debt, label: label, debt_type: type})

  def add_debt(_h, _actor, _id, _label, _type), do: {:error, :invalid_balance}

  @doc "True for accounts and debts."
  def balance?(%{attrs: attrs}), do: Map.get(attrs, :kind) in [:account, :debt]
  def balance?(_), do: false

  @doc "True for accounts, false for debts and everything else."
  def account?(%{attrs: attrs}), do: Map.get(attrs, :kind) == :account

  @doc "True for 401(k) and IRA accounts (REQ-149)."
  def retirement?(%{attrs: attrs}),
    do: Map.get(attrs, :kind) == :account and Map.get(attrs, :account_type) in @retirement_types

  def retirement?(_), do: false

  @doc "True for accounts that hold cash: every account except retirement accounts (REQ-149)."
  def cash_account?(i), do: account?(i) and not retirement?(i)

  @doc """
  Adds a reading (REQ-131). Only an owner may; anyone else who can see the item gets
  `:not_owner`, and anyone who can't see it gets `:not_found`, like a missing item. `reading` is
  `%{on: "YYYY-MM-DD", balance: cents}` for an account, and additionally `rate_bp:` and
  `min_payment:` for a debt.
  """
  def add_reading(%Household{} = h, actor, id, reading) do
    item = h.items[id]

    cond do
      item == nil or not View.visible?(h, actor, id) -> {:error, :not_found}
      not balance?(item) -> {:error, :not_a_balance}
      actor not in item.owners -> {:error, :not_owner}
      not valid?(item, reading) -> {:error, :invalid_reading}
      true -> {:ok, append(h, actor, id, reading)}
    end
  end

  defp append(h, actor, id, reading) do
    existing = Map.get(h.readings, id, [])
    seq = length(existing) + 1

    entry =
      Map.merge(Map.take(reading, [:on, :balance, :rate_bp, :min_payment]), %{seq: seq, by: actor})

    %{h | readings: Map.put(h.readings, id, existing ++ [entry])}
    |> Ledger.record(id, actor, :reading_added, %{seq: seq})
  end

  defp valid?(item, %{on: on, balance: balance} = r) when is_binary(on) and is_integer(balance) do
    date_ok = match?({:ok, _}, Date.from_iso8601(on))

    case item.attrs[:kind] do
      :account ->
        date_ok and map_size(Map.drop(r, [:on, :balance])) == 0

      :debt ->
        date_ok and valid_owed?(balance) and valid_rate?(r[:rate_bp]) and
          valid_min_payment?(r[:min_payment]) and
          map_size(Map.drop(r, [:on, :balance, :rate_bp, :min_payment])) == 0
    end
  end

  defp valid?(_item, _reading), do: false

  @doc "True for a debt's amount owed in cents (REQ-131): not negative."
  def valid_owed?(balance), do: is_integer(balance) and balance >= 0

  @doc "True for an interest rate in basis points (REQ-131, REQ-142): from 0% to 100%."
  def valid_rate?(bp), do: is_integer(bp) and bp in 0..10_000

  @doc "True for a debt's minimum payment in cents (REQ-131): not negative."
  def valid_min_payment?(cents), do: is_integer(cents) and cents >= 0

  @doc """
  The readings `member` may read, oldest first (REQ-132): all of them for an owner, only the
  latest for anyone else who can see the item. `{:error, :not_found}` if they can't see it.
  """
  def readings(%Household{} = h, member, id) do
    cond do
      not View.visible?(h, member, id) -> {:error, :not_found}
      member in h.items[id].owners -> {:ok, Map.get(h.readings, id, [])}
      true -> {:ok, h.readings |> Map.get(id, []) |> Enum.take(-1)}
    end
  end

  @doc "The latest reading `member` can read, or nil."
  def latest(h, member, id) do
    # a reading the member cannot open (a placeholder in an app session) is never returned
    with {:ok, list} <- readings(h, member, id),
         %{} = r <- List.last(list) do
      r
    else
      _ -> nil
    end
  end

  @doc "Interest for one month at the reading's rate on its balance, in cents, rounded (REQ-135)."
  def monthly_interest(%{balance: balance, rate_bp: rate_bp}) do
    n = balance * rate_bp
    d = 12 * 10_000
    if n < 0, do: -div(-2 * n + d, 2 * d), else: div(2 * n + d, 2 * d)
  end
end
