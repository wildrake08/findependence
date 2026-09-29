defmodule FindependenceShared.Names do
  @moduledoc "The rule for a name a member gives anything (REQ-157, DEF-049), the same in both forms (WI-072)."

  alias Findependence.Import

  @doc """
  A name as the member typed it, checked by the rule a saved file is checked against (REQ-157, DEF-049):
  1 to 200 characters once spaces at either end are removed. Returns `{:ok, name}` or `{:error, message}`.
  """
  def name(text) do
    name = String.trim(to_string(text || ""))

    cond do
      name == "" ->
        {:error, "Give it a name."}

      String.length(name) > Import.max_text() ->
        {:error, "Use #{Import.max_text()} characters or fewer."}

      true ->
        {:ok, name}
    end
  end
end
