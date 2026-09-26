defmodule RI01.AssuranceAuthorityTest do
  @moduledoc "REQ-014 (supersession) and REQ-015 (evidence and assessment authority, CP-004 option B)."
  use ExUnit.Case, async: true

  import RI01.Fixture

  defp qualified(e, by, extra \\ %{}) do
    e
    |> Map.merge(%{"stage" => "qualified", "integrity" => "valid", "kind" => "test", "relationships" => [rel("supports", "CLM-001")]})
    |> Map.delete("proposed_bindings")
    |> Map.put("qualification", Map.merge(%{"by" => by, "reproduction" => %{"commit" => "abc123", "command" => "mix test"}}, extra))
  end

  defp i012(store), do: outcome(check(store), "I-012")

  defp assessment(by, claim),
    do: %{"id" => "ASMT-001", "type" => "Assessment", "relationships" => [rel("assesses", claim)], "provenance" => %{"created_by" => by, "inputs" => ["x"]}}

  describe "REQ-015 (a)/(b) qualification" do
    test "AI may qualify reproducible test Evidence" do
      assert {:pass, _, []} = i012(update(valid_store(), "EVC-001", &qualified(&1, "ACT-002")))
    end

    test "valid integrity without a qualification record fails" do
      store = update(valid_store(), "EVC-001", &Map.put(&1, "integrity", "valid"))
      assert {:fail, _, [msg]} = i012(store)
      assert msg =~ "no qualification"
    end

    test "AI may not qualify analysis Evidence" do
      store = update(valid_store(), "EVC-001", &(qualified(&1, "ACT-002") |> Map.put("kind", "analysis")))
      assert {:fail, _, [msg]} = i012(store)
      assert msg =~ "only test or deterministic_check"
    end

    test "AI qualification needs a reproduction" do
      store = update(valid_store(), "EVC-001", &qualified(&1, "ACT-002", %{"reproduction" => %{"commit" => "abc123"}}))
      assert {:fail, _, [msg]} = i012(store)
      assert msg =~ "without a reproduction"
    end

    test "a human may qualify any kind of Evidence" do
      store = update(valid_store(), "EVC-001", &(qualified(&1, "ACT-001", %{"reproduction" => nil}) |> Map.put("kind", "analysis")))
      assert {:pass, _, []} = i012(store)
    end
  end

  describe "REQ-015 (c)/(d) assessment" do
    test "a supported Claim needs an Assessment" do
      store = update(valid_store(), "CLM-001", &Map.merge(&1, %{"state" => "supported", "level" => "implementation"}))
      assert {:fail, _, [msg]} = i012(store)
      assert msg =~ "supported without an Assessment"

      assert {:pass, _, []} = i012(add(store, "project/a.yaml", assessment("ACT-002", "CLM-001")))
    end

    test "AI may assess only implementation-level Claims; a missing level counts as not implementation" do
      for level <- ["capability", nil] do
        store =
          valid_store()
          |> update("CLM-001", &Map.merge(&1, %{"state" => "supported", "level" => level}))
          |> add("project/a.yaml", assessment("ACT-002", "CLM-001"))

        assert {:fail, _, [msg]} = i012(store)
        assert msg =~ "non-human Assessment"
      end
    end

    test "a human may assess a Claim at any level" do
      store =
        valid_store()
        |> update("CLM-001", &Map.merge(&1, %{"state" => "supported", "level" => "outcome"}))
        |> add("project/a.yaml", assessment("ACT-001", "CLM-001"))

      assert {:pass, _, []} = i012(store)
    end
  end

  describe "REQ-014 supersession" do
    defp superseded_req do
      valid_store()
      |> update("REQ-001", &Map.merge(&1, %{"state" => "superseded", "history" => specified_history() ++ [h("specified", "superseded", "ACT-001")]}))
      |> update("IE-001", &Map.put(&1, "relationships", [rel("satisfies", "REQ-002")]))
      |> add("project/realization/realization.yaml", %{
        "id" => "REQ-002",
        "type" => "Requirement",
        "state" => "specified",
        "accepted_by" => %{"actor" => "ACT-001"},
        "history" => specified_history(),
        "relationships" => [rel("derived_from", "CON-001"), rel("supersedes", "REQ-001")],
        "provenance" => prov()
      })
    end

    test "a superseded Requirement carries no realization obligation" do
      c = check(superseded_req())
      assert {:pass, _, []} = outcome(c, "I-007")
      refute Map.has_key?(Map.new(RI01.Trace.run(write(superseded_req())).downward), "REQ-001")
    end

    test "a superseded artifact must have a successor" do
      store = update(superseded_req(), "REQ-002", &Map.put(&1, "relationships", [rel("derived_from", "CON-001")]))
      assert {:fail, _, msgs} = outcome(check(store), "I-015")
      assert Enum.any?(msgs, &(&1 =~ "REQ-001: superseded, but no artifact supersedes it"))
    end

    test "a superseded artifact on an upward path is still a defect" do
      store =
        superseded_req()
        |> update("CON-001", &Map.merge(&1, %{"state" => "specified", "sources" => ["CONSTITUTION.md"], "history" => specified_history()}))
        |> update("IE-001", &Map.put(&1, "relationships", [rel("satisfies", "REQ-001")]))

      assert {:fail, msgs} = RI01.Trace.run(write(store)).upward |> Map.new() |> Map.fetch!("IE-001")
      assert Enum.any?(msgs, &(&1 =~ "REQ-001: on path but superseded"))
    end
  end
