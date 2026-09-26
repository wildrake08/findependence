defmodule FindependenceApp.Money do
  @moduledoc """
  Money entry and display (UX-001 R2, WI-021). Amounts are integer cents, with direction chosen
  explicitly: money out is negative. Parsing is strict. Anything not clearly an amount is an error
  with a message for the member, never a silent 0 or a truncated number.

  Vaults written before WI-021 stored whole units without a `:unit` key; `normalize/1` converts
  those to cents when a session is opened.
  """

  @doc """
  Parses what the member typed. Accepts an optional `$`, digits with optional comma thousands
  separators (in groups of three), and up to two decimal places. Direction is `"in"` or `"out"`.
  An empty amount means "no amount".
  """
  def parse(text, direction) do
    raw = text |> to_string() |> String.trim()
    text = raw |> String.replace_prefix("$", "") |> String.trim()

    cond do
      raw == "" ->
        {:ok, nil}

      String.starts_with?(text, ["-", "−", "+"]) ->
        {:error, "Enter the amount without a + or − sign, and choose Money in or Money out."}

      not Regex.match?(~r/^(\d{1,3}(,\d{3})+|\d+)(\.\d{1,2})?$/, text) ->
        {:error, "Enter an amount like 62.40 or 1,200."}

      direction not in ["in", "out"] ->
        {:error, "Choose Money in or Money out."}

      true ->
        [whole | frac] = text |> String.replace(",", "") |> String.split(".")
        cents = String.to_integer(whole) * 100 + frac_cents(frac)
        {:ok, if(direction == "out", do: -cents, else: cents)}
    end
  end

  defp frac_cents([]), do: 0
  defp frac_cents([f]), do: f |> String.pad_trailing(2, "0") |> String.to_integer()

  @doc "Shows cents as money: `-6240` becomes `\"−$62.40\"`, `320000` becomes `\"+$3,200.00\"`."
  def format(nil), do: ""
  def format(0), do: "$0.00"

  def format(cents) when is_integer(cents) do
    abs = abs(cents)
    whole = abs |> div(100) |> Integer.to_string() |> group()
    frac = abs |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    if(cents < 0, do: "−", else: "+") <> "$" <> whole <> "." <> frac
  end

  def format(other), do: to_string(other)

  defp group(digits),
    do:
      digits |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()

  @doc "Converts pre-WI-021 whole-unit amounts to cents (in memory only; stored content is immutable)."
  def normalize(%{amount: a} = attrs) when is_integer(a) and not is_map_key(attrs, :unit),
    do: Map.merge(attrs, %{amount: a * 100, unit: :cents})

  def normalize(attrs), do: attrs
end
