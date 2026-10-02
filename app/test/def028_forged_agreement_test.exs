defmodule FindependenceApp.DEF028ForgedAgreementTest do
  @moduledoc """
  DEF-028, reproduced at runtime on v0.8.4-alpha (2026-10-02, after a source-only report). Documents what happens
  today, so it fails, and must then be turned round, when agreements are authenticated (CP-031, proposed, or
  DESIGN-002): a co-owner who can edit the vault file writes the other owner's agreement into a request and has
  the app apply it. The cooling-off (REQ-201) is no defence: its fields are as unauthenticated as the agreement.
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

  test "DEF-028 (still open): a co-owner's forged agreement shares a joint item; history says the other agreed; no warning" do
    {v, honest} = forge()
    r = report("wait off", v, honest)
    IO.puts("DEF-028 #{inspect(r)}")

    assert r.honest_consents == ["ben"]
    assert r.cy_reads
    assert {:granted, ["ana", "ben"]} in r.history
    refute r.ana_warned
  end

  test "DEF-028 (still open): the 72-hour cooling-off doesn't stop it" do
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
    IO.puts("DEF-028 #{inspect(r)}")

    assert r.cy_reads
    refute r.ana_warned
  end
end
