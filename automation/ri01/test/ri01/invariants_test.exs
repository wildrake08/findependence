defmodule RI01.InvariantsTest do
  use ExUnit.Case, async: true

  import RI01.Fixture

  @ids for i <- 1..20, do: "I-" <> String.pad_leading("#{i}", 3, "0")

  defp fails(store, id, pattern, opts \\ []) do
    assert {:fail, _, messages} = outcome(check(store, opts), id)
    assert Enum.any?(messages, &(&1 =~ pattern)), "expected #{inspect(pattern)} in #{inspect(messages)}"
  end

  describe "valid store" do
    test "every invariant passes and the overall result is pass" do
      c = check(valid_store(), git: true)
      assert c.store_outcome == :pass

      for {inv, result} <- c.results,
          do: assert(match?({:pass, _, []}, result), "#{inv["id"]}: #{inspect(result)}")

      assert c.overall == :pass
      assert Enum.map(c.results, fn {inv, _} -> inv["id"] end) == @ids
    end

    test "without git history I-016 and the overall result are indeterminate, never pass" do
      c = check(valid_store())
      assert {:indeterminate, 0, _} = outcome(c, "I-016")
      assert c.overall == :indeterminate
      assert RI01.Check.exit_code(c.overall) == 3
    end

    test "every core.yaml invariant has a documented interpretation (REQ-005)" do
      for id <- @ids, do: assert(RI01.Invariants.defined?(id), id)
    end
  end

  describe "store (REQ-006)" do
    test "unparsable YAML fails the store load and the overall result" do
      root = write(valid_store())
      File.write!(Path.join(root, "project/semantic/broken.yaml"), "a: [unclosed")
      c = RI01.Check.run(root)
      assert c.store_outcome == :fail
      assert c.overall == :fail
    end

    test "a YAML file without an artifacts list fails the store load" do
      root = write(valid_store())
      File.write!(Path.join(root, "project/semantic/loose.yaml"), "id: X-001\n")
      assert RI01.Check.run(root).store_outcome == :fail
    end
  end

  describe "REQ-003" do
    test "an invariant with no rule is indeterminate" do
      assert {:indeterminate, 0, [msg]} =
               RI01.Check.evaluate(%{"id" => "I-999", "deterministic" => true}, nil)

      assert msg =~ "no rule"
    end

    test "an invariant not declared deterministic is indeterminate" do
      assert {:indeterminate, 0, _} = RI01.Check.evaluate(%{"id" => "I-001"}, nil)
    end

    test "a rule that raises is indeterminate" do
      assert {:indeterminate, 0, [msg]} =
               RI01.Check.evaluate(%{"id" => "I-001", "deterministic" => true}, %{artifacts: :bad})

      assert msg =~ "raised"
    end
  end

  test "I-001 duplicate and malformed ids" do
    fails(add(valid_store(), "project/x.yaml", %{"id" => "ACT-001", "type" => "Actor", "provenance" => prov()}), "I-001", "defined 2 times")
    fails(update(valid_store(), "CLM-001", &Map.put(&1, "id", "claim1")), "I-001", "invalid id")
  end

  test "I-001 id retyped relative to HEAD" do
    root = write(valid_store(), git: true)
    rewrite(root, update(valid_store(), "CON-001", &Map.put(&1, "type", "Principle")))
    assert {:fail, _, [msg]} = outcome(RI01.Check.run(root), "I-001")
    assert msg =~ "type changed"
  end

  test "I-002 unknown type" do
    fails(update(valid_store(), "CON-001", &Map.put(&1, "type", "Widget")), "I-002", "unknown artifact type")
  end

  test "I-003 typing and dangling targets" do
    fails(update(valid_store(), "TEL-001", &Map.put(&1, "relationships", [rel("concerns", "CON-001")])), "I-003", "may not be the target")
    fails(update(valid_store(), "TEL-001", &Map.put(&1, "relationships", [rel("concerns", "SUBJ-404")])), "I-003", "does not exist")
    fails(update(valid_store(), "TEL-001", &Map.put(&1, "relationships", [rel("inspires", "SUBJ-001")])), "I-003", "unknown relationship")
  end

  test "I-004 hierarchy cycle" do
    store =
      valid_store()
      |> add("project/x.yaml", %{"id" => "REQ-002", "type" => "Requirement", "relationships" => [rel("derived_from", "REQ-003")], "provenance" => prov()})
      |> add("project/x.yaml", %{"id" => "REQ-003", "type" => "Requirement", "relationships" => [rel("depends_on", "REQ-002")], "provenance" => prov()})

    assert {:pass, _, _} = outcome(check(store), "I-004")

    store = update(store, "REQ-003", &Map.put(&1, "relationships", [rel("derived_from", "REQ-002")]))
    fails(store, "I-004", "cycle")
  end

  test "I-005 accepted Requirement without justification; canonical justified by proposed" do
    fails(update(valid_store(), "REQ-001", &Map.delete(&1, "relationships")), "I-005", "no derived_from")

    canonical =
      update(valid_store(), "REQ-001", fn r ->
        Map.merge(r, %{"state" => "canonical", "history" => specified_history() ++ [h("specified", "canonical", "ACT-001")]})
      end)

    fails(canonical, "I-005", "CON-001, which is proposed")
  end

  test "I-006 orphan implementation" do
    fails(update(valid_store(), "IE-001", &Map.delete(&1, "relationships")), "I-006", "neither implements")
  end

  test "I-007 realization gap and explicit disposition" do
    gap = update(valid_store(), "IE-001", &Map.delete(&1, "relationships"))
    fails(gap, "I-007", "REQ-001")

    disposed = update(gap, "REQ-001", &Map.put(&1, "disposition", "deferred"))
    assert {:pass, _, _} = outcome(check(disposed), "I-007")
  end

  test "I-008 unbound, prematurely bound, and mis-bound evidence" do
    fails(update(valid_store(), "EVC-001", &Map.delete(&1, "proposed_bindings")), "I-008", "no proposed_bindings")
    fails(update(valid_store(), "EVC-001", &Map.put(&1, "relationships", [rel("supports", "CLM-001")])), "I-008", "before qualification")
    fails(update(valid_store(), "EVC-001", &Map.put(&1, "proposed_bindings", ["CON-001"])), "I-008", "not an existing Claim")
    fails(update(valid_store(), "EVC-001", &Map.put(&1, "stage", "qualified")), "I-008", "not bound")
  end

  test "I-009 runtime observation must be qualified before binding" do
    runtime = fn e ->
      Map.merge(e, %{"kind" => "runtime_observation", "stage" => "observed", "relationships" => [rel("supports", "CLM-001")]})
    end

    fails(update(valid_store(), "EVC-001", runtime), "I-009", "without qualification")

    qualified = update(valid_store(), "EVC-001", &(runtime.(&1) |> Map.merge(%{"stage" => "qualified", "qualification" => %{"by" => "ACT-001"}})))
    assert {:pass, 1, _} = outcome(check(qualified), "I-009")
  end

  test "I-010 integrity and applicability from their own enumerations" do
    fails(update(valid_store(), "EVC-001", &Map.put(&1, "integrity", "stale")), "I-010", "integrity")
    fails(update(valid_store(), "EVC-001", &Map.delete(&1, "applicability")), "I-010", "applicability")
  end

  test "I-011 governed transitions need history, actor, and authority" do
    fails(update(valid_store(), "TEL-001", &Map.delete(&1, "history")), "I-011", "no transition history")
    fails(update(valid_store(), "TEL-001", &Map.put(&1, "state", "canonical")), "I-011", "history ends at")

    no_authority = [h(nil, "proposed", "ACT-002"), h("proposed", "coherent", "ACT-001", nil), h("coherent", "specified", "ACT-001")]
    fails(update(valid_store(), "TEL-001", &Map.put(&1, "history", no_authority)), "I-011", "states no authority")

    ghost = [h(nil, "proposed", "ACT-002"), h("proposed", "coherent", "ACT-404"), h("coherent", "specified", "ACT-001")]
    fails(update(valid_store(), "TEL-001", &Map.put(&1, "history", ghost)), "I-011", "names no existing Actor")
  end

  test "I-012 AI may not transition ratification-governed artifacts" do
    ai = [h(nil, "proposed", "ACT-002"), h("proposed", "coherent", "ACT-002"), h("coherent", "specified", "ACT-001")]
    fails(update(valid_store(), "TEL-001", &Map.put(&1, "history", ai)), "I-012", "non-human")
  end

  test "I-012 manifest canonical_foundation must reference a canonical artifact" do
    fails(valid_store(), "I-012", "which is specified", canonical_foundation: %{"telos" => "TEL-001"})
    fails(valid_store(), "I-012", "a Subject", canonical_foundation: %{"telos" => "SUBJ-001"})
  end

  test "I-013 AI implementation needs a WorkItem and stays inside allowed files" do
    fails(update(valid_store(), "IE-001", &Map.delete(&1, "work_item")), "I-013", "no existing WorkItem")
    fails(update(valid_store(), "IE-001", &Map.put(&1, "paths", ["framework/x.yaml"])), "I-013", "outside WI-001")
    fails(update(valid_store(), "WI-001", &Map.delete(&1, "authority")), "I-013", "states no authority")
  end

  test "glob matching" do
    assert RI01.Invariants.glob_match?("src/**", "src/a/b.ex")
    assert RI01.Invariants.glob_match?("scripts/check", "scripts/check")
    refute RI01.Invariants.glob_match?("src/*", "src/a/b.ex")
    refute RI01.Invariants.glob_match?("scripts/check", "scripts/checkX")
  end

  test "I-014 higher-level claim supported only by tests" do
    store =
      valid_store()
      |> update("CLM-001", &Map.merge(&1, %{"state" => "supported", "level" => "capability"}))
      |> update("EVC-001", &Map.merge(&1, %{"stage" => "qualified", "kind" => "test", "integrity" => "valid", "relationships" => [rel("supports", "CLM-001")]}))
      |> update("EVC-001", &Map.delete(&1, "proposed_bindings"))

    fails(store, "I-014", "capability-level")

    field = update(store, "EVC-001", &Map.put(&1, "kind", "field_study"))
    assert {:pass, 1, _} = outcome(check(field), "I-014")
  end

  test "I-015 illegal state and transition" do
    fails(update(valid_store(), "SUBJ-001", &Map.put(&1, "state", "approved")), "I-015", "not in its state machine")

    skip = [h(nil, "proposed", "ACT-002"), h("proposed", "specified", "ACT-001")]
    fails(update(valid_store(), "TEL-001", &Map.put(&1, "history", skip)), "I-015", "illegal transition")
  end

  test "I-016 deletion and history rewrite relative to HEAD" do
    root = write(valid_store(), git: true)
    rewrite(root, Map.update!(valid_store(), "project/semantic/foundation.yaml", &Enum.reject(&1, fn a -> a["id"] == "CON-001" end)))
    fails_root(root, "I-016", "no longer present")

    root = write(valid_store(), git: true)
    rewritten = [h(nil, "proposed", "ACT-001"), h("proposed", "coherent", "ACT-001"), h("coherent", "specified", "ACT-001")]
    rewrite(root, update(valid_store(), "TEL-001", &Map.put(&1, "history", rewritten)))
    fails_root(root, "I-016", "history was rewritten")
  end

  test "I-016 canonical statement change" do
    canonical = fn a -> Map.merge(a, %{"state" => "canonical", "history" => specified_history() ++ [h("specified", "canonical", "ACT-001")]}) end
    store = update(valid_store(), "TEL-001", canonical)
    root = write(store, git: true)
    rewrite(root, update(store, "TEL-001", &Map.put(&1, "statement", "changed")))
    fails_root(root, "I-016", "without supersession")
  end

  test "I-017 change without impact analysis" do
    fails(update(valid_store(), "CHG-001", &Map.delete(&1, "impact_analysis")), "I-017", "no impact_analysis")
  end

  test "I-018 supported claim with weakened dependency or stale evidence" do
    supported =
      valid_store()
      |> update("CLM-001", &Map.merge(&1, %{"state" => "supported", "relationships" => [rel("depends_on", "CON-001")]}))
      |> update("EVC-001", &(&1 |> Map.merge(%{"stage" => "qualified", "integrity" => "valid", "relationships" => [rel("supports", "CLM-001")]}) |> Map.delete("proposed_bindings")))

    assert {:pass, 1, _} = outcome(check(supported), "I-018")
    fails(update(supported, "CON-001", &Map.merge(&1, %{"state" => "weakened"})), "I-018", "CON-001, which is weakened")
    fails(update(supported, "EVC-001", &Map.put(&1, "applicability", "stale")), "I-018", "valid/stale")
  end

  test "I-019 stale and unanchored work items" do
    fails(update(valid_store(), "WI-001", &Map.put(&1, "canonical_inputs", [%{"path" => "framework/invariants/core.yaml", "sha256" => "0000"}])), "I-019", "changed")
    fails(update(valid_store(), "WI-001", &Map.delete(&1, "canonical_inputs")), "I-019", "no canonical_inputs")
    fails(update(valid_store(), "WI-001", &Map.put(&1, "canonical_inputs", ["core.yaml"])), "I-019", "malformed")

    done = update(valid_store(), "WI-001", &Map.merge(&1, %{"status" => "completed", "canonical_inputs" => []}))
    assert {:pass, 0, _} = outcome(check(done), "I-019")
  end

  test "I-020 provenance" do
    fails(update(valid_store(), "CON-001", &Map.delete(&1, "provenance")), "I-020", "no provenance")
    fails(update(valid_store(), "CON-001", &Map.put(&1, "provenance", %{"created_by" => "ACT-002", "inputs" => []})), "I-020", "inputs is empty")
    fails(update(valid_store(), "CON-001", &Map.put(&1, "provenance", %{"created_by" => "someone", "inputs" => ["x"]})), "I-020", "not an existing Actor")
  end

  test "REQ-004: check leaves the repository unchanged" do
    root = write(valid_store(), git: true)
    before = System.cmd("git", ["-C", root, "status", "--porcelain", "--ignored"]) |> elem(0)
    RI01.Check.run(root)
    assert System.cmd("git", ["-C", root, "status", "--porcelain", "--ignored"]) |> elem(0) == before
  end

  defp fails_root(root, id, pattern) do
    assert {:fail, _, messages} = outcome(RI01.Check.run(root), id)
    assert Enum.any?(messages, &(&1 =~ pattern)), "expected #{inspect(pattern)} in #{inspect(messages)}"
  end
end
