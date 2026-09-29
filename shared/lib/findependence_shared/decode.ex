defmodule FindependenceShared.Decode do
  @moduledoc """
  Decoding what a member typed into a form, for both forms' transports (WI-075, CP-021; moved without change
  from the local form's router). Decoding only: the ranges and rules are core's and the contexts' (WI-068).
  """

  alias FindependenceShared.Money

  @frequencies %{
    "one_off" => :one_off,
    "weekly" => {:every, 1, :week},
    "biweekly" => {:every, 2, :week},
    "monthly" => {:every, 1, :month},
    "every_2_months" => {:every, 2, :month},
    "every_3_months" => {:every, 3, :month},
    "twice_a_year" => {:every, 6, :month},
    "yearly" => {:every, 1, :year},
    "irregular" => :irregular
  }

  # A borrowing step's figures as typed: {:ok, %{amount:, rate_bp:, payment:}} or :error. Their ranges are
  # core's (REQ-142, Plans.valid_borrow?/1), checked by the Planning context.
  def borrow(p) do
    with {:ok, amount} when is_integer(amount) <- Money.parse(p["amount"], "in"),
         {:ok, bp} <- rate(p["rate"]),
         {:ok, pay} when is_integer(pay) <- Money.parse(p["payment"], "in") do
      {:ok, %{amount: amount, rate_bp: bp, payment: pay}}
    else
      _ -> :error
    end
  end

  # A whole number as typed: {:ok, n}, {:ok, nil} when empty, or :error.
  def int(raw) do
    case String.trim(raw || "") do
      "" ->
        {:ok, nil}

      t ->
        case Integer.parse(t) do
          {n, ""} -> {:ok, n}
          _ -> :error
        end
    end
  end

  # a yearly return in percent, after inflation, as basis points: "5" is 500, "-1.5" is -150
  def return(raw) do
    case Regex.run(~r/\A([-−])?(\d{1,2})(?:\.(\d{1,2}))?\z/u, String.trim(raw || "")) do
      nil ->
        if String.trim(raw || "") == "", do: {:ok, nil}, else: :error

      [_, sign, whole | frac] ->
        f = frac |> List.first("") |> String.pad_trailing(2, "0")
        bp = String.to_integer(whole) * 100 + String.to_integer(f)
        {:ok, if(sign in ["-", "−"], do: -bp, else: bp)}
    end
  end

  # a monthly amount in today's dollars; zero clears it
  def monthly_money(raw) do
    case Money.parse(raw || "", "in") do
      {:ok, 0} -> {:ok, nil}
      {:ok, c} -> {:ok, c}
      {:error, msg} -> {:error, msg}
    end
  end

  # A balance as typed: {:ok, cents_or_nil, negative?} or :error. Whether it may be negative is the
  # domain's (REQ-131: an account may be overdrawn, a debt's amount owed may not).
  def balance(text) do
    raw = String.trim(text || "")
    negative? = String.starts_with?(raw, ["-", "−"])

    unsigned =
      if negative?,
        do: raw |> String.replace_prefix("-", "") |> String.replace_prefix("−", ""),
        else: raw

    case Money.parse(unsigned, "in") do
      {:ok, cents} -> {:ok, cents, negative?}
      {:error, _} -> :error
    end
  end

  def date(text) do
    case Date.from_iso8601(String.trim(text || "")) do
      {:ok, d} -> {:ok, Date.to_iso8601(d)}
      _ -> :error
    end
  end

  # A rate as a percentage, as basis points: "22", "21.9", and "21.99" are all rates; an unmatched
  # decimal group is simply absent. Its range is the domain's.
  def rate(text) do
    rate = String.trim(text || "") |> String.replace_suffix("%", "") |> String.trim()

    case Regex.run(~r/^(\d{1,3})(?:\.(\d{1,2}))?$/, rate) do
      [_, whole | frac] ->
        {:ok,
         String.to_integer(whole) * 100 +
           String.to_integer(String.pad_trailing(List.first(frac, ""), 2, "0"))}

      _ ->
        :error
    end
  end

  @doc "An account's kinds as the form names them, and the stored kind (REQ-171)."
  def account_types,
    do: %{
      "checking" => :checking,
      "savings" => :savings,
      "other" => :other,
      "retirement_401k" => :retirement_401k,
      "ira" => :ira
    }

  @doc "A debt's kinds as the form names them, and the stored kind (REQ-171)."
  def debt_types,
    do: %{
      "card" => :card,
      "heloc" => :heloc,
      "loan" => :loan,
      "other" => :other
    }

  @doc "The stored frequency for a form's choice, or nil (REQ-129)."
  def frequency(choice), do: Map.get(@frequencies, choice)

  @doc "The form's frequency choices and their stored terms."
  def frequencies, do: @frequencies
end
