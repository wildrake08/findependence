defmodule FindependenceApp.Items do
  @moduledoc """
  Domain context Items (DP-001 section 2; CAP-001, CAP-005, MEC-002..005, MEC-016): items, their owners
  and grants, proposals and consent, relinquishing and deleting, and what the member can see.
  """

  alias FindependenceApp.{Money, Operation, Scope}
  alias Findependence.{Exit, Household, View}

  @doc """
  Adds a money item the member owns. The rules are checked here, so every transport gets the same ones:
  a name within the limit (REQ-157), how often it happens chosen by the member with no default (REQ-129),
  and an optional date, which an irregular item doesn't have (REQ-136).

  `input` is `%{note:, amount:, frequency:, on:}`: the name and date as typed, the amount as the transport
  decoded it (`{:ok, cents_or_nil}` or `{:error, message}`), and the frequency as a stored term or nil. The
  first problem is reported in the order of the form's fields: `{:error, :validation, {field, message}}`.
  """
  def add_item(%Scope{member: m} = scope, %{note: note, amount: amount, frequency: f, on: on}) do
    on = String.trim(on || "")

    with {:ok, name} <- field(:note, Money.name(note)),
         {:ok, cents} <- field(:amount, amount),
         :ok <-
           if(f == nil, do: {:error, :frequency, "Choose how often this happens."}, else: :ok),
         {:ok, on} <- date(on, f) do
      attrs = %{note: name, unit: :cents, frequency: f}
      attrs = if cents, do: Map.put(attrs, :amount, cents), else: attrs
      attrs = if on, do: Map.put(attrs, :on, on), else: attrs
      Operation.run(scope, &Household.add_item(&1, m, Operation.new_id(), attrs))
    else
      {:error, field, message} -> {:error, :validation, {field, message}}
    end
  end

  defp field(_name, {:ok, value}), do: {:ok, value}
  defp field(name, {:error, message}), do: {:error, name, message}

  defp date("", _f), do: {:ok, nil}
  defp date(_on, :irregular), do: {:ok, nil}

  defp date(on, _f) do
    if match?({:ok, _}, Date.from_iso8601(on)),
      do: {:ok, on},
      else: {:error, :on, "Enter the date, like 2026-10-01, or leave it empty."}
  end

  @doc "Proposes a grant of `item` to `grantee` (REQ-103)."
  def propose_grant(%Scope{member: m} = scope, item, grantee),
    do: Operation.run(scope, &Household.propose_grant(&1, m, item, grantee))

  @doc "Revokes `grantee`'s grant (REQ-103)."
  def revoke_grant(%Scope{member: m} = scope, item, grantee),
    do: Operation.run(scope, &Household.revoke_grant(&1, m, item, grantee))

  @doc "Proposes a new owner set (REQ-107)."
  def propose_owners(%Scope{member: m} = scope, item, owners),
    do: Operation.run(scope, &Household.propose_owners(&1, m, item, owners))

  @doc "Consents to a proposal (REQ-107, REQ-115)."
  def consent(%Scope{member: m} = scope, proposal),
    do: Operation.run(scope, &Household.consent(&1, m, proposal))

  @doc "Withdraws a pending proposal (REQ-125)."
  def withdraw(%Scope{member: m} = scope, proposal),
    do: Operation.run(scope, &Household.withdraw(&1, m, proposal))

  @doc "Removes the member from an item's owners (REQ-107)."
  def relinquish(%Scope{member: m} = scope, item),
    do: Operation.run(scope, &Household.relinquish(&1, m, item))

  @doc "Deletes an item the member solely owns (REQ-108)."
  def delete(%Scope{member: m} = scope, item), do: Operation.run(scope, &Exit.delete(&1, m, item))

  @doc """
  A sole owner's one choice for an item on the leave checklist (UX-001 R8): `:delete`, `{:give, member}`,
  or nil when nothing was chosen.
  """
  def let_go(%Scope{} = scope, item, :delete), do: delete(scope, item)
  def let_go(%Scope{} = scope, item, {:give, to}), do: propose_owners(scope, item, [to])

  def let_go(%Scope{} = scope, _item, nil),
    do: Operation.run(scope, fn _ -> {:error, :no_choice} end)

  @doc "Whether the member can see `item` (REQ-167)."
  def visible?(%Scope{member: m, session: s}, item), do: View.visible?(s.household, m, item)

  @doc "The other owners of `item`, sorted, or `[]` when the member can't see it."
  def co_owners(%Scope{member: m, session: s}, item) do
    case s.household.items[item] do
      %{owners: owners} -> owners |> MapSet.delete(m) |> Enum.sort()
      nil -> []
    end
  end
end
