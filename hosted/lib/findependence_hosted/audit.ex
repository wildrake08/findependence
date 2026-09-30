defmodule FindependenceHosted.Audit do
  @moduledoc """
  Content-free audit records (REQ-191, DP-001 section 9): who (an account or household identifier), what
  operation, on what resource identifier, when, through which channel, and the outcome. Never a passphrase, a
  recovery key, a token, an email address, a name, a note, an amount, or any other content.
  """

  alias FindependenceHosted.Repo
  alias FindependenceHosted.Schemas.AuditEvent

  @operations ~w(sign_up sign_in sign_out session_ended passphrase_changed recovery recovery_key_replaced household_created
                 invitation_created invitation_used invitation_withdrawn export bring_in leave account_deleted
                 operator_access)

  @doc "The operations that are audited."
  def operations, do: @operations

  @doc "Records one event. `attrs` may hold :account_id, :household_id, :resource_id; nothing else is kept."
  def record(operation, outcome, attrs \\ %{})
      when operation in @operations and outcome in [:ok, :refused] do
    %AuditEvent{
      at: DateTime.utc_now(),
      account_id: attrs[:account_id],
      household_id: attrs[:household_id],
      operation: operation,
      resource_id: attrs[:resource_id] && to_string(attrs[:resource_id]),
      channel: Map.get(attrs, :channel, "web"),
      outcome: Atom.to_string(outcome)
    }
    |> Repo.insert!()

    :ok
  end
end
