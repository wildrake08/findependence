defmodule FindependenceShared.Contract.Helpers do
  @moduledoc """
  Helpers for the contract cases (REQ-188 AC-1, WI-074). Each takes the form module first; in a case, write
  `household(@form, ~w(ana ben))` and so on. A household is a map from name to the form's handle.
  """

  alias FindependenceShared.{Items, Scope}

  def household(form, names), do: form.household(names)

  @doc "A fresh scope for the named member."
  def scope(form, h, name), do: form.scope(Map.fetch!(h, name))

  @doc "The named member's id inside the domain rules."
  def id(form, h, name), do: form.member(Map.fetch!(h, name))

  @doc "The named member's view of the household (a core Household) on the latest state."
  def view(form, h, name), do: scope(form, h, name).household

  @doc "The household's sealed state as stored."
  def stored(form, h), do: h |> Map.values() |> hd() |> form.stored()

  @doc "Every stored value, as binaries."
  def stored_bytes(form, h), do: h |> Map.values() |> hd() |> form.stored_bytes()

  @doc """
  Adds an item for the named member through the Items context and returns its id. `opts`: :amount (cents,
  default -1000), :frequency (default :monthly), :on (default "").
  """
  def add_item(form, h, name, note, opts \\ []) do
    input = %{
      note: note,
      amount: {:ok, Keyword.get(opts, :amount, -1000)},
      frequency: Keyword.get(opts, :frequency, :monthly),
      on: Keyword.get(opts, :on, "")
    }

    {:ok, saved} = Items.add_item(scope(form, h, name), input)
    find(saved.household, note)
  end

  @doc "The id of the item with this note in a household view, or nil."
  def find(household, note),
    do: Enum.find_value(household.items, fn {id, i} -> if i.attrs[:note] == note, do: id end)

  @doc "True if the named member can read the item's content."
  def reads?(form, h, name, item), do: view(form, h, name).items[item].attrs != %{}

  @doc "Unwraps `{:ok, saved}` from a context operation and returns a scope on it."
  def ok!({:ok, saved}), do: Scope.new(saved)
  def ok!(other), do: raise(ArgumentError, "expected {:ok, _}, got: #{inspect(other, limit: 5)}")
end
