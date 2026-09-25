defmodule RI01.Check do
  @moduledoc """
  Evaluates every invariant listed in framework/invariants/core.yaml (REQ-001) and
  combines the outcomes (REQ-002, REQ-003). Performs no writes (REQ-004).
  """

  alias RI01.{Invariants, Store}

  defstruct [:store, :store_outcome, :results, :overall]

  def run(root) do
    store = Store.load(root)
    store_outcome = if store.load_errors == [], do: :pass, else: :fail
    results = Enum.map(store.invariants, &{&1, evaluate(&1, store)})
    %__MODULE__{store: store, store_outcome: store_outcome, results: results, overall: overall(store_outcome, results)}
  end

  def evaluate(%{"id" => id} = invariant, store) do
    cond do
      invariant["deterministic"] != true ->
        {:indeterminate, 0, ["not declared deterministic in core.yaml"]}

      not Invariants.defined?(id) ->
        {:indeterminate, 0, ["no rule implemented for #{id}"]}

      true ->
        try do
          Invariants.rule(id, store)
        rescue
          e -> {:indeterminate, 0, ["rule raised #{inspect(e.__struct__)}: #{Exception.message(e)}"]}
        end
    end
  end

  defp overall(store_outcome, results) do
    outcomes = [store_outcome | Enum.map(results, fn {_, {o, _, _}} -> o end)]

    cond do
      :fail in outcomes -> :fail
      :indeterminate in outcomes -> :indeterminate
      true -> :pass
    end
  end

  def exit_code(:pass), do: 0
  def exit_code(:fail), do: 1
  def exit_code(:indeterminate), do: 3
end
