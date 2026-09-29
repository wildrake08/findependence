defmodule FindependenceApp.Scope do
  @moduledoc """
  The trusted scope every context operation takes (ARCH-003 7, 14; DP-001 section 7; WI-066): the acting
  member and their unlocked session. It is built only from a session the server holds (`Sessions`), never
  from request data, so an operation always acts as the member who unlocked. In the local-first form the
  household is the one vault the device holds (DP-001 section 10).
  """

  alias FindependenceApp.Session

  @enforce_keys [:member, :session]
  defstruct [:member, :session]

  @type t :: %__MODULE__{member: String.t(), session: Session.t()}

  @doc "The scope for an unlocked session."
  def new(%Session{member: member} = session), do: %__MODULE__{member: member, session: session}
end