end

defmodule RI01.SupersessionJustificationTest do
  @moduledoc "REQ-016: historical delegation condition, and re-justification after supersession."
  use ExUnit.Case, async: true

  import RI01.Fixture

  defp ai_specified, do: [h(nil, "proposed", "ACT-002"), h("proposed", "coherent", "ACT-002", "CP-002"), h("coherent", "specified", "ACT-002", "CP-002")]

  # REQ-001 accepted by AI under delegation from MEC-009; MEC-009 later superseded by MEC-010.
  defp store(mec009_superseded?, req_parents) do
    mec9_history = specified_history() ++ if(mec009_superseded?, do: [h("specified", "superseded", "ACT-001")], else: [])

    valid_store()
    |> add("project/m.yaml", %{"id" => "MEC-009", "type" => "Mechanism", "state" => if(mec009_superseded?, do: "superseded", else: "specified"), "history" => mec9_history, "provenance" => prov()})
    |> add("project/m.yaml", %{"id" => "MEC-010", "type" => "Mechanism", "state" => "specified", "history" => specified_history(), "relationships" => [rel("supersedes", "MEC-009")], "provenance" => prov()})
    |> update("REQ-001", &Map.merge(&1, %{"accepted_by" => %{"actor" => "ACT-002"}, "history" => ai_specified(), "relationships" => Enum.map(req_parents, fn p -> rel("derived_from", p) end)}))
  end

  test "(a) a parent superseded later does not invalidate an earlier delegated transition" do
    assert {:pass, _, []} = outcome(check(store(true, ["MEC-009", "MEC-010"])), "I-012")
  end

  test "(a) a parent that never reached specified still fails" do
    s = store(false, ["MEC-009"]) |> update("MEC-009", &Map.merge(&1, %{"state" => "proposed", "history" => [h(nil, "proposed", "ACT-002")]}))
    assert {:fail, _, [_ | _]} = outcome(check(s), "I-012")
  end

  test "(b) a Requirement justified only by superseded artifacts must be re-justified" do
    assert {:fail, _, [msg]} = outcome(check(store(true, ["MEC-009"])), "I-005")
    assert msg =~ "re-justify"
    assert {:pass, _, []} = outcome(check(store(true, ["MEC-009", "MEC-010"])), "I-005")
  end
end
