defmodule RI01.DelegationTest do
  @moduledoc "REQ-013: I-012 enforces the delegated authority policy (CP-002 option B)."
  use ExUnit.Case, async: true

  import RI01.Fixture

  defp ai_specified, do: [h(nil, "proposed", "ACT-002"), h("proposed", "coherent", "ACT-002", "CP-002"), h("coherent", "specified", "ACT-002", "CP-002")]

  defp branch(cap_state \\ "specified") do
    cap_history = if cap_state == "specified", do: specified_history(), else: [h(nil, "proposed", "ACT-002")]

    valid_store()
    |> add("project/b.yaml", %{"id" => "CAP-001", "type" => "Capability", "state" => cap_state, "history" => cap_history, "provenance" => prov()})
    |> add("project/b.yaml", %{"id" => "FUN-001", "type" => "Function", "state" => "specified", "history" => ai_specified(), "relationships" => [rel("enables", "CAP-001")], "provenance" => prov()})
    |> add("project/b.yaml", %{"id" => "MEC-001", "type" => "Mechanism", "state" => "specified", "history" => ai_specified(), "relationships" => [rel("realizes", "FUN-001")], "provenance" => prov()})
    |> add("project/b.yaml", %{
      "id" => "REQ-101",
      "type" => "Requirement",
      "state" => "specified",
      "accepted_by" => %{"actor" => "ACT-002", "authority" => "CP-002"},
      "history" => ai_specified(),
      "relationships" => [rel("derived_from", "MEC-001")],
      "provenance" => prov()
    })
  end

  defp i012(store), do: outcome(check(store), "I-012")

  test "(b) AI may specify Function and Mechanism, and accept a Requirement, when parents are specified" do
    assert {:pass, _, []} = i012(branch())
  end

  test "(b) delegation fails when a parent is only proposed" do
    assert {:fail, _, msgs} = i012(branch("proposed"))
    assert Enum.any?(msgs, &(&1 =~ "FUN-001" and &1 =~ "parent CAP-001 is proposed"))
  end

  test "(b) delegated Requirement acceptance requires every derived_from target to be specified" do
    store = update(branch(), "REQ-101", &Map.put(&1, "relationships", [rel("derived_from", "MEC-001"), rel("derived_from", "CON-001")]))
    assert {:fail, _, msgs} = i012(store)
    assert Enum.any?(msgs, &(&1 =~ "REQ-101" and &1 =~ "parent CON-001 is proposed"))
  end

  test "(b) AI may not specify a Capability or Outcome (policy: ai deny)" do
    store = update(branch(), "CAP-001", &Map.put(&1, "history", ai_specified()))
    assert {:fail, _, msgs} = i012(store)
    assert Enum.any?(msgs, &(&1 =~ "CAP-001" and &1 =~ "does not delegate 'specify'"))
  end

  test "(b) delegation needs a parent" do
    store = update(branch(), "FUN-001", &Map.delete(&1, "relationships"))
    assert {:fail, _, msgs} = i012(store)
    assert Enum.any?(msgs, &(&1 =~ "no parent"))
  end

  test "(a) AI may not canonicalize a delegated type" do
    store =
      update(branch(), "MEC-001", fn m ->
        Map.merge(m, %{"state" => "canonical", "history" => ai_specified() ++ [h("specified", "canonical", "ACT-002", "CP-002")]})
      end)

    assert {:fail, _, msgs} = i012(store)
    assert Enum.any?(msgs, &(&1 =~ "MEC-001" and &1 =~ "canonicalization requires a human"))
  end

  test "(c) non-human acceptance is checked even when history is by a human" do
    store =
      branch()
      |> update("REQ-101", &Map.merge(&1, %{"history" => specified_history(), "relationships" => [rel("derived_from", "CON-001")]}))

    assert {:fail, _, msgs} = i012(store)
    assert Enum.any?(msgs, &(&1 =~ "accepted by non-human"))
  end

  test "human transitions and human acceptance need no delegation" do
    store =
      branch("proposed")
      |> update("FUN-001", &Map.put(&1, "history", specified_history()))
      |> update("MEC-001", &Map.put(&1, "history", specified_history()))
      |> update("REQ-101", &Map.merge(&1, %{"history" => specified_history(), "accepted_by" => %{"actor" => "ACT-001"}}))

    assert {:pass, _, []} = i012(store)
  end
end
