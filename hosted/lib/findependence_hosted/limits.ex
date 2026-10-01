defmodule FindependenceHosted.Limits do
  @moduledoc """
  Bounds on failed sign-in, recovery, and invitation attempts, on sign-ups, and on a member's changes (REQ-190
  AC-1, AC-5, AC-6 as CP-023 and CP-025 amend them; WI-079..WI-081). More than 10 failures for one account number
  from one client, 30 from one client, or 100 for one account number from every client together, within 15
  minutes, are refused for the rest of that window; the 100 doesn't apply on a device the account has used
  (WI-080). Counting an account per client means someone elsewhere can no longer lock a member out with 10
  guesses (the assessment's FND-06). At most 10 sign-ups from one client, and 300 changes by one member, in 15
  minutes. Counts are kept in memory (an ETS table owned by this process); a refusal gives the same response for
  known and unknown account numbers. A process is used because the counts are long-lived mutable runtime state
  (ARCH-003 10).
  """
  use GenServer

  @table __MODULE__
  @window_ms 15 * 60 * 1000
  @limits %{pair: 10, client: 30, account: 100, sign_up: 10, writes: 300}

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :duplicate_bag, write_concurrency: true])
    {:ok, nil}
  end

  @doc "True if any of the keys has reached its limit in the current window."
  def limited?(keys) do
    now = now()
    Enum.any?(keys, fn {kind, _} = key -> count(key, now) >= Map.fetch!(@limits, kind) end)
  end

  @doc "Counts one failure against each key."
  def failed(keys) do
    now = now()
    Enum.each(keys, &:ets.insert(@table, {&1, now}))
  end

  @doc "Counts one use against each key (the same as `failed/1`, for counts that aren't failures)."
  def count(keys), do: failed(keys)

  @doc "Forgets every count (tests)."
  def reset, do: :ets.delete_all_objects(@table)

  defp count(key, now) do
    stale = now - @window_ms

    for {^key, at} = row <- :ets.lookup(@table, key),
        at <= stale,
        do: :ets.delete_object(@table, row)

    length(:ets.lookup(@table, key))
  end

  defp now, do: System.monotonic_time(:millisecond)
end
