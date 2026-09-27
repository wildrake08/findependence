defmodule FindependenceApp.Web.Glossary do
  @moduledoc """
  UX-001 R9: one word per concept. Every user-facing string uses these terms; the draft study
  materials use them too. `banned/0` lists synonyms that must not appear in rendered pages, and a
  test renders every page to check.
  """

  @terms [
    {"item", "Money in or out that a member records."},
    {"value", "Something that matters to a member, in their own words."},
    {"owner", "A member who owns an item or value; only owners change it."},
    {"can see", "A member who isn't an owner but was shared an item or value."},
    {"share / stop sharing", "Let a member see an item or value, or stop letting them."},
    {"give away", "A sole owner makes someone else the owner."},
    {"stop owning", "A joint owner leaves the owners; the others keep it."},
    {"request", "A change waiting for someone to agree."},
    {"per month", "A repeating item's amount converted to a month, as the totals use it."},
    {"one-off", "An item that happens once."},
    {"account", "Somewhere money is kept: checking, savings, or other (CAP-010)."},
    {"debt", "Money owed: a card, a HELOC, a loan, or other (CAP-010)."},
    {"balance", "What an account holds, or a debt's amount owed, as of a date."},
    {"interest", "What a debt costs at its rate, stated as a fact for one month."},
    {"coming up", "Dated items in the next fourteen days (CAP-011)."},
    {"set aside", "A monthly amount that would cover items that happen less often than monthly."}
  ]

  # Synonyms of the terms above, matched case-insensitively on whole words.
  @banned [
    {~r/\bmoney items?\b/i, "item"},
    {~r/\bthings?\b/i, "item or value"},
    {~r/\bsomething\b/i, "item or value"},
    {~r/\bheld by\b/i, "owned by"},
    {~r/\bvisib(le|ility)\b/i, "can see"},
    {~r/\blet (\w+ )?see\b/i, "share"},
    {~r/\bgrant(s|ed|ee|ees)?\b/i, "share"},
    {~r/\brevok\w*/i, "stop sharing"},
    {~r/\bunshar\w*/i, "stop sharing"},
    {~r/\btransfer\w*/i, "give away"},
    {~r/\bhand over\b/i, "give away"},
    {~r/\brelinquish\w*/i, "stop owning"},
    {~r/\blet(ting)? go\b/i, "stop owning / give away"},
    {~r/\bpropos\w*/i, "request"},
    {~r/\binvit\w*/i, "request"},
    {~r/\bpending\b/i, "waiting"},
    {~r/\bconsent\w*/i, "agree"},
    {~r/\bone[- ]time\b/i, "one-off"},
    {~r/\bonce-off\b/i, "one-off"},
    {~r/\bmonthly equivalent\b/i, "per month"}
  ]

  # ROADMAP-ALPHA section 3: computed results carry no judgment. Checked on user-visible text.
  @judgment ~r/\b(good|bad|risky?|healthy|unhealthy|on track|off track|over budget|under budget|warning|danger(ous)?|too much|too little|you can afford|can.t afford)\b/i

  def terms, do: @terms
  def banned, do: @banned

  @doc "Judgment words found in `text` (ROADMAP-ALPHA section 3)."
  def judgments(text), do: Regex.scan(@judgment, text) |> Enum.map(&hd/1)

  @doc "The banned synonyms found in `text`, as `{found, use_instead}`."
  def violations(text) do
    for {re, instead} <- @banned, [found | _] <- Regex.scan(re, text), do: {found, instead}
  end
end
