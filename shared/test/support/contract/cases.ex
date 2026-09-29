defmodule FindependenceShared.Contract do
  @moduledoc """
  REQ-188 AC-1 (WI-074): the contract cases, one module per group of Requirements, each defining tests on
  `@form` (a `FindependenceShared.Contract.Form`) with `FindependenceShared.Contract.Helpers` imported. A form's
  test module sets `@form`, imports the helpers, and writes `use FindependenceShared.Contract`, which uses every
  module `cases/0` lists.
  """

  defmacro __using__(_) do
    for m <- cases(), do: quote(do: use(unquote(m)))
  end

  @doc "The case modules, in order."
  def cases do
    # loaded (the local form requires the files) or compiled and not yet loaded (the hosted form compiles them)
    :code.all_available()
    |> Enum.map(&to_string(elem(&1, 0)))
    |> Enum.filter(&String.starts_with?(&1, "Elixir.FindependenceShared.Contract.Cases."))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&String.to_atom/1)
  end
end
