defmodule FindependenceShared.PlanWords do
  @moduledoc """
  The words both forms use on the plan pages (REQ-142, REQ-143, REQ-148, REQ-166; WI-076): a plan's steps,
  the comparison's summary and notes, a plan request, a shared plan, and the confirmation for deleting a
  plan, moved without change from the local form's page rendering (web/html.ex). Plain text only: each form
  escapes and marks it up. Where a member is named, `name_of` turns a member id into what is shown (the local
  form's ids are the names themselves; the hosted form's are membership ids, shown by display name).
  """

  alias FindependenceShared.{Items, Planning, Scope, Words}

  defp sc(h, m), do: Scope.read(h, m)

  @doc """
  A plan step in words, as the member `m` sees it in household `h`: a switched-off item is named only if the
  member can see it, with what the member has marked as depending on it.
  """
  def step_text(h, m, {:switch_off, ids, from}) do
    # names come from the viewer's own household, so a shared plan names only what they can see
    names =
      Enum.map(ids, fn id ->
        cond do
          Items.lookup(sc(h, m), id) == nil -> "an item no longer there"
          Items.visible?(sc(h, m), id) -> Words.title(Items.lookup(sc(h, m), id))
          true -> "an item you can't see"
        end
      end)

    deps =
      for {i, j} <- Planning.depends(sc(h, m)),
          j in ids,
          do: Words.title(Items.lookup(sc(h, m), i))

    extra = if deps == [], do: "", else: " (and what depends on it: #{Words.people(deps)})"
    "From #{Words.month_text(from)}: switch off #{Words.people(names)}#{extra}."
  end

  def step_text(_h, _m, {:add, a, from}),
    do:
      "From #{Words.month_text(from)}: #{a.note}, #{Words.money_line(Map.put(a, :unit, :cents))} (planned)."

  def step_text(_h, _m, {:borrow, b, from}),
    do:
      "From #{Words.month_text(from)}: borrow #{Words.plain_amount(b.amount)} at #{Words.rate_text(b.rate_bp)}, paying #{Words.plain_amount(b.payment)} a month."

  @doc "A member's own plan in the plans list, after its name: \"2 steps, private to you\"."
  def plan_entry(%{steps: steps}),
    do: "#{length(steps)} #{if length(steps) == 1, do: "step", else: "steps"}, private to you"

  @doc "A shared plan in the plans list, after its name: \"shared plan, owned by Ana and you\"."
  def shared_plan_entry(owners, m, name_of \\ &Function.identity/1),
    do: "shared plan, owned by #{Words.people(owners, m, "No one", name_of)}"

  @doc "A shared plan's page, under its name (REQ-148)."
  def shared_plan_note(owners, m, name_of \\ &Function.identity/1),
    do:
      "A shared plan, owned by #{Words.people(owners, m, "No one", name_of)}. Its steps don't change; a revised plan is a new request."

  @doc "A plan request's page, under the plan's name (REQ-148): who asked, and that nothing changes yet."
  def request_note(consents, m, name_of \\ &Function.identity/1),
    do:
      "#{Words.people(consents, m, "No one", name_of)} asked you to share this plan. Nothing changes until you agree, and a shared plan never changes your real totals."

  @doc """
  UX-002 R5: the comparison's answer in one or two sentences, before the months it comes from; nil when
  there is no cash to start from. Amounts are written by `amount` (by default `Words.plain_amount/1`), so a
  form can keep each amount from splitting in running text.
  """
  def plan_summary(base, with_plan, amount \\ &Words.plain_amount/1) do
    case plan_summary_parts(base, with_plan) do
      nil ->
        nil

      parts ->
        Enum.map_join(parts, fn
          {:amount, cents} -> amount.(cents)
          text -> text
        end)
    end
  end

  @doc """
  `plan_summary/3` as parts: text, and `{:amount, cents}` for each amount in it; nil when there is no cash
  to start from.
  """
  def plan_summary_parts(%{start: nil}, _with_plan), do: nil

  def plan_summary_parts(base, with_plan),
    do:
      ["With this plan, "] ++
        describe(with_plan.months) ++ [". Without it, "] ++ describe(base.months) ++ ["."]

  defp describe(months) do
    low = Enum.min_by(months, & &1.cash)

    case Enum.find(months, &(&1.cash < 0)) do
      nil ->
        [
          "cash doesn't go below zero in these 12 months; it is lowest in #{Words.month_text(low.month)}, at ",
          {:amount, low.cash}
        ]

      first ->
        [
          "cash first goes below zero in #{Words.month_text(first.month)} and is lowest in #{Words.month_text(low.month)}, at ",
          {:amount, low.cash}
        ]
    end
  end

  @doc "What the comparison's months show, and that it isn't what's real."
  def comparison_note(base) do
    what =
      if base.start,
        do: "cash at the end of each month",
        else: "net money in and out each month (add an account's balance to see cash)"

    "Showing #{what}. This is a plan, not what's real."
  end

  @doc "A month's difference the plan makes: in cash when both have it, else in net money in and out."
  def difference(a, b) do
    if a.cash && b.cash,
      do: Words.format_amount(b.cash - a.cash),
      else: Words.format_amount(b.net - a.net)
  end

  @doc "REQ-143 AC-2: the interest on the planned borrowing (`loans`, the planned debts), or nil if none."
  def borrowing_interest([]), do: nil

  def borrowing_interest(loans),
    do:
      "Interest on the planned borrowing over these months: #{Words.plain_amount(Enum.sum(Enum.map(loans, & &1.interest)))}."

  @doc """
  REQ-166 AC-3: the confirmation for deleting the plan `name` with `count` steps, as
  `{heading, body, yes}`.
  """
  def confirm_delete(name, count) do
    steps = if count == 1, do: "Its 1 step", else: "Its #{count} steps"

    {"Delete the plan “#{name}”?",
     "#{steps} will be deleted with it. Your real items and totals don't change. This can't be undone.",
     "Yes, delete the plan"}
  end
end
