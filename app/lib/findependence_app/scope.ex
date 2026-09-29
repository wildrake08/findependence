defmodule FindependenceApp.Scope do
  @moduledoc """
  The scope every context operation takes (ARCH-003 7, 14; DP-001 section 7; WI-066): the acting member and
  the household as that member sees it (items they can't read are placeholders, `Session`).

  A scope that can change the household is built only from a session the server holds (`new/1`, from
  `Sessions`), never from request data, so a change always acts as the member who unlocked. A read scope
  (`read/2`) holds only a household view and a member, for the rendering layer, whose functions take the
  view the transport got from that member's session (REV-087). Only a scope with a session can change
  anything (`FindependenceApp.Operation`). In the local-first form the household is the one vault the
  device holds (DP-001 section 10).
  """

  alias FindependenceApp.Session

  @enforce_keys [:member, :household]
  defstruct [:member, :household, session: nil]

  @doc "The scope for an unlocked session: it can read and change."
  def new(%Session{member: member, household: household} = session),
    do: %__MODULE__{member: member, household: household, session: session}

  @doc "A read scope over a household view the member already holds (REV-087)."
  def read(household, member), do: %__MODULE__{member: member, household: household}
end
