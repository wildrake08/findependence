defmodule Findependence.Plans do
  @moduledoc """
  CAP-007 plans and CAP-013 goals (MEC-019), and CAP-005 shared plans (MEC-020).

  A member's plans, "depends on this job" marks, and goals live in their own private record, like
  links (MEC-009): they change freely and nobody else can read them. A plan has a name and steps:

  - `{:switch_off, [item_id], from}`: items the member owns stop from a month (REQ-142);
  - `{:add, %{note, amount, frequency}, from}`: a planned item, in cents, signed like items;
  - `{:borrow, %{amount, rate_bp, payment}, from}`: money borrowed, with its rate and payment.

  `from` is a month, `"YYYY-MM"`. Nothing here is an item or counts in real totals (REQ-142, REQ-143).
  A shared plan is an item of kind `:plan` with a snapshot of the steps; members join it only with
  their own consent (REQ-148, the REQ-115 rule).
  """

  alias Findependence.{Alignment, Balances, Household, View}

  @doc "Every atom a plan, mark, goal, or shared plan can contain, for decoders that must know them."
  def format_atoms,
    do: [
      :plans,
      :depends,
      :goals,
      :plan,
      :steps,
      :name,
      :from,
      :payment,
      :switch_off,
      :add,
      :borrow,
      :fund_months,
      :set_aside,
      :next_step
    ]

  @doc "True for shared plans (items of kind :plan)."
  def plan?(%{attrs: attrs}), do: Map.get(attrs, :kind) == :plan
  def plan?(_), do: false

  @doc "True for money items: not a value, account, debt, or shared plan."
  def money?(i), do: not (Alignment.value?(i) or Balances.balance?(i) or plan?(i))

  # ---------------------------------------------------------------------------
  # Personal plans (REQ-142)

  @doc "The member's own plans: `%{plan_id => %{name, steps: [%{n, step}], next_step}}`."
  def plans(h, m), do: Map.get(h.plans, m, %{})

  def new_plan(%Household{} = h, m, id, name) when is_binary(name) do
    name = String.trim(name)

    cond do
      m not in h.members ->
        {:error, :not_a_member}

      # REQ-157 (DEF-049): the rule a saved file is checked against: 1 to 200 characters
      name == "" or String.length(name) > 200 ->
        {:error, :invalid_plan}

      Map.has_key?(plans(h, m), id) ->
        {:error, :plan_exists}

      true ->
        {:ok, put_plans(h, m, Map.put(plans(h, m), id, %{name: name, steps: [], next_step: 1}))}
    end
  end

  def new_plan(_h, _m, _id, _name), do: {:error, :invalid_plan}

  def delete_plan(h, m, id) do
    if Map.has_key?(plans(h, m), id),
      do: {:ok, put_plans(h, m, Map.delete(plans(h, m), id))},
      else: {:error, :not_found}
  end

  @doc "Adds a step, checked against what the member owns (REQ-142)."
  def add_step(h, m, id, step) do
    with %{} = plan <- plans(h, m)[id] || {:error, :not_found},
         :ok <- valid_step(h, m, step) do
      plan = %{
        plan
        | steps: plan.steps ++ [%{n: plan.next_step, step: step}],
          next_step: plan.next_step + 1
      }

      {:ok, put_plans(h, m, Map.put(plans(h, m), id, plan))}
    end
  end

  def remove_step(h, m, id, n) do
    case plans(h, m)[id] do
      %{steps: steps} = plan ->
        if Enum.any?(steps, &(&1.n == n)),
          do:
            {:ok,
             put_plans(
               h,
               m,
               Map.put(plans(h, m), id, %{plan | steps: Enum.reject(steps, &(&1.n == n))})
             )},
          else: {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  defp put_plans(h, m, p), do: %{h | plans: Map.put(h.plans, m, p)}

  defp valid_step(h, m, {:switch_off, ids, from}) when is_list(ids) and ids != [] do
    owned? = fn id -> (i = h.items[id]) != nil and m in i.owners and money?(i) end
    if month?(from) and Enum.all?(ids, owned?), do: :ok, else: {:error, :invalid_step}
  end

  defp valid_step(_h, _m, {:add, %{note: note, amount: a, frequency: f}, from})
       when is_binary(note) and note != "" and is_integer(a) and a != 0 do
    if month?(from) and Alignment.frequency(%{attrs: %{frequency: f}}) == f,
      do: :ok,
      else: {:error, :invalid_step}
  end

  defp valid_step(_h, _m, {:borrow, %{amount: a, rate_bp: r, payment: p}, from})
       when is_integer(a) and a > 0 and is_integer(r) and r in 0..10_000 and is_integer(p) and
              p > 0 do
    if month?(from), do: :ok, else: {:error, :invalid_step}
  end

  defp valid_step(_h, _m, _step), do: {:error, :invalid_step}

  @doc "True for a month written \"YYYY-MM\"."
  def month?(from) when is_binary(from), do: match?({:ok, _}, Date.from_iso8601(from <> "-01"))
  def month?(_), do: false

  # ---------------------------------------------------------------------------
  # "Depends on this job" marks (REQ-144)

  @doc "The member's marks, as `{item_id, job_id}` pairs whose items they still own."
  def depends(h, m) do
    for {i, j} <- Map.get(h.depends, m, MapSet.new()),
        owns?(h, m, i) and owns?(h, m, j),
        do: {i, j}
  end

  def mark(h, m, item, job) do
    cond do
      not (owns?(h, m, item) and owns?(h, m, job)) ->
        {:error, :not_found}

      item == job ->
        {:error, :invalid_mark}

      not income?(h.items[job]) ->
        {:error, :not_income}

      {item, job} in depends(h, m) ->
        {:error, :already_marked}

      true ->
        {:ok,
         %{
           h
           | depends:
               Map.update(h.depends, m, MapSet.new([{item, job}]), &MapSet.put(&1, {item, job}))
         }}
    end
  end

  def unmark(h, m, item, job) do
    if {item, job} in depends(h, m),
      do: {:ok, %{h | depends: Map.update!(h.depends, m, &MapSet.delete(&1, {item, job}))}},
      else: {:error, :not_found}
  end

  defp owns?(h, m, id), do: (i = h.items[id]) != nil and m in i.owners and money?(i)
  defp income?(i), do: is_integer(i.attrs[:amount]) and i.attrs[:amount] > 0

  @doc "Removes marks, retirement contributions, and account attachments naming a deleted item, like Alignment.purge_item/2. Plan steps keep the id and read as an item no longer there."
  def purge_item(h, id) do
    depends =
      Map.new(h.depends, fn {m, set} ->
        {m, MapSet.reject(set, fn {i, j} -> i == id or j == id end)}
      end)

    %{h | depends: depends}
    |> Findependence.Retirement.purge_item(id)
    |> Findependence.Attach.purge_item(id)
  end

  # ---------------------------------------------------------------------------
  # Goals (REQ-146, REQ-147)

  def goals(h, m), do: Map.merge(%{fund_months: nil, set_aside: %{}}, Map.get(h.goals, m, %{}))

  @doc "Sets (or clears, with nil) the emergency fund goal in months of money out."
  def set_fund_goal(h, m, months) when is_nil(months) or (is_integer(months) and months in 1..60),
    do: {:ok, put_goals(h, m, %{goals(h, m) | fund_months: months})}

  def set_fund_goal(_h, _m, _), do: {:error, :invalid_goal}

  @doc "Sets (or clears, with nil) a set-aside rate, in basis points, for money in linked to a value."
  def set_aside(h, m, value_id, bp) do
    v = h.items[value_id]

    cond do
      v == nil or not View.visible?(h, m, value_id) or not Alignment.value?(v) ->
        {:error, :not_found}

      bp == nil ->
        {:ok,
         put_goals(h, m, %{goals(h, m) | set_aside: Map.delete(goals(h, m).set_aside, value_id)})}

      is_integer(bp) and bp in 1..10_000 ->
        {:ok,
         put_goals(h, m, %{goals(h, m) | set_aside: Map.put(goals(h, m).set_aside, value_id, bp)})}

      true ->
        {:error, :invalid_goal}
    end
  end

  defp put_goals(h, m, g), do: %{h | goals: Map.put(h.goals, m, g)}

  # ---------------------------------------------------------------------------
  # Shared plans (REQ-148)

  @doc """
  Proposes the member's plan `plan_id` to `others` as a shared plan: an item of kind `:plan` holding
  a snapshot, owned by the member until each named member agrees (REQ-115 applied to plans).
  """
  def propose_shared(h, m, plan_id, item_id, others) when is_list(others) and others != [] do
    with %{} = plan <- plans(h, m)[plan_id] || {:error, :not_found},
         true <- Enum.all?(others, &(&1 in h.members and &1 != m)) || {:error, :not_a_member},
         {:ok, h} <-
           Household.add_item(h, m, item_id, %{kind: :plan, label: plan.name, steps: plan.steps}) do
      Household.propose_owners(h, m, item_id, [m | others])
    end
  end

  def propose_shared(_h, _m, _plan_id, _item_id, _others), do: {:error, :not_a_member}
end
