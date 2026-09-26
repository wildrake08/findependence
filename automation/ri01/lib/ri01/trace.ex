defmodule RI01.Trace do
  @moduledoc """
  AUT-TRACE: justification paths over the artifact store (WI-002). Read-only (REQ-012).

  Upward (REQ-008): each ImplementationElement must reach a Subject or a governance root over
  justification edges, through artifacts that are neither proposed nor unsettled, with every
  Requirement on the path accepted or canonical.

  Downward (REQ-009): each accepted or canonical Capability, Function, Mechanism, and
  Requirement must reach an ImplementationElement over the reversed edges, or carry an
  explicit disposition on itself or an intermediate artifact.
  """

  alias RI01.Store

  # Justification edges, pointing from the justified artifact to its justification.
  @upward ~w(implements satisfies derived_from realizes enables required_of contributes_to
    advances concerns has_purpose)
  # depends_on counts as justification only from normative and contextual artifacts.
  @normative_types ~w(Principle Constraint NormativePosition Context)
  @governance_sources ~w(CONSTITUTION.md GOVERNANCE.md framework/ automation/)
  @unsettled ~w(contested weakened reopened superseded retired)
  @responsibility_types ~w(Capability Function Mechanism Requirement)

  defstruct [:store, :store_outcome, :upward, :downward, :overall]

  def run(root) do
    store = Store.load(root)
    store_outcome = if store.load_errors == [], do: :pass, else: :fail

    upward =
      for ie <- of_type(store, "ImplementationElement"), do: {ie["id"], evaluate_upward(store, ie)}

    downward =
      for a <- store.artifacts, a["type"] in @responsibility_types, accepted?(a),
          a["state"] not in ~w(superseded retired),
          do: {a["id"], evaluate_downward(store, a)}

    outcomes = [store_outcome | Enum.map(upward ++ downward, fn {_, r} -> elem(r, 0) end)]
    overall = if :fail in outcomes, do: :fail, else: :pass

    %__MODULE__{store: store, store_outcome: store_outcome, upward: upward, downward: downward, overall: overall}
  end

  @doc "All upward paths from `id`, each a list of ids ending at a root or a dead end."
  def upward_paths(store, id), do: walk_up(store, id, [id])

  @doc "The downward realization tree of `id` as `{id, children}`."
  def downward_tree(store, id, seen \\ MapSet.new()) do
    children =
      for child <- justified_by(store, id), child not in seen,
          do: downward_tree(store, child, MapSet.put(seen, id))

    {id, children}
  end

  def root_kind(store, id) do
    a = store.by_id[id]

    cond do
      a == nil -> nil
      a["type"] == "Subject" -> :subject
      governance_root?(a) -> :governance
      true -> nil
    end
  end

  # ---------------------------------------------------------------------------

  defp evaluate_upward(store, ie) do
    paths = upward_paths(store, ie["id"])
    rooted = Enum.filter(paths, &(root_kind(store, List.last(&1)) != nil))
    valid = Enum.filter(rooted, &(path_defects(store, &1) == []))

    cond do
      valid != [] ->
        {:pass, Enum.map(valid, &{&1, root_kind(store, List.last(&1))})}

      rooted == [] ->
        {:fail, ["no upward path reaches a Subject or governance root" | dead_ends(paths)]}

      true ->
        {:fail, Enum.flat_map(rooted, &path_defects(store, &1)) |> Enum.uniq()}
    end
  end

  defp evaluate_downward(store, a) do
    case realization(store, a["id"], MapSet.new()) do
      {:realized, ies} -> {:pass, {:realized, ies}}
      {:disposed, ids} -> {:pass, {:disposed, ids}}
      :gap -> {:fail, ["#{a["id"]}: no downward path to an ImplementationElement and no disposition"]}
    end
  end

  # Collects IEs reachable downward; a disposition anywhere on the way counts as coverage.
  defp realization(store, id, seen) do
    a = store.by_id[id]

    cond do
      a["type"] == "ImplementationElement" ->
        {:realized, [id]}

      true ->
        results =
          for child <- justified_by(store, id), child not in seen,
              do: realization(store, child, MapSet.put(seen, id))

        ies = for {:realized, list} <- results, x <- list, uniq: true, do: x
        disposed = for {:disposed, list} <- results, x <- list, uniq: true, do: x

        cond do
          ies != [] -> {:realized, ies}
          a["disposition"] != nil -> {:disposed, [id]}
          disposed != [] -> {:disposed, disposed}
          true -> :gap
        end
    end
  end

  defp walk_up(store, id, path) do
    nexts = for t <- justifications(store, id), t not in path, do: t

    cond do
      root_kind(store, id) != nil and length(path) > 1 -> [Enum.reverse(path)]
      nexts == [] -> [Enum.reverse(path)]
      true -> Enum.flat_map(nexts, &walk_up(store, &1, [&1 | path]))
    end
  end

  defp justifications(store, id) do
    a = store.by_id[id] || %{}

    for %{"type" => t, "to" => to} <- List.wrap(a["relationships"]),
        t in @upward or (t == "depends_on" and a["type"] in @normative_types),
        Map.has_key?(store.by_id, to),
        do: to
  end

  defp justified_by(store, id) do
    for a <- store.artifacts, id in justifications(store, a["id"]), do: a["id"]
  end

  defp path_defects(store, [_ie | rest]) do
    for id <- rest, a = store.by_id[id], defect = defect(a), do: "#{id}: #{defect}"
  end

  defp defect(%{"state" => s}) when s in @unsettled, do: "on path but #{s}"
  defp defect(%{"state" => "proposed"}), do: "on path but only proposed"
  defp defect(%{"type" => "Requirement"} = r), do: unless(accepted?(r), do: "Requirement on path is not accepted")
  defp defect(_), do: nil

  defp dead_ends(paths) do
    for p <- paths, do: "dead end: #{Enum.join(p, " -> ")}"
  end

  defp accepted?(a), do: a["state"] == "canonical" or a["accepted_by"] != nil

  defp governance_root?(%{"type" => "Constraint", "state" => state} = a) when state not in [nil, "proposed"] do
    Enum.any?(List.wrap(a["sources"]), fn src ->
      is_binary(src) and Enum.any?(@governance_sources, &String.starts_with?(src, &1))
    end)
  end

  defp governance_root?(_), do: false

  defp of_type(store, type), do: Enum.filter(store.artifacts, &(&1["type"] == type))
end
