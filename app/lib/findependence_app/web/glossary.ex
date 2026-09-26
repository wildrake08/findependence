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
    {"request", "A change waiting for someone to agree."}
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
    {~r/\bconsent\w*/i, "agree"}
  ]

  def terms, do: @terms
  def banned, do: @banned

  @doc "The banned synonyms found in `text`, as `{found, use_instead}`."
  def violations(text) do
    for {re, instead} <- @banned, [found | _] <- Regex.scan(re, text), do: {found, instead}
  end
end
