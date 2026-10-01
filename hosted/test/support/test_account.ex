defmodule FindependenceHosted.TestAccount do
  @moduledoc """
  WI-081: accounts are identified by an account number issued at sign-up. Tests name each account by a label
  (often written like an address, as they were before); sign-up records the number issued for that label in
  the test's process, and sign-in and recovery look it up. A label never signed up stands for an unknown
  account: a well-formed number nobody was issued.
  """

  @doc "Records the account number and recovery key issued for `label` (from the page after sign-up)."
  def remember(label, html) when is_binary(html) do
    number = capture(html, "account-number")
    key = capture(html, "recovery-key")
    if number, do: Process.put({__MODULE__, label}, number)
    {number, key}
  end

  @doc "Records `number` for `label`."
  def remember_number(label, number), do: Process.put({__MODULE__, label}, number)

  @doc "The account number issued for `label`, or a well-formed one nobody was issued."
  def number(label) do
    Process.get({__MODULE__, label}) ||
      :crypto.hash(:sha256, "never issued " <> label)
      |> binary_part(0, 10)
      |> Base.encode32(padding: false)
      |> String.graphemes()
      |> Enum.chunk_every(4)
      |> Enum.map_join("-", &Enum.join/1)
  end

  defp capture(html, id) do
    case Regex.run(~r/id="#{id}"[^>]*>\s*([A-Z2-7-]+)\s*</, html) do
      [_, value] -> value
      _ -> nil
    end
  end
end
