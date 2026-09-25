defmodule RI01.TraceTest do
  use ExUnit.Case, async: true

  import RI01.Fixture

  # valid_store(): IE-001 -satisfies-> REQ-001 (accepted) -derived_from-> CON-001 (proposed).
  defp governance_rooted(store) do
    update(store, "CON-001", fn c ->
      Map.merge(c, %{"state" => "specified", "sources" => ["CONSTITUTION.md#x"], "history" => specified_history()})
    end)
  end

  defp trace(store), do: RI01.Trace.run(write(store))
  defp up(t, id), do: t.upward |> Map.new() |> Map.fetch!(id)
  defp down(t, id), do: t.downward |> Map.new() |> Map.fetch!(id)

  defp mechanism_chain do
    valid_store()
    |> add("project/s.yaml", %{"id" => "SUBJ-002", "type" => "Subject", "state" => "canonical", "provenance" => prov()})
    |> add("project/s.yaml", %{"id" => "TEL-002", "type" => "Telos", "state" => "canonical", "relationships" => [rel("concerns", "SUBJ-002")], "provenance" => prov()})
    |> add("project/s.yaml", %{"id" => "PUR-002", "type" => "Purpose", "state" => "canonical", "relationships" => [rel("advances", "TEL-002")], "provenance" => prov()})
    |> add("project/s.yaml", %{"id" => "CAP-001", "type" => "Capability", "state" => "canonical", "relationships" => [rel("contributes_to", "PUR-002")], "provenance" => prov()})
    |> add("project/s.yaml", %{"id" => "FUN-001", "type" => "Function", "state" => "canonical", "relationships" => [rel("enables", "CAP-001")], "provenance" => prov()})
    |> add("project/s.yaml", %{"id" => "MEC-001", "type" => "Mechanism", "state" => "canonical", "relationships" => [rel("realizes", "FUN-001")], "provenance" => prov()})
    |> update("IE-001", &Map.put(&1, "relationships", [rel("implements", "MEC-001")]))
    |> update("REQ-001", &Map.put(&1, "disposition", "not in scope of fixture"))
  end

  test "REQ-008: implementation rooted in the Subject through accepted artifacts passes" do
    t = trace(mechanism_chain())
    assert {:pass, [{path, :subject}]} = up(t, "IE-001")
    assert path == ~w(IE-001 MEC-001 FUN-001 CAP-001 PUR-002 TEL-002 SUBJ-002)
  end

  test "REQ-008: implementation rooted in governance passes and reports the root kind" do
    assert {:pass, [{~w(IE-001 REQ-001 CON-001), :governance}]} = up(trace(governance_rooted(valid_store())), "IE-001")
  end

  test "REQ-008: a proposed Constraint is not a governance root" do
    assert {:fail, [msg | _]} = up(trace(valid_store()), "IE-001")
    assert msg =~ "no upward path"
  end

  test "REQ-008: a path through a proposed or unsettled artifact fails" do
    store = update(mechanism_chain(), "FUN-001", &Map.put(&1, "state", "proposed"))
    assert {:fail, msgs} = up(trace(store), "IE-001")
    assert Enum.any?(msgs, &(&1 =~ "FUN-001: on path but only proposed"))

    store = update(mechanism_chain(), "CAP-001", &Map.put(&1, "state", "weakened"))
    assert {:fail, msgs} = up(trace(store), "IE-001")
    assert Enum.any?(msgs, &(&1 =~ "CAP-001: on path but weakened"))
  end

  test "REQ-008: a Requirement on the path must be accepted" do
    store = governance_rooted(valid_store()) |> update("REQ-001", &Map.delete(&1, "accepted_by"))
    assert {:fail, msgs} = up(trace(store), "IE-001")
    assert Enum.any?(msgs, &(&1 =~ "not accepted"))
  end

  test "REQ-008: depends_on justifies only from normative or contextual artifacts" do
    store =
      valid_store()
      |> update("REQ-001", &Map.put(&1, "relationships", [rel("depends_on", "SUBJ-001")]))
      |> update("SUBJ-001", &Map.put(&1, "state", "canonical"))

    assert {:fail, [msg | _]} = up(trace(store), "IE-001")
    assert msg =~ "no upward path"

    via_principle =
      store
      |> add("project/p.yaml", %{"id" => "PRI-009", "type" => "Principle", "state" => "canonical", "relationships" => [rel("depends_on", "SUBJ-001")], "provenance" => prov()})
      |> update("REQ-001", &Map.put(&1, "relationships", [rel("derived_from", "PRI-009")]))

    assert {:pass, [{~w(IE-001 REQ-001 PRI-009 SUBJ-001), :subject}]} = up(trace(via_principle), "IE-001")
  end

  test "REQ-008: orphan implementation fails with its dead end" do
    store = update(valid_store(), "IE-001", &Map.delete(&1, "relationships"))
    assert {:fail, msgs} = up(trace(store), "IE-001")
    assert "dead end: IE-001" in msgs
  end

  test "REQ-009: accepted responsibility is realized, disposed, or fails" do
    t = trace(mechanism_chain())
    assert {:pass, {:realized, ["IE-001"]}} = down(t, "CAP-001")
    assert {:pass, {:disposed, ["REQ-001"]}} = down(t, "REQ-001")

    gap = update(mechanism_chain(), "IE-001", &Map.put(&1, "relationships", [rel("satisfies", "REQ-001")]))
    t = trace(gap)
    assert {:fail, [msg]} = down(t, "MEC-001")
    assert msg =~ "no downward path"
    assert t.overall == :fail

    disposed = update(gap, "FUN-001", &Map.put(&1, "disposition", "deferred to release 2"))
    t = trace(disposed)
    assert {:pass, {:disposed, ["FUN-001"]}} = down(t, "CAP-001")
    assert {:fail, _} = down(t, "MEC-001")
  end

  test "REQ-009: proposed responsibilities carry no obligation" do
    store = update(mechanism_chain(), "MEC-001", &Map.put(&1, "state", "proposed"))
    refute Map.has_key?(Map.new(trace(store).downward), "MEC-001")
  end

  test "REQ-011: overall pass, and store failure fails" do
    assert trace(mechanism_chain()).overall == :pass

    root = write(mechanism_chain())
    File.write!(Path.join(root, "project/bad.yaml"), "a: [")
    assert RI01.Trace.run(root).overall == :fail
  end

  test "upward traversal terminates on cycles" do
    store =
      governance_rooted(valid_store())
      |> add("project/x.yaml", %{"id" => "REQ-002", "type" => "Requirement", "accepted_by" => %{}, "relationships" => [rel("derived_from", "REQ-003")], "provenance" => prov()})
      |> add("project/x.yaml", %{"id" => "REQ-003", "type" => "Requirement", "accepted_by" => %{}, "relationships" => [rel("derived_from", "REQ-002")], "provenance" => prov()})

    s = RI01.Store.load(write(store))
    assert RI01.Trace.upward_paths(s, "REQ-002") == [~w(REQ-002 REQ-003)]
  end

  test "REQ-010: downward tree" do
    s = RI01.Store.load(write(mechanism_chain()))
    assert RI01.Trace.downward_tree(s, "FUN-001") == {"FUN-001", [{"MEC-001", [{"IE-001", []}]}]}
  end

  test "REQ-012: trace leaves the repository unchanged" do
    root = write(mechanism_chain(), git: true)
    status = fn -> System.cmd("git", ["-C", root, "status", "--porcelain", "--ignored"]) |> elem(0) end
    before = status.()
    RI01.Trace.run(root)
    assert status.() == before
  end

  test "I-012 repair: a non-reference manifest entry fails instead of raising" do
    assert {:fail, _, msgs} = outcome(check(valid_store(), canonical_foundation: %{"telos" => ["TEL-001"]}), "I-012")
    assert Enum.any?(msgs, &(&1 =~ "not an artifact reference"))
  end
end
