defmodule FindependenceShared.Balances do
  @moduledoc """
  Domain context Balances (DP-001 section 2; CAP-010, MEC-017, MEC-023): accounts, debts, their readings,
  and which account a money item goes through.
  """

  alias FindependenceShared.{Names, Persistence, Scope}
  alias Findependence.{Attach, View}

  @doc """
  Adds an account (REQ-171) with the given id, name, and type (a stored type, or nil if none was chosen).
  The name follows REQ-157; a missing type is refused. `{:error, :validation, {field, message}}` names the
  first problem, the name before the type.
  """
  def add_account(%Scope{} = scope, id, label, type),
    do: add(scope, id, label, type, &Findependence.Balances.add_account/5)

  @doc "Adds a debt (REQ-171), under the same rules as `add_account/4`."
  def add_debt(%Scope{} = scope, id, label, type),
    do: add(scope, id, label, type, &Findependence.Balances.add_debt/5)

  defp add(%Scope{member: m} = scope, id, label, type, add) do
    label = String.trim(label || "")

    case Names.name(label) do
      {:error, message} -> {:error, :validation, {:label, message}}
      {:ok, _} when type == nil -> {:error, :validation, {:type, "Choose what kind it is."}}
      {:ok, _} -> Persistence.run(scope, &add.(&1, m, id, label, type))
    end
  end

  @doc """
  Adds a reading to an account or debt the member owns (REQ-131). Someone who can't update it is told so
  by the core whatever they typed. For an owner the fields are checked here, in the form's order, with
  core's rules: `input` is `%{balance:, on:, rate:, min_payment:}` as the transport decoded them (balance
  `{:ok, cents_or_nil, negative?}` or `:error`; date `{:ok, iso}` or `:error`; rate `{:ok, bp}` or
  `:error`; minimum payment as `Money.parse/2` returns it). A problem is
  `{:error, :validation, {field, message}}`.
  """
  def add_reading(%Scope{member: m} = scope, item, input) do
    %{debt?: debt?, owner?: owner?} = reading_target(scope, item)

    cond do
      not owner? ->
        Persistence.run(scope, &Findependence.Balances.add_reading(&1, m, item, %{}))

      true ->
        with {:ok, balance} <- reading_balance(input.balance, debt?),
             {:ok, on} <- reading_date(input.on),
             {:ok, extra} <- debt_fields(input, debt?) do
          reading = Map.merge(%{on: on, balance: balance}, extra)
          Persistence.run(scope, &Findependence.Balances.add_reading(&1, m, item, reading))
        else
          {:error, field, message} -> {:error, :validation, {field, message}}
        end
    end
  end

  # An account may be overdrawn; a debt's amount owed may not be negative (REQ-131).
  defp reading_balance({:ok, _, true}, true = _debt?), do: owed_error()
  defp reading_balance({:ok, nil, _}, _debt?), do: {:error, :balance, "Enter the balance."}
  defp reading_balance({:ok, cents, true}, false), do: {:ok, -cents}

  defp reading_balance({:ok, cents, false}, debt?) do
    if not debt? or Findependence.Balances.valid_owed?(cents),
      do: {:ok, cents},
      else: owed_error()
  end

  defp reading_balance(:error, true), do: owed_error()

  defp reading_balance(:error, false),
    do: {:error, :balance, "Enter the balance, like 1,240.50, or −50 if overdrawn."}

  defp owed_error, do: {:error, :balance, "Enter the amount owed, like 5,200 or 5200.00."}

  defp reading_date({:ok, iso}), do: {:ok, iso}
  defp reading_date(:error), do: {:error, :on, "Enter the date, like 2026-09-27."}

  defp debt_fields(_input, false), do: {:ok, %{}}

  defp debt_fields(%{rate: rate, min_payment: min}, true) do
    with {:rate, {:ok, bp}} <- {:rate, rate},
         {:rate, true} <- {:rate, Findependence.Balances.valid_rate?(bp)},
         {:min, {:ok, cents}} when is_integer(cents) <- {:min, min},
         {:min, true} <- {:min, Findependence.Balances.valid_min_payment?(cents)} do
      {:ok, %{rate_bp: bp, min_payment: cents}}
    else
      {:rate, _} -> {:error, :rate, "Enter the interest rate as a percentage, like 21.99."}
      {:min, _} -> {:error, :min_payment, "Enter the minimum payment, like 150."}
    end
  end

  @doc "What a reading form for `item` needs: whether it is a debt, and whether the member owns it."
  def reading_target(%Scope{member: m, household: h}, item) do
    case h.items[item] do
      nil -> %{debt?: false, owner?: false}
      i -> %{debt?: i.attrs[:kind] == :debt, owner?: m in i.owners}
    end
  end

  @doc "Says which cash account a money item goes through, or clears it with nil (REQ-160)."
  def attach(%Scope{member: m} = scope, item, account),
    do: Persistence.run(scope, &Attach.attach(&1, m, item, account))

  @doc "The ids of the retirement accounts the member can see (REQ-149, REQ-150)."
  def retirement_account_ids(%Scope{member: m, household: h}) do
    for i <- View.visible_items(h, m), Findependence.Balances.retirement?(i), do: i.id
  end

  @doc "An account's or debt's latest reading the member can read (REQ-132), or nil."
  def latest(%Scope{member: m, household: h}, id), do: Findependence.Balances.latest(h, m, id)

  @doc "An account's or debt's readings, for its owners (REQ-132)."
  def readings(%Scope{member: m, household: h}, id), do: Findependence.Balances.readings(h, m, id)

  @doc "Which cash account each of the member's money items goes through (REQ-160)."
  def attached(%Scope{member: m, household: h}), do: Attach.attached(h, m)

  @doc "Whether an item is an account or a debt."
  defdelegate balance?(item), to: Findependence.Balances

  @doc "Whether an item is a cash account (checking, savings, or other)."
  defdelegate cash_account?(item), to: Findependence.Balances

  @doc "Whether an item is a retirement account (REQ-149)."
  defdelegate retirement?(item), to: Findependence.Balances

  @doc "A month's interest at a reading's balance and rate."
  defdelegate monthly_interest(reading), to: Findependence.Balances

  @doc "Months and interest to clear a debt at a monthly payment (REQ-145)."
  defdelegate payoff(balance, rate_bp, payment), to: Findependence.Projection
end
