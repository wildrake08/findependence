defmodule Findependence.Attach do
  @moduledoc """
  CP-014 A: which cash account an item goes through, as each member says, privately (MEC-023).

  An attachment is kept with the member's goals in their own private record, like links, so it
  changes without editing the item and nobody else can read it (REQ-160). For that member, a
  running balance or projection counts the items they have attached to one of the accounts it starts
  from, and the items they own that they haven't attached anywhere (REQ-161, REQ-162). An item
  someone else only shares with them counts once they attach it; the kids' tuition, shared for
  information and attached nowhere, still doesn't.
  """

  alias Findependence.{Balances, Plans, View}

  @doc "Every atom an attachment can add to the private record, for decoders."
  def format_atoms, do: [:attached]

  @doc "The member's attachments whose item and account they can still see: `%{item_id => account_id}`."
  def attached(h, m) do
    for {i, a} <- Map.get(Plans.goals(h, m), :attached, %{}),
        View.visible?(h, m, i) and View.visible?(h, m, a),
        into: %{},
        do: {i, a}
  end

  @doc """
  Says `item` goes through `account` for member `m`, or clears it with `nil` (REQ-160). The item must
  be a money item and the account a cash account (not a retirement account), both visible to them.
  """
  def attach(h, m, item, account) do
    i = h.items[item]
    a = account && h.items[account]

    cond do
      i == nil or not View.visible?(h, m, item) -> {:error, :not_found}
      not Plans.money?(i) -> {:error, :not_money}
      account == nil -> {:ok, put(h, m, Map.delete(own(h, m), item))}
      a == nil or not View.visible?(h, m, account) -> {:error, :not_found}
      not Balances.cash_account?(a) -> {:error, :not_a_cash_account}
      true -> {:ok, put(h, m, Map.put(own(h, m), item, account))}
    end
  end

  @doc """
  True if `item` counts for member `m` toward a flow starting from `accounts` (REQ-161, REQ-162): it
  is attached to one of them, or it isn't attached anywhere and they own it.
  """
  def counts?(h, m, item, accounts, attached \\ nil) do
    attached = attached || attached(h, m)

    case attached[item.id] do
      nil -> m in item.owners
      a -> a in accounts
    end
  end

  @doc "Removes every member's attachments naming a deleted item or account."
  def purge_item(h, id) do
    goals =
      Map.new(h.goals, fn
        {m, %{attached: at} = g} ->
          {m,
           %{g | attached: at |> Enum.reject(fn {i, a} -> i == id or a == id end) |> Map.new()}}

        other ->
          other
      end)

    %{h | goals: goals}
  end

  defp own(h, m), do: Map.get(Plans.goals(h, m), :attached, %{})

  defp put(h, m, at) do
    g = Map.put(Map.get(h.goals, m, %{}), :attached, at)
    %{h | goals: Map.put(h.goals, m, g)}
  end
end
