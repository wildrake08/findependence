defmodule FindependenceApp.Planning do
  @moduledoc """
  Domain context Planning (DP-001 section 2; CAP-007, CAP-012, CAP-013, MEC-019..021): each member's
  private plans and steps, marks, shared plans, goals, and retirement assumptions.
  """

  alias FindependenceApp.{Money, Operation, Scope}
  alias Findependence.{Plans, Retirement}

  @doc "Starts a private plan with the given id and name (REQ-142)."
  def new_plan(%Scope{member: m} = scope, id, name),
    do: Operation.run(scope, &Plans.new_plan(&1, m, id, name || ""))

  @doc "Proposes a plan to other members as a shared plan (REQ-148)."
  def share_plan(%Scope{member: m} = scope, plan, others),
    do: Operation.run(scope, &Plans.propose_shared(&1, m, plan, Operation.new_id(), others))

  @doc """
  Adds a step to a plan (REQ-142), checked here so every transport gets the same rules and the same
  plainly named mistakes. `input` is `%{kind:, items:, from:, note:, amount:, frequency:, borrow:}`:
  `amount` as the transport decoded it (`{:ok, cents_or_nil}` or `{:error, message}`), `frequency` a stored
  term or nil, and `borrow` `{:ok, %{amount:, rate_bp:, payment:}}` or `:error`. A problem is
  `{:error, :validation, message}`.
  """
  def add_step(%Scope{member: m} = scope, plan, input) do
    case step(input) do
      {:ok, st} -> Operation.run(scope, &Plans.add_step(&1, m, plan, st))
      {:error, message} -> {:error, :validation, message}
    end
  end

  defp step(%{kind: "switch_off", items: items, from: from}) do
    case items do
      [] -> {:error, "Tick at least one item to switch off."}
      ids -> {:ok, {:switch_off, ids, from}}
    end
  end

  defp step(%{kind: "add", note: raw, amount: amount, frequency: f, from: from}) do
    named = Money.name(raw)
    note = String.trim(raw || "")

    case amount do
      _ when note == "" ->
        {:error, "Name the planned item."}

      _ when elem(named, 0) == :error ->
        {:error, "Name the planned item in 200 characters or fewer."}

      _ when f == nil ->
        {:error, "Choose how often the planned item happens."}

      {:ok, cents} when is_integer(cents) and cents != 0 ->
        {:ok, {:add, %{note: note, amount: cents, frequency: f}, from}}

      {:error, message} ->
        {:error, message}

      _ ->
        {:error, "Enter the planned amount."}
    end
  end

  defp step(%{kind: "borrow", borrow: {:ok, b}, from: from}), do: {:ok, {:borrow, b, from}}

  defp step(%{kind: "borrow"}),
    do: {:error, "Enter how much to borrow, the interest rate, and the monthly payment."}

  defp step(_), do: {:error, "Choose a kind of step."}

  @doc "Removes step `n` from a plan (REQ-142)."
  def remove_step(%Scope{member: m} = scope, plan, n),
    do: Operation.run(scope, &Plans.remove_step(&1, m, plan, n))

  @doc "Deletes a plan (REQ-142, REQ-166)."
  def delete_plan(%Scope{member: m} = scope, plan),
    do: Operation.run(scope, &Plans.delete_plan(&1, m, plan))

  @doc "Marks an item as depending on a job (REQ-144)."
  def mark(%Scope{member: m} = scope, item, job),
    do: Operation.run(scope, &Plans.mark(&1, m, item, job))

  @doc "Removes a mark (REQ-144)."
  def unmark(%Scope{member: m} = scope, item, job),
    do: Operation.run(scope, &Plans.unmark(&1, m, item, job))

  @doc "Sets or clears the emergency-fund goal in months (REQ-146); `:invalid` is refused by the core."
  def set_fund_goal(%Scope{member: m} = scope, months),
    do: Operation.run(scope, &Plans.set_fund_goal(&1, m, months))

  @doc "Sets or clears the set-aside rate for a value's money in (REQ-147)."
  def set_aside(%Scope{member: m} = scope, value, rate_bp),
    do: Operation.run(scope, &Plans.set_aside(&1, m, value, rate_bp))

  @doc """
  Saves the retirement assumptions together (REQ-150): `fields` as `[{field, value}]` and `contributions`
  as `[{account_id, cents}]`, each value already checked by the transport.
  """
  def set_retirement(%Scope{member: m} = scope, fields, contributions) do
    Operation.run(scope, fn h ->
      with {:ok, h} <-
             Enum.reduce_while(fields, {:ok, h}, fn {f, v}, {:ok, h} ->
               step_result(Retirement.set(h, m, f, v))
             end) do
        Enum.reduce_while(contributions, {:ok, h}, fn {id, v}, {:ok, h} ->
          step_result(Retirement.set_contribution(h, m, id, v))
        end)
      end
    end)
  end

  defp step_result({:ok, _} = ok), do: {:cont, ok}
  defp step_result(error), do: {:halt, error}

  @doc "The member's plan with this id, or nil (plans are private, REQ-142)."
  def plan(%Scope{member: m, household: h}, id), do: Plans.plans(h, m)[id]

  # ---------------------------------------------------------------------------
  # Reads: the member's own plans, marks, goals, and retirement assumptions (private, REQ-142..REQ-150).

  @doc "The member's plans, by id."
  def plans(%Scope{member: m, household: h}), do: Plans.plans(h, m)

  @doc "The member's marks: `{item, job}` pairs (REQ-144)."
  def depends(%Scope{member: m, household: h}), do: Plans.depends(h, m)

  @doc "The member's goals (REQ-146, REQ-147)."
  def goals(%Scope{member: m, household: h}), do: Plans.goals(h, m)

  @doc "How long the savings the member can see would cover their money out (REQ-146)."
  def cover(%Scope{member: m, household: h}), do: Findependence.Projection.cover(h, m)

  @doc "The monthly amounts the member's set-aside rates set aside (REQ-147)."
  def set_asides(%Scope{member: m, household: h}), do: Findependence.Projection.set_asides(h, m)

  @doc "The member's retirement assumptions (REQ-150)."
  def retirement_settings(%Scope{member: m, household: h}), do: Retirement.settings(h, m)

  @doc "The retirement projection (REQ-151, REQ-174)."
  def retirement_projection(%Scope{member: m, household: h}, %Date{} = today),
    do: Retirement.project(h, m, today)

  @doc "How sensitive the retirement result is (REQ-153)."
  def retirement_sensitivity(%Scope{member: m, household: h}, %Date{} = today),
    do: Retirement.sensitivity(h, m, today)

  @doc "Whether an item is a shared plan (REQ-148)."
  defdelegate plan?(item), to: Plans
end
