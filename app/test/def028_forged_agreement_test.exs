defmodule FindependenceApp.DEF028ForgedAgreementTest do
  @moduledoc """
  DEF-028's forged-agreement path, reproduced at runtime on v0.8.4-alpha (2026-10-02, after a source-only report):
  a co-owner who could edit the vault file wrote the other owner's agreement into a request and had the app apply
  it, with the other owner's history saying they agreed and no warning; the cooling-off (REQ-201) was no defence.
  Turned round by WI-090 (REQ-203, CP-031 option A): only agreements their members signed count.
  Not async: one case turns the cooling-off on for the whole VM.
  """
  use ExUnit.Case, async: false
  import FindependenceApp.TestJoint

  alias FindependenceApp.{Session, Vault}
  alias Findependence.{Household, Ledger, View}

  @opts [iterations: 1_000, unsafe_test: true]

  defp session(v, m) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)
    s
  end

  defp act(v, m, fun) do
    s = session(v, m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
    end
  end

  # Ana and Ben co-own "Joint savings"; Ben asks to share it with Cy, which waits for Ana. Ben then writes Ana's
  # agreement into the request in the file and agrees again through the app.
  defp forge do
    v =
      Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)
      |> act("ana", &Household.add_item(&1, "ana", "savings", %{note: "Joint savings"}))
      |> joint_v(&act/3, "ana", "savings", ["ana", "ben"])
      |> act("ben", &Household.propose_grant(&1, "ben", "savings", "cy"))

    [p] = Map.keys(v.proposals)
    honest = MapSet.to_list(v.proposals[p].consents)
    v = update_in(v, [:proposals, p, :consents], &MapSet.put(&1, "ana"))
    v = act(v, "ben", &Household.consent(&1, "ben", p))
    {v, honest}
  end

  defp report(label, v, honest) do
    cy = session(v, "cy")
    ana = session(v, "ana")
    {:ok, history} = Ledger.read(ana.household, "ana", "savings")

    %{
      label: label,
      honest_consents: honest,
      cy_reads:
        View.visible?(cy.household, "cy", "savings") and
          cy.household.items["savings"].attrs != %{},
      history: Enum.map(history, &{&1.event, Enum.sort(&1.by)}),
      ana_warned: Session.integrity_issues(ana) != []
    }
  end

  test "REQ-203 AC-1: a co-owner's unsigned forged agreement isn't counted: nothing is shared, the request still waits" do
    {v, honest} = forge()
    r = report("wait off", v, honest)
    IO.puts("REQ-203 #{inspect(r)}")

    assert r.honest_consents == ["ben"]
    refute r.cy_reads
    refute Enum.any?(r.history, &match?({:granted, _}, &1))
    [p] = Map.keys(v.proposals)
    assert v.proposals[p].consents == MapSet.new(["ben"])
  end

  test "REQ-203 AC-2: an agreement with a signature that doesn't verify isn't counted, and is reported" do
    v =
      Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)
      |> act("ana", &Household.add_item(&1, "ana", "savings", %{note: "Joint savings"}))
      |> joint_v(&act/3, "ana", "savings", ["ana", "ben"])
      |> act("ben", &Household.propose_grant(&1, "ben", "savings", "cy"))

    [p] = Map.keys(v.proposals)
    # Ben writes Ana's agreement with a signature of his own over it
    {_, ben_sig} = v.proposals[p].sigs["ben"]

    v =
      update_in(v, [:proposals, p], fn prop ->
        %{
          prop
          | consents: MapSet.put(prop.consents, "ana"),
            sigs: Map.put(prop.sigs, "ana", {1_900_000_000, ben_sig})
        }
      end)

    # whoever opens the file next is told; the app's next save drops the agreement it didn't count
    assert {:forged_agreement, p, "ana"} in Session.integrity_issues(session(v, "ana"))
    v = act(v, "ben", &Household.consent(&1, "ben", p))
    refute View.visible?(session(v, "cy").household, "cy", "savings")
    assert v.proposals[p].consents == MapSet.new(["ben"])
  end

  test "REQ-203 AC-3: the cooling-off's end comes from the signed times; a written-in end or opening is ignored" do
    before = Application.get_env(:findependence_shared, :cooling_seconds)
    on_exit(fn -> Application.put_env(:findependence_shared, :cooling_seconds, before) end)

    v =
      Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)
      |> act("ana", &Household.add_item(&1, "ana", "savings", %{note: "Joint savings"}))

    Application.put_env(:findependence_shared, :cooling_seconds, 72 * 3600)
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "savings", "cy"))
    [p] = Map.keys(v.proposals)
    signed_due = session(v, "ana").household.proposals[p].due

    # someone with the file writes an end in the past and marks it opened
    v = update_in(v, [:proposals, p], &Map.merge(&1, %{due: 0, released: true}))
    h = session(v, "ana").household
    assert h.proposals[p].due == signed_due
    refute Map.get(h.proposals[p], :released, false)
    assert Household.due(h, "ana") == []
    refute View.visible?(session(v, "cy").household, "cy", "savings")
  end

  test "REQ-203 AC-1: with the 72-hour cooling-off on too, the forged agreement does nothing" do
    before = Application.get_env(:findependence_shared, :cooling_seconds)

    on_exit(fn -> Application.put_env(:findependence_shared, :cooling_seconds, before) end)

    # the joint ownership is made before the wait applies; the attack runs with it on
    v =
      Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)
      |> act("ana", &Household.add_item(&1, "ana", "savings", %{note: "Joint savings"}))
      |> joint_v(&act/3, "ana", "savings", ["ana", "ben"])

    Application.put_env(:findependence_shared, :cooling_seconds, 72 * 3600)
    v = act(v, "ben", &Household.propose_grant(&1, "ben", "savings", "cy"))
    [p] = Map.keys(v.proposals)
    honest = MapSet.to_list(v.proposals[p].consents)
    v = update_in(v, [:proposals, p, :consents], &MapSet.put(&1, "ana"))
    v = act(v, "ben", &Household.consent(&1, "ben", p))

    r = report("wait on", v, honest)
    IO.puts("REQ-203 #{inspect(r)}")

    refute r.cy_reads
    refute Enum.any?(r.history, &match?({:granted, _}, &1))
  end

  test "REQ-203 AC-4: a request from before signed agreements is asked again, and applies once its owners agree in the app" do
    v =
      Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)
      |> act("ana", &Household.add_item(&1, "ana", "savings", %{note: "Joint savings"}))
      |> joint_v(&act/3, "ana", "savings", ["ana", "ben"])
      |> act("ben", &Household.propose_grant(&1, "ben", "savings", "cy"))

    [p] = Map.keys(v.proposals)
    # as v0.8.4 wrote it: agreements without signatures
    v = update_in(v, [:proposals, p], &Map.delete(&1, :sigs))
    ana = session(v, "ana")
    assert ana.household.proposals[p].consents == MapSet.new()
    assert Session.integrity_issues(ana) == []

    v =
      v
      |> act("ben", &Household.consent(&1, "ben", p))
      |> act("ana", &Household.consent(&1, "ana", p))

    assert View.visible?(session(v, "cy").household, "cy", "savings")
  end
end
