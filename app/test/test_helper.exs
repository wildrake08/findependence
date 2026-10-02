ExUnit.start()

defmodule FindependenceApp.TestJoint do
  @moduledoc """
  WI-086 (CP-029): nobody becomes an owner without agreeing. A test that sets up an owner change proposes it and
  has each joiner agree, which is what the change used to do at once: `joint!/4` on a household, `joint_v/5` on a
  vault through the test's own `act(vault, member, fun)`. A change still waiting for current owners stays waiting.
  """
  alias Findependence.Household

  def joint!(h, actor, item, owners) do
    before = h.items[item].owners
    # values and plans waited for their joiners before WI-086 too; the case then tests that
    joining? = Map.get(h.items[item].attrs, :kind) not in [:value, :plan]
    {:ok, h, pid} = Household.propose_owners(h, actor, item, owners)
    joiners = if joining?, do: MapSet.difference(MapSet.new(owners), before), else: MapSet.new()

    consent_joiners(h, pid, joiners, fn h, j ->
      {:ok, h} = Household.consent(h, j, pid)
      h
    end)
  end

  def joint_v(v, act, actor, item, owners) do
    before = MapSet.new(v.items[item].owners)
    known = Map.keys(v.proposals)
    v = act.(v, actor, &Household.propose_owners(&1, actor, item, owners))
    joiners = MapSet.difference(MapSet.new(owners), before)

    case Map.keys(v.proposals) -- known do
      [pid] ->
        consent_joiners(v, pid, joiners, fn v, j -> act.(v, j, &Household.consent(&1, j, pid)) end)

      [] ->
        v
    end
  end

  defp consent_joiners(state, pid, joiners, consent) do
    Enum.reduce(Enum.sort(joiners), state, fn j, state ->
      case state.proposals[pid] do
        %{consents: c} = p ->
          if MapSet.subset?(owners_of(state, p), MapSet.new(c)) and j not in c,
            do: consent.(state, j),
            else: state

        nil ->
          state
      end
    end)
  end

  defp owners_of(state, p), do: MapSet.new(state.items[p.item_id].owners)
end

# WI-074 (REQ-188 AC-1): the contract cases shared with the hosted form, from shared/test/support/contract
contract = Path.expand("../../shared/test/support/contract", __DIR__)
Enum.each(~w(form.ex helpers.ex cases.ex), &Code.require_file(&1, contract))

for f <- Path.wildcard(Path.join(contract, "*_cases.ex")) |> Enum.sort(),
    do: Code.require_file(f)
