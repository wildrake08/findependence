defmodule Findependence.TestJoint do
  @moduledoc """
  WI-086 (CP-029): nobody becomes an owner without agreeing, so a test that sets up a joint item proposes the new
  owners and has each joiner agree. `joint!/4` returns the household; `joint/4` returns `{:ok, household}`.
  A proposal still waiting for current owners is left waiting: a joiner can't agree before them.
  """
  alias Findependence.Household

  def joint!(h, actor, item, owners), do: elem(joint(h, actor, item, owners), 1)

  def joint(h, actor, item, owners) do
    before = h.items[item].owners

    case Household.propose_owners(h, actor, item, owners) do
      {:ok, h, pid} ->
        joiners = MapSet.difference(MapSet.new(owners), before)

        h =
          Enum.reduce(joiners, h, fn j, h ->
            p = h.proposals[pid]

            if (p && MapSet.subset?(before, p.consents)) and j not in p.consents do
              {:ok, h} = Household.consent(h, j, pid)
              h
            else
              h
            end
          end)

        {:ok, h}

      other ->
        other
    end
  end
end

ExUnit.start()
