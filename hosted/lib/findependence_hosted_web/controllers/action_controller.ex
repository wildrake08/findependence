defmodule FindependenceHostedWeb.ActionController do
  @moduledoc """
  The household-changing forms of the item pages (WI-075), as the local form's `post "/act/:action"`: each
  calls its context with what was sent, decoded as the local form decodes it. On success it says what
  happened and goes back to where the form came from; a refusal shows that page again with the message.
  An action this form doesn't have is refused as the Households context refuses an unknown one.
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHostedWeb.{DomainWeb, ItemController}
  alias FindependenceShared.{Balances, Households, Items, Planning, Values}

  def act(conn, %{"action" => action}) do
    p = conn.body_params

    op =
      case action do
        "add_value" -> &Values.add_value(&1, p["label"])
        "grant" -> &Items.propose_grant(&1, p["item"], p["member"])
        "revoke" -> &Items.revoke_grant(&1, p["item"], p["member"])
        "owners" -> &Items.propose_owners(&1, p["item"], List.wrap(p["owners"]))
        "consent" -> &Items.consent(&1, proposal(p["proposal"]))
        "relinquish" -> &Items.relinquish(&1, p["item"])
        "delete" -> &Items.delete(&1, p["item"])
        "link" -> &Values.link(&1, p["item"], p["value"])
        # REQ-160 (CP-014 A): which account an item goes through; empty clears it
        "attach" -> &Balances.attach(&1, p["item"], blank_to_nil(p["account"]))
        "unlink" -> &Values.unlink(&1, p["item"], p["value"])
        "withdraw" -> &Items.withdraw(&1, proposal(p["proposal"]))
        "mark" -> &Planning.mark(&1, p["item"], p["job"])
        "unmark" -> &Planning.unmark(&1, p["item"], p["job"])
        # let_go, remove_step, and delete_plan come with the leave and plan pages (a later WorkItem)
        _ -> &Households.unknown_action/1
      end

    DomainWeb.act(conn, action, op, refused: &ItemController.refused/2)
  end

  # A request is named by the identifier members see (REQ-199, WI-085): 12 URL-safe characters; anything else
  # matches no request.
  defp proposal(raw) when is_binary(raw) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]{12}\z/, raw), do: raw, else: ""
  end

  defp proposal(_), do: ""

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: v
end
