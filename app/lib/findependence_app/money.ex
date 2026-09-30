defmodule FindependenceApp.Money do
  @moduledoc """
  Money entry and display (UX-001 R2, WI-021), defined once for both forms in `FindependenceShared.Money`
  (WI-075, CP-021). Vaults written before WI-021 stored whole units without a `:unit` key; `normalize/1`
  converts those to cents when a session is opened, which only the local form needs.
  """

  defdelegate parse(text, direction), to: FindependenceShared.Money
  defdelegate max_cents, to: FindependenceShared.Money
  defdelegate format(cents), to: FindependenceShared.Money

  @doc "The rule for a name (REQ-157, DEF-049), defined once in `FindependenceShared.Names` (WI-072)."
  defdelegate name(text), to: FindependenceShared.Names

  @doc "Converts pre-WI-021 whole-unit amounts to cents (in memory only; stored content is immutable)."
  def normalize(%{amount: a} = attrs) when is_integer(a) and not is_map_key(attrs, :unit),
    do: Map.merge(attrs, %{amount: a * 100, unit: :cents})

  def normalize(attrs), do: attrs
end
