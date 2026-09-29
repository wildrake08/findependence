defmodule FindependenceShared.CashFlow do
  @moduledoc """
  Domain context Cash flow (DP-001 section 2; CAP-011, MEC-018): what is coming up, the next sixty days,
  the next twelve months, and set-asides, all computed on request over what the member can see (REQ-161,
  REQ-162, REQ-173, REQ-140).
  """

  alias FindependenceShared.Scope
  alias Findependence.{Alignment, Projection, Schedule}

  @doc "Day-by-day cash flow for `days` days from `from`, for what counts for the member (REQ-161, REQ-173)."
  def cash_flow(%Scope{member: m, household: h}, %Date{} = from, days),
    do: Schedule.cash_flow(h, m, from, days)

  @doc "The member's money out that happens less often than monthly, and its monthly set-aside (REQ-140)."
  def set_asides(%Scope{member: m, household: h}), do: Schedule.set_asides(h, m)

  @doc "The next twelve months, as things are or with a plan (REQ-162, REQ-143)."
  def project(%Scope{member: m, household: h}, %Date{} = today, plan \\ nil),
    do: Projection.project(h, m, today, plan)

  @doc "The twelve months from `today`."
  defdelegate months(today), to: Projection

  @doc "An item's dates between two days (REQ-137)."
  defdelegate occurrences(item, from, to), to: Schedule

  @doc "An item's date, if it has one (REQ-136)."
  defdelegate date(item), to: Schedule

  @doc "An amount at a frequency, as a monthly figure (REQ-162)."
  defdelegate per_month(amount, frequency), to: Alignment
end
