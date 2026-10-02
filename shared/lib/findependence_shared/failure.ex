defmodule FindependenceShared.Failure do
  @moduledoc """
  ARCH-003 34 (WI-066): the stable categories a context operation's failure falls into, so a transport can
  map them to its own protocol without knowing each rule. The reason itself is kept beside the category,
  because the interface names the actual problem to the member (UX-001 R6).

  An item a member can't see is `:not_found`, never `:unauthorized`, so its existence isn't revealed (ASM-014).
  """

  @categories %{
    validation:
      ~w(invalid_step invalid_retirement invalid_plan invalid_goal invalid_balance invalid_value
                   invalid_reading invalid_mark no_choice no_owners note amount frequency on balance rate
                   min_payment not_money not_income not_a_value not_a_cash_account not_a_balance
                   cannot_link_a_value cannot_link_a_plan cannot_link_a_balance)a,
    unauthenticated: ~w(bad_credentials account_changed)a,
    unauthorized: ~w(not_owner not_sole_owner not_a_member)a,
    not_found: ~w(not_found unknown_action not_granted)a,
    conflict:
      ~w(file_changed file_unreadable already_owner already_marked already_linked already_granted item_exists
                 plan_exists no_change)a,
    permanent_domain_rejection:
      ~w(still_owner sole_owner household_full items_full too_many_changes)a
  }

  @by_reason for {category, reasons} <- @categories, r <- reasons, into: %{}, do: {r, category}

  @doc "The category of a failure reason; an unlisted reason is a permanent domain rejection."
  def category(reason) when is_atom(reason),
    do: Map.get(@by_reason, reason, :permanent_domain_rejection)

  def category(_), do: :permanent_domain_rejection

  @doc "Every category, for transports that map them."
  def categories, do: Map.keys(@categories)
end
