defmodule FindependenceShared.Values do
  @moduledoc """
  Domain context Values (DP-001 section 2; CAP-003, CAP-004, MEC-008..010): values, and each member's
  private links from money items to them.
  """

  alias FindependenceShared.{Persistence, Scope}
  alias Findependence.Alignment

  @doc "Adds a value the member owns (REQ-111)."
  def add_value(%Scope{member: m} = scope, label),
    do: Persistence.run(scope, &Alignment.add_value(&1, m, Persistence.new_id(), label))

  @doc "Links a money item to a value, privately (REQ-168)."
  def link(%Scope{member: m} = scope, item, value),
    do: Persistence.run(scope, &Alignment.link(&1, m, item, value))

  @doc "Removes a link (REQ-168)."
  def unlink(%Scope{member: m} = scope, item, value),
    do: Persistence.run(scope, &Alignment.unlink(&1, m, item, value))

  @doc "The member's value distribution over what they can see (REQ-128)."
  def distribution(%Scope{member: m, household: h}), do: Alignment.distribution(h, m)

  @doc "The member's own links (REQ-168)."
  def links(%Scope{member: m, household: h}), do: Alignment.links(h, m)

  @doc "Whether an item is a value (REQ-111)."
  defdelegate value?(item), to: Alignment
end
