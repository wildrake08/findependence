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

  @doc "The household's members."
  def members(%Scope{household: h}), do: h.members
end
