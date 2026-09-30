defmodule FindependenceShared.Messages do
  @moduledoc """
  What a member is told when a context operation refuses, in plain language, for both forms (WI-075, REV-100
  H3). Moved without change from the local form's page rendering; each form shows these as they are. A reason
  not listed gets "That didn't work."
  """

  @errors %{
    not_found: "That isn't available to you.",
    not_a_member: "That person isn't in this household.",
    already_owner: "They already own it.",
    already_granted: "They can already see it.",
    not_granted: "They can't see it now, so there is nothing to stop.",
    no_owners: "An item or value needs at least one owner.",
    no_change: "That wouldn't change anything.",
    sole_owner:
      "You're the only owner, so you can't stop owning it. Give it away or delete it instead.",
    not_sole_owner: "Only a sole owner can delete it. You can stop owning it instead.",
    still_owner:
      "You still own items or values. Give them away, stop owning them, or delete them first.",
    no_choice: "Choose what should happen to it first.",
    already_linked: "Those are already linked.",
    cannot_link_a_plan: "Plans can't be linked to values.",
    invalid_plan: "Give the plan a name of up to 200 characters.",
    invalid_value: "Give it a name of up to 200 characters.",
    plan_exists: "That plan already exists.",
    invalid_step:
      "Check the step: every field is needed, and the month must be one of the next twelve.",
    not_income: "Choose money coming in, like a paycheck, as the job.",
    invalid_mark: "An item can't depend on itself.",
    already_marked: "That's already marked.",
    invalid_goal: "Enter a number of months from 1 to 60, or a rate from 0.01% to 100%.",
    invalid_retirement: "One of the retirement assumptions is out of range. Nothing was saved.",
    not_money: "Only money in or out can go through an account.",
    not_a_cash_account:
      "Choose a checking, savings, or other account; not a debt or a retirement account.",
    cannot_link_a_balance: "Accounts and debts can't be linked to values.",
    invalid_balance: "Give it a name and choose what kind it is.",
    invalid_reading: "Check the date and the amounts.",
    not_owner: "Only an owner can update the balance.",
    not_a_balance: "That isn't an account or a debt.",
    not_a_value: "You can only link to one of your values.",
    cannot_link_a_value: "A value can't be linked to another value.",
    unknown_action: "That didn't work.",
    file_unreadable:
      "The household file can't be read: it was changed outside Findependence. Nothing was saved. Put back an earlier copy of the file, or ask for help.",
    household_full:
      "This household holds 2,000 items, the most it can. Delete some before adding more. Nothing was saved.",
    file_changed:
      "The household file was changed by another copy of Findependence while you were working. Nothing was saved, so nothing was lost. The page now shows the latest version; please try again."
  }

  @doc "The message for a refusal's reason."
  def error_text(reason), do: Map.get(@errors, reason, "That didn't work.")

  @doc "Every reason with its own message."
  def error_reasons, do: Map.keys(@errors)
end
