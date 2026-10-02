defmodule FindependenceShared.Clock do
  @moduledoc """
  The household rules' clock and cooling-off (REQ-201, CP-030 option A, WI-088). Each form sets
  `config :findependence_shared, cooling_seconds: ...`: 72 hours, or 0 in the test suites that check the rules as
  they were before CP-030 (dedicated tests turn it on). Unset, it is 72 hours: a form that forgets gets the strict
  behaviour. `:now` (Unix seconds) fixes the clock, for tests only.
  """

  @seventy_two_hours 72 * 3600

  @doc "Now, in Unix seconds."
  def now, do: Application.get_env(:findependence_shared, :now) || System.os_time(:second)

  @doc "How long a change that widens access or takes something away waits, in seconds."
  def cooling,
    do: Application.get_env(:findependence_shared, :cooling_seconds, @seventy_two_hours)
end
