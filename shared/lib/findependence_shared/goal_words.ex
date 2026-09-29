defmodule FindependenceShared.GoalWords do
  @moduledoc """
  The wording of the goals and retirement pages (REQ-146, REQ-147, REQ-150..154, REQ-174), as plain text for
  both forms: how long savings would last, a set-aside, the retirement result and how it is worked out, how
  long paying the difference would last, and the alternatives' labels. Copied from the local form's pages
  (web/html.ex), so each says exactly what it said there. Nothing here is HTML; a page escapes it as it
  writes it. No sentence here names a member.
  """

  alias FindependenceShared.Words

  # ---------------------------------------------------------------------------
  # REQ-146: how long savings would last, and the member's own goal

  @doc "How long savings would last, as the page's large figure: \"About 2.3 months\"."
  def cover_months(months), do: "About #{one_decimal(months)} months"

  @doc "What the months are worked out from (`Planning.cover/1`)."
  def cover_note(%{savings: savings, monthly_out: out}),
    do:
      "Savings of #{Words.plain_amount(savings)} against #{Words.plain_amount(out)} a month of money out, if no money came in. Counts repeating money out of items you own."

  @doc "The member's goal and where they are: \"Your goal: 3 months of money out. You're at 2.3 of 3.\"."
  def goal_progress(goal_months, months),
    do:
      "Your goal: #{goal_months} #{if goal_months == 1, do: "month", else: "months"} of money out. You're at #{one_decimal(months)} of #{goal_months}."

  defp one_decimal(months), do: :erlang.float_to_binary(months, decimals: 1)

  # ---------------------------------------------------------------------------
  # REQ-147: a set-aside rate on money in linked to a value

  @doc "One set-aside (`Planning.set_asides/1`), for the value titled `value_title`."
  def set_aside_line(a, value_title),
    do:
      "#{Words.rate_text(a.rate_bp)} of money in for #{value_title} (#{Words.plain_amount(a.monthly_in)} a month): set aside #{Words.plain_amount(a.set_aside)} a month"

  @doc "What the button removing a set-aside says to a screen reader."
  def remove_set_aside(value_title), do: "Remove the set-aside for #{value_title}"

  # ---------------------------------------------------------------------------
  # REQ-151: the projection and how it is worked out

  @doc "When the result is at: \"In January 2028, the year you turn 67\", or \"Now\"."
  def retirement_when(%{retire_year: year, retire_age: age}, %Date{} = today),
    do: if(year > today.year, do: "In January #{year}, the year you turn #{age}", else: "Now")

  @doc "The year-by-year table's summary: \"Year by year, 2 years\"."
  def year_by_year(n), do: "Year by year, #{n} #{if n == 1, do: "year", else: "years"}"

  @doc """
  A retirement account the projection starts from, with its latest reading (or nil):
  "Work 401(k) ($10,000.00 as of Sunday, November 1)".
  """
  def starting_balance(title, nil, _today), do: "#{title} (no balance yet, so $0.00)"

  def starting_balance(title, reading, today),
    do:
      "#{title} (#{Words.plain_amount(reading.balance)} as of #{Words.date_text(reading.on, today)})"

  @doc """
  How the projection is worked out, after "How this is worked out: starting from …; " (what it starts from is
  written by the page, which links to adding an account when there is none).
  """
  def worked_out(p),
    do:
      "adding #{Words.plain_amount(p.monthly_contribution)} a month as you entered; growing each month at #{pct_text(p.return_bp)} a year after inflation, the return you entered; until January of the year you turn #{p.retire_age}. Everything is in today's dollars, and estimates are rounded to the nearest $100."

  # ---------------------------------------------------------------------------
  # REQ-174: paying the difference between the target and Social Security

  @doc "How long the balance would last paying the difference, as a sentence."
  def lasts_sentence(%{lasts: :covered}),
    do:
      "The Social Security estimate you entered is at least your target income, so there's no difference to pay from these accounts."

  def lasts_sentence(%{lasts: :beyond, gap: g}),
    do:
      "Paying the difference between your target income and Social Security, #{Words.plain_amount(g)} a month, from these accounts, some would remain at age 100."

  def lasts_sentence(%{lasts: {:months, n}, gap: g, retire_age: a}),
    do:
      "Paying the difference between your target income and Social Security, #{Words.plain_amount(g)} a month, from these accounts would last #{Words.months_text(n)}, to about age #{a + div(n, 12)}."

  @doc "How long it would last, short, as the alternatives' table has it (REQ-153)."
  def lasts_short(%{lasts: nil}), do: "No target set"
  def lasts_short(%{lasts: :covered}), do: "No difference to pay"
  def lasts_short(%{lasts: :beyond}), do: "Some remains at 100"

  def lasts_short(%{lasts: {:months, n}, retire_age: a}),
    do: "#{Words.months_text(n)}, to about age #{a + div(n, 12)}"

  # ---------------------------------------------------------------------------
  # REQ-153: what changes the result

  @doc "The label of one alternative (`Planning.retirement_sensitivity/2`'s `change`)."
  def change_label(:as_entered), do: "As you entered"
  def change_label({:return, d}) when d < 0, do: "Return 2 points lower"
  def change_label({:return, _}), do: "Return 2 points higher"
  def change_label({:retire_age, d}) when d < 0, do: "Retiring 2 years earlier"
  def change_label({:retire_age, _}), do: "Retiring 2 years later"

  # ---------------------------------------------------------------------------
  # Figures

  @doc "A return in basis points as a percentage, with a true minus: \"−1.5%\"."
  def pct_text(bp), do: bp |> Words.rate_text() |> String.replace_prefix("-", "−")

  @doc """
  UX-002 R6, UX-003 C10: an estimate years ahead, to the nearest $100 in whole dollars, saying it's an
  estimate: "about $13,000"; `about_signed/1` keeps the sign: "about +$200".
  """
  def about(cents), do: "about " <> whole_dollars(Words.plain_amount(round_100(cents)))
  def about_signed(cents), do: "about " <> whole_dollars(Words.format_amount(round_100(cents)))

  defp whole_dollars(text), do: String.replace_suffix(text, ".00", "")

  defp round_100(c) when c < 0, do: -round_100(-c)
  defp round_100(c), do: div(c + 5_000, 10_000) * 10_000

  # ---------------------------------------------------------------------------
  # REQ-150: the assumptions form

  @doc "A contribution field's label."
  def contribution_label(account_title), do: "Each month into #{account_title}"

  @doc "A saved monthly amount as its field shows it: \"1,200.00\", or \"\" when unset."
  def money_field(nil), do: ""
  def money_field(cents), do: cents |> Words.plain_amount() |> String.replace_prefix("$", "")

  @doc "A saved return as its field shows it: \"4.5\", or \"\" when unset."
  def return_field(nil), do: ""
  def return_field(bp), do: bp |> Words.rate_text() |> String.replace_suffix("%", "")

  @doc "A saved whole number (birth year, age) as its field shows it, or \"\" when unset."
  def int_field(nil), do: ""
  def int_field(n), do: Integer.to_string(n)
end
