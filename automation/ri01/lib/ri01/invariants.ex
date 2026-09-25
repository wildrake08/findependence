defmodule RI01.Invariants do
  @moduledoc """
  Deterministic rules for framework/invariants/core.yaml v1.

  core.yaml names invariants without defining them, so each rule's operational
  interpretation is recorded in `@interpretations` (REQ-005, ASM-011) and printed by
  `scripts/check --explain`.

  Each rule returns `{outcome, subjects, messages}`, where `outcome` is one of the
  framework validation outcomes (`:pass`, `:fail`, `:indeterminate`) and `subjects` is
  the number of artifacts the rule applied to.
  """

  alias RI01.Store

  @id_format ~r/^[A-Z][A-Z0-9]*-\d{3,}$/

  # Types governed by the semantic state machine in framework/states/machines.yaml.
  @semantic_machine_types ~w(Subject Telos Purpose Outcome Capability Function Mechanism
    Principle Constraint NormativePosition Context System DecisionScope Requirement
    CrossLevelSynthesis)

  # Relationships that form the justification hierarchy (I-004).
  @hierarchy ~w(concerns has_purpose advances contributes_to enables required_of realizes
    derived_from implements satisfies)

  @higher_claim_levels ~w(mechanism capability outcome purpose telos)
  @lower_evidence_kinds ~w(test deterministic_check static_analysis)
  @unsettled_states ~w(contested weakened reopened superseded retired)

  # Parent relationships used by delegated-authority conditions (REQ-013).
  @parent_relationship %{"Function" => "enables", "Mechanism" => "realizes", "Requirement" => "derived_from"}

  @interpretations %{
    "I-001" =>
      "Every artifact has an id matching #{Regex.source(@id_format)}, ids are unique, and an id committed at HEAD keeps its type.",
    "I-002" => "Every artifact type is listed in framework/vocabulary/artifacts.yaml.",
    "I-003" =>
      "Every relationship names a type in relationships.yaml, targets an existing artifact, and respects that type's allowed from/to artifact types.",
    "I-004" => "The graph of hierarchy relationships (#{Enum.join(@hierarchy, ", ")}) has no cycle.",
    "I-005" =>
      "A specified or canonical Requirement has at least one derived_from; a canonical Requirement's derived_from targets are themselves neither proposed nor unsettled.",
    "I-006" =>
      "Every ImplementationElement implements an existing Mechanism or satisfies an existing Requirement.",
    "I-007" =>
      "Every accepted (accepted_by) or canonical Requirement is satisfied by an ImplementationElement or carries an explicit disposition; likewise every canonical Mechanism is implemented or carries a disposition.",
    "I-008" =>
      "Every Evidence artifact is bound to at least one existing Claim: through supports/contradicts when qualified, through proposed_bindings when stage is candidate.",
    "I-009" =>
      "Evidence of kind runtime_observation may support or contradict a Claim only when stage is qualified and a qualification record is present.",
    "I-010" =>
      "Every Evidence artifact has separate integrity and applicability fields, each drawn from its own enumeration in machines.yaml.",
    "I-011" =>
      "An artifact governed by the semantic or claim state machine that is past its initial state has a history whose last 'to' equals its state, and every non-creation transition names an existing Actor (by) and an authority.",
    "I-012" =>
      "For types governed by automation/policies/authority.yaml (REQ-013): a transition to canonical must be by a human unless canonicalize.ai is allow. Any other non-human transition past creation, and any non-human Requirement acceptance, needs the type's specify policy (accept, for Requirement) to give ai allow or a condition; under a condition every parent (Function: enables, Mechanism: realizes, Requirement: derived_from) must currently be specified or canonical. The check and trace part of the condition is enforced by running those checks, not by this rule. Manifest canonical_foundation entries must reference canonical artifacts of the matching type.",
    "I-013" =>
      "Every ImplementationElement created by an AI Actor names an existing WorkItem that states its authority, and every path the element declares is within that WorkItem's allowed_files.",
    "I-014" =>
      "A supported Claim at level #{Enum.join(@higher_claim_levels, "/")} has at least one supporting Evidence whose kind is not #{Enum.join(@lower_evidence_kinds, "/")}.",
    "I-015" =>
      "States come from the applicable machine, and every history transition is legal in the semantic machine (creation is null -> proposed).",
    "I-016" =>
      "Against git HEAD: no committed artifact has been deleted, committed history is a prefix of current history, and a committed canonical artifact's statement is unchanged. Indeterminate without git history.",
    "I-017" => "Every Change or ChangeEvent carries a non-empty impact_analysis.",
    "I-018" =>
      "A supported Claim has no dependency in an unsettled state and no supporting Evidence that is not valid or is stale/inapplicable.",
    "I-019" =>
      "Every open or in-progress WorkItem records canonical_inputs as {path, sha256}, and each hash matches the current file.",
    "I-020" =>
      "Every artifact has provenance naming an existing Actor (created_by) and non-empty inputs."
  }

  def interpretations, do: @interpretations
  def defined?(id), do: Map.has_key?(@interpretations, id)

  # ---------------------------------------------------------------------------
  # Rules

  def rule("I-001", s) do
    format =
      for a <- s.artifacts, not (is_binary(a["id"]) and a["id"] =~ @id_format),
          do: "#{a["__file"]}: invalid id #{inspect(a["id"])}"

    duplicates =
      for {id, n} <- Enum.frequencies_by(s.artifacts, & &1["id"]), n > 1,
          do: "id #{id} is defined #{n} times"

    retyped =
      for a <- s.artifacts, old = baseline_artifact(s, a["id"]), old["type"] != a["type"],
          do: "#{a["id"]}: type changed from #{old["type"]} (HEAD) to #{a["type"]}"

    result(length(s.artifacts), format ++ duplicates ++ retyped)
  end

  def rule("I-002", s) do
    errors =
      for a <- s.artifacts, a["type"] not in s.types,
          do: "#{a["id"]}: unknown artifact type #{inspect(a["type"])}"

    result(length(s.artifacts), errors)
  end

  def rule("I-003", s) do
    pairs = for a <- s.artifacts, r <- rels(a), do: {a, r}
    errors = for {a, r} <- pairs, err = relationship_error(s, a, r), do: err
    result(length(pairs), errors)
  end

  def rule("I-004", s) do
    edges =
      for a <- s.artifacts, r <- rels(a), r["type"] in @hierarchy, reduce: %{} do
        acc -> Map.update(acc, a["id"], [r["to"]], &[r["to"] | &1])
      end

    errors = for id <- Map.keys(edges), reaches?(edges, id, id), do: "#{id} is on a hierarchy cycle"
    result(map_size(edges), errors)
  end

  def rule("I-005", s) do
    reqs = of_type(s, "Requirement") |> Enum.filter(&(&1["state"] in ~w(specified canonical)))

    errors =
      Enum.flat_map(reqs, fn r ->
        targets = targets(r, "derived_from")

        cond do
          targets == [] ->
            ["#{r["id"]}: #{r["state"]} Requirement has no derived_from justification"]

          r["state"] == "canonical" ->
            for t <- targets, st = get_in(s.by_id, [t, "state"]), st in ["proposed" | @unsettled_states],
                do: "#{r["id"]}: canonical Requirement is justified by #{t}, which is #{st}"

          true ->
            []
        end
      end)

    result(length(reqs), errors)
  end

  def rule("I-006", s) do
    ies = of_type(s, "ImplementationElement")

    errors =
      for ie <- ies,
          not (has_target_of_type?(s, ie, "implements", "Mechanism") or
                 has_target_of_type?(s, ie, "satisfies", "Requirement")),
          do: "#{ie["id"]}: neither implements a Mechanism nor satisfies a Requirement"

    result(length(ies), errors)
  end

  def rule("I-007", s) do
    reqs =
      of_type(s, "Requirement")
      |> Enum.filter(&(&1["state"] == "canonical" or &1["accepted_by"] != nil))

    mechs = of_type(s, "Mechanism") |> Enum.filter(&(&1["state"] == "canonical"))

    req_errors =
      for r <- reqs, r["disposition"] == nil, not realized_by?(s, r["id"], "satisfies"),
          do: "#{r["id"]}: accepted Requirement has no satisfying ImplementationElement and no disposition"

    mech_errors =
      for m <- mechs, m["disposition"] == nil, not realized_by?(s, m["id"], "implements"),
          do: "#{m["id"]}: canonical Mechanism has no implementing ImplementationElement and no disposition"

    result(length(reqs) + length(mechs), req_errors ++ mech_errors)
  end

  def rule("I-008", s) do
    evidence = of_type(s, "Evidence")

    errors =
      Enum.flat_map(evidence, fn e ->
        bound = targets(e, "supports") ++ targets(e, "contradicts")
        proposed = List.wrap(e["proposed_bindings"])

        cond do
          e["stage"] == "candidate" and bound != [] ->
            ["#{e["id"]}: candidate Evidence may not use supports/contradicts before qualification"]

          e["stage"] == "candidate" and proposed == [] ->
            ["#{e["id"]}: candidate Evidence has no proposed_bindings"]

          e["stage"] != "candidate" and bound == [] ->
            ["#{e["id"]}: Evidence is not bound to any Claim by supports/contradicts"]

          true ->
            for c <- proposed, get_in(s.by_id, [c, "type"]) != "Claim",
                do: "#{e["id"]}: proposed binding #{c} is not an existing Claim"
        end
      end)

    result(length(evidence), errors)
  end

  def rule("I-009", s) do
    runtime = of_type(s, "Evidence") |> Enum.filter(&(&1["kind"] == "runtime_observation"))

    errors =
      for e <- runtime,
          targets(e, "supports") ++ targets(e, "contradicts") != [],
          e["stage"] != "qualified" or not is_map(e["qualification"]),
          do: "#{e["id"]}: runtime observation bound to a Claim without qualification"

    result(length(runtime), errors)
  end

  def rule("I-010", s) do
    evidence = of_type(s, "Evidence")
    %{"integrity" => integrity, "applicability" => applicability} = s.machines["evidence"]

    errors =
      Enum.flat_map(evidence, fn e ->
        [
          e["integrity"] not in integrity &&
            "#{e["id"]}: integrity #{inspect(e["integrity"])} is not one of #{inspect(integrity)}",
          e["applicability"] not in applicability &&
            "#{e["id"]}: applicability #{inspect(e["applicability"])} is not one of #{inspect(applicability)}"
        ]
        |> Enum.filter(& &1)
      end)

    result(length(evidence), errors)
  end

  def rule("I-011", s) do
    governed =
      Enum.filter(s.artifacts, fn a ->
        state_machine(a) != nil and a["state"] not in [nil, "proposed"]
      end)

    errors =
      Enum.flat_map(governed, fn a ->
        history = List.wrap(a["history"])
        last = List.last(history)

        cond do
          history == [] ->
            ["#{a["id"]}: state #{a["state"]} has no transition history"]

          last["to"] != a["state"] ->
            ["#{a["id"]}: history ends at #{inspect(last["to"])} but state is #{a["state"]}"]

          true ->
            for h <- history, h["from"] != nil, err = transition_authority_error(s, a, h), do: err
        end
      end)

    result(length(governed), errors)
  end

  def rule("I-012", s) do
    governed_types =
      for {type, p} <- s.policies, Enum.any?(~w(canonicalize specify accept), &Map.has_key?(p, &1)),
          do: type

    subjects = Enum.filter(s.artifacts, &(&1["type"] in governed_types))

    transition_errors =
      for a <- subjects, h <- List.wrap(a["history"]), h["from"] != nil,
          actor_kind(s, h["by"]) != "human",
          err <- delegated_transition_errors(s, a, h["to"], "#{h["from"]} -> #{h["to"]} performed by non-human #{inspect(h["by"])}"),
          do: err

    acceptance_errors =
      for a <- subjects, a["type"] == "Requirement",
          by = get_in(a, ["accepted_by", "actor"]),
          actor_kind(s, by) != "human",
          err <- delegated_transition_errors(s, a, "specified", "accepted by non-human #{inspect(by)}"),
          do: err

    transition_errors = transition_errors ++ acceptance_errors

    foundation = (s.manifest || %{})["canonical_foundation"] || %{}

    manifest_errors =
      for {key, ref} <- foundation, ref != nil, err = manifest_reference_error(s, key, ref),
          do: err

    result(length(subjects) + map_size(foundation), transition_errors ++ manifest_errors)
  end

  def rule("I-013", s) do
    ai_ies =
      of_type(s, "ImplementationElement")
      |> Enum.filter(&(actor_kind(s, get_in(&1, ["provenance", "created_by"])) == "ai_agent"))

    errors =
      Enum.flat_map(ai_ies, fn ie ->
        wi = s.by_id[ie["work_item"]]

        cond do
          wi == nil or wi["type"] != "WorkItem" ->
            ["#{ie["id"]}: AI-created element names no existing WorkItem (#{inspect(ie["work_item"])})"]

          blank?(wi["authority"]) ->
            ["#{ie["id"]}: WorkItem #{wi["id"]} states no authority"]

          true ->
            allowed = List.wrap(wi["allowed_files"])

            for path <- List.wrap(ie["paths"]), not Enum.any?(allowed, &glob_match?(&1, path)),
                do: "#{ie["id"]}: #{path} is outside #{wi["id"]} allowed_files"
        end
      end)

    result(length(ai_ies), errors)
  end

  def rule("I-014", s) do
    claims =
      of_type(s, "Claim")
      |> Enum.filter(&(&1["state"] == "supported" and &1["level"] in @higher_claim_levels))

    errors =
      for c <- claims,
          kinds = supporting_evidence(s, c["id"]) |> Enum.map(& &1["kind"]),
          Enum.all?(kinds, &(&1 in @lower_evidence_kinds)),
          do: "#{c["id"]}: #{c["level"]}-level Claim is supported only by #{inspect(Enum.uniq(kinds))} evidence"

    result(length(claims), errors)
  end

  def rule("I-015", s) do
    semantic = s.machines["semantic"]
    subjects = Enum.filter(s.artifacts, &(state_machine(&1) != nil))

    errors =
      Enum.flat_map(subjects, fn a ->
        states = if state_machine(a) == :claim, do: s.machines["claim"]["states"], else: semantic["states"]

        state_error =
          if a["state"] != nil and a["state"] not in states,
            do: ["#{a["id"]}: state #{inspect(a["state"])} is not in its state machine"],
            else: []

        transition_errors =
          if state_machine(a) == :semantic do
            for h <- List.wrap(a["history"]), not legal_transition?(semantic, h["from"], h["to"]),
                do: "#{a["id"]}: illegal transition #{inspect(h["from"])} -> #{inspect(h["to"])}"
          else
            []
          end

        state_error ++ transition_errors
      end)

    result(length(subjects), errors)
  end

  def rule("I-016", %{baseline: nil}),
    do: {:indeterminate, 0, ["no git history available at HEAD; historical preservation not evaluable"]}

  def rule("I-016", s) do
    committed = s.baseline.artifacts

    errors =
      Enum.flat_map(committed, fn old ->
        case s.by_id[old["id"]] do
          nil ->
            ["#{old["id"]}: committed at HEAD but no longer present"]

          new ->
            old_history = List.wrap(old["history"])

            [
              Enum.take(List.wrap(new["history"]), length(old_history)) != old_history &&
                "#{old["id"]}: committed history was rewritten",
              old["state"] == "canonical" and new["statement"] != old["statement"] &&
                "#{old["id"]}: statement of a canonical artifact changed without supersession"
            ]
            |> Enum.filter(& &1)
        end
      end)

    result(length(committed), errors)
  end

  def rule("I-017", s) do
    changes = Enum.filter(s.artifacts, &(&1["type"] in ~w(Change ChangeEvent)))

    errors =
      for c <- changes, blank?(c["impact_analysis"]),
          do: "#{c["id"]}: #{c["type"]} has no impact_analysis"

    result(length(changes), errors)
  end

  def rule("I-018", s) do
    claims = of_type(s, "Claim") |> Enum.filter(&(&1["state"] == "supported"))

    errors =
      Enum.flat_map(claims, fn c ->
        deps =
          for t <- targets(c, "depends_on"), st = get_in(s.by_id, [t, "state"]), st in @unsettled_states,
              do: "#{c["id"]}: depends on #{t}, which is #{st}; reassessment required"

        ev =
          for e <- supporting_evidence(s, c["id"]),
              e["integrity"] != "valid" or e["applicability"] in ~w(stale inapplicable),
              do: "#{c["id"]}: supporting #{e["id"]} is #{e["integrity"]}/#{e["applicability"]}; reassessment required"

        deps ++ ev
      end)

    result(length(claims), errors)
  end

  def rule("I-019", s) do
    open = of_type(s, "WorkItem") |> Enum.filter(&(&1["status"] in ~w(open in_progress)))

    errors =
      Enum.flat_map(open, fn wi ->
        case wi["canonical_inputs"] do
          inputs when is_list(inputs) and inputs != [] ->
            Enum.flat_map(inputs, fn
              %{"path" => path, "sha256" => expected} ->
                actual = sha256(s.root, path)

                if actual == expected,
                  do: [],
                  else: ["#{wi["id"]}: canonical input #{path} changed (#{short(expected)} -> #{short(actual)})"]

              other ->
                ["#{wi["id"]}: malformed canonical input #{inspect(other)}"]
            end)

          _ ->
            ["#{wi["id"]}: open WorkItem records no canonical_inputs; staleness cannot be detected"]
        end
      end)

    result(length(open), errors)
  end

  def rule("I-020", s) do
    errors =
      for a <- s.artifacts, err = provenance_error(s, a), do: err

    result(length(s.artifacts), errors)
  end

  # ---------------------------------------------------------------------------
  # Helpers

  defp result(n, []), do: {:pass, n, []}
  defp result(n, errors), do: {:fail, n, errors}

  defp rels(a), do: List.wrap(a["relationships"])
  defp targets(a, type), do: for(%{"type" => ^type, "to" => to} <- rels(a), do: to)
  defp of_type(s, type), do: Enum.filter(s.artifacts, &(&1["type"] == type))
  defp blank?(v), do: v in [nil, "", [], %{}]
  defp actor_kind(s, id), do: get_in(s.by_id, [id, "kind"])

  defp baseline_artifact(%Store{baseline: nil}, _), do: nil
  defp baseline_artifact(%Store{baseline: b}, id), do: b.by_id[id]

  defp relationship_error(s, a, r) do
    spec = is_map(r) && s.relationships[r["type"]]
    target = is_map(r) && s.by_id[r["to"]]

    cond do
      not is_map(r) -> "#{a["id"]}: malformed relationship #{inspect(r)}"
      spec in [nil, false] -> "#{a["id"]}: unknown relationship type #{inspect(r["type"])}"
      target == nil -> "#{a["id"]} -#{r["type"]}-> #{r["to"]}: target does not exist"
      not allowed?(spec["from"], a["type"]) -> "#{a["id"]}: #{a["type"]} may not be the source of #{r["type"]}"
      not allowed?(spec["to"], target["type"]) -> "#{a["id"]}: #{target["type"]} may not be the target of #{r["type"]}"
      true -> nil
    end
  end

  defp allowed?(types, type), do: "*" in types or type in types

  defp reaches?(edges, from, goal, seen \\ MapSet.new()) do
    Enum.any?(Map.get(edges, from, []), fn next ->
      next == goal or (next not in seen and reaches?(edges, next, goal, MapSet.put(seen, next)))
    end)
  end

  defp has_target_of_type?(s, a, rel, type),
    do: Enum.any?(targets(a, rel), &(get_in(s.by_id, [&1, "type"]) == type))

  defp realized_by?(s, id, rel),
    do: Enum.any?(of_type(s, "ImplementationElement"), &(id in targets(&1, rel)))

  defp supporting_evidence(s, claim_id),
    do: Enum.filter(of_type(s, "Evidence"), &(claim_id in targets(&1, "supports")))

  defp state_machine(%{"type" => "Claim"}), do: :claim
  defp state_machine(%{"type" => t}) when t in @semantic_machine_types, do: :semantic
  defp state_machine(_), do: nil

  defp legal_transition?(_machine, nil, "proposed"), do: true
  defp legal_transition?(machine, from, to), do: to in List.wrap(machine["transitions"][from])

  defp transition_authority_error(s, a, h) do
    cond do
      get_in(s.by_id, [h["by"], "type"]) != "Actor" ->
        "#{a["id"]}: transition #{h["from"]} -> #{h["to"]} names no existing Actor (#{inspect(h["by"])})"

      blank?(h["authority"]) ->
        "#{a["id"]}: transition #{h["from"]} -> #{h["to"]} states no authority"

      true ->
        nil
    end
  end

  # REQ-013: a non-human transition is legitimate only where authority.yaml delegates it.
  defp delegated_transition_errors(s, a, to, what) do
    policy = s.policies[a["type"]]
    key = if a["type"] == "Requirement", do: "accept", else: "specify"
    permission = get_in(policy, [key, "ai"])

    cond do
      to == "canonical" ->
        if get_in(policy, ["canonicalize", "ai"]) == "allow",
          do: [],
          else: ["#{a["id"]}: #{what}; canonicalization requires a human"]

      permission == "allow" ->
        []

      is_map(permission) and permission["condition"] != nil ->
        parent_errors(s, a, what)

      true ->
        ["#{a["id"]}: #{what}; policy does not delegate '#{key}' to AI"]
    end
  end

  defp parent_errors(s, a, what) do
    parents = targets(a, @parent_relationship[a["type"]])

    if parents == [] do
      ["#{a["id"]}: #{what} under a delegated condition, but it has no parent"]
    else
      for p <- parents, st = get_in(s.by_id, [p, "state"]), st not in ~w(specified canonical),
          do: "#{a["id"]}: #{what} under a delegated condition, but parent #{p} is #{st}"
    end
  end

  defp manifest_reference_error(s, key, ref) do
    expected = key |> to_string() |> Macro.camelize()
    a = s.by_id[ref]

    cond do
      not is_binary(ref) -> "manifest canonical_foundation.#{key} is not an artifact reference: #{inspect(ref)}"
      a == nil -> "manifest canonical_foundation.#{key} references missing #{ref}"
      a["type"] != expected -> "manifest canonical_foundation.#{key} references #{ref}, a #{a["type"]}"
      a["state"] != "canonical" -> "manifest canonical_foundation.#{key} references #{ref}, which is #{a["state"]}"
      true -> nil
    end
  end

  defp provenance_error(s, a) do
    p = a["provenance"]

    cond do
      not is_map(p) -> "#{a["id"]}: no provenance"
      get_in(s.by_id, [p["created_by"], "type"]) != "Actor" -> "#{a["id"]}: provenance.created_by is not an existing Actor"
      blank?(p["inputs"]) -> "#{a["id"]}: provenance.inputs is empty"
      true -> nil
    end
  end

  @doc false
  def glob_match?(pattern, path) do
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", "\u0000")
      |> String.replace("\\*", "[^/]*")
      |> String.replace("\u0000", ".*")

    Regex.match?(~r/^#{regex}$/, path)
  end

  defp sha256(root, rel) do
    case File.read(Path.join(root, rel)) do
      {:ok, bytes} -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      {:error, reason} -> "missing(#{reason})"
    end
  end

  defp short(hash), do: String.slice(hash, 0, 12)
end
