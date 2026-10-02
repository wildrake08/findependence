defmodule FindependenceShared.Households do
  @moduledoc """
  Domain context Households (DP-001 section 2; CAP-002, MEC-007): membership and leaving, and the member's
  current view of the household.
  """

  alias FindependenceShared.{Persistence, Scope}
  alias Findependence.Exit

  @doc "The scope on the latest state of the household, as the member can see it."
  def view(%Scope{} = scope), do: Persistence.refresh(scope)

  @doc "An action the household doesn't have: refused as not found, on the latest state."
  def unknown_action(%Scope{} = scope),
    do: Persistence.run(scope, fn _ -> {:error, :unknown_action} end)

  @doc "Leaves the household; refused while the member still owns anything (REQ-110)."
  def leave(%Scope{member: m} = scope), do: Persistence.run(scope, &Exit.leave(&1, m))

  @doc """
  REQ-201 (WI-088): applies the member's waiting changes whose cooling-off has ended, and opens to their
  prospective owners those still waiting for them, before the member's page is shown. Only an owner's session can
  seal what such a change needs, so each form calls this for the signed-in member on every page. Returns the scope,
  saved if anything changed.
  """
  def settle(%Scope{member: m, household: h} = scope) do
    if Findependence.Household.due(h, m) == [] do
      scope
    else
      case Persistence.run(scope, &Findependence.Household.settle(&1, m)) do
        {:ok, saved} -> Scope.new(saved)
        {:error, _category, _reason, latest} -> Scope.new(latest)
      end
    end
  end

  @doc "The household's members."
  def members(%Scope{household: h}), do: h.members
end
