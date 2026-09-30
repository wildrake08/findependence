defmodule FindependenceHosted.Sessions do
  @moduledoc """
  Signed-in sessions (REQ-183, REV-094 H4), as the local form's Sessions: a random token in a signed cookie, and
  here, in memory only, the member's unwrapped private key. A session is discarded at sign-out, after 15 idle
  minutes (a sweep every few seconds, leaving a keyless marker so the next request can say why), and when the
  member changes their passphrase or leaves, for every other session of theirs. Nothing here is written to the
  database, a log, or telemetry; an ended session writes one content-free audit record (REQ-191 AC-1), naming
  the account and household, not the token.
  """
  use GenServer

  alias FindependenceHosted.Audit

  @table __MODULE__

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule()
    {:ok, nil}
  end

  @doc "Starts a session for a signed-in account; returns its token."
  def put(%{account_id: _, private_key: _, public_key: _} = data) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    :ets.insert(@table, {token, Map.merge(data, %{touched: now(), membership: nil})})
    token
  end

  @doc """
  The session for a token, refreshed as used: `{:ok, data}`, `{:ended, :idle, membership_id}` for one the idle
  limit ended (the membership id, or nil, lets the next request say whether its form was saved, REQ-165), or
  `:none`.
  """
  def fetch(token) when is_binary(token) do
    case :ets.lookup(@table, token) do
      [{^token, {:idle, mid}}] ->
        :ets.delete(@table, token)
        {:ended, :idle, mid}

      [{^token, data}] ->
        if now() - data.touched > idle_ms() do
          :ets.delete(@table, token)
          ended(data)
          {:ended, :idle, data.membership && data.membership.id}
        else
          data = %{data | touched: now()}
          :ets.insert(@table, {token, data})
          {:ok, data}
        end

      [] ->
        :none
    end
  end

  def fetch(_), do: :none

  @doc "Records the member's household membership in the session."
  def put_membership(token, membership) do
    case :ets.lookup(@table, token) do
      [{^token, %{} = data}] -> :ets.insert(@table, {token, %{data | membership: membership}})
      _ -> :ok
    end
  end

  @doc "Ends a session."
  def drop(token), do: :ets.delete(@table, token)

  @doc "Ends every session of an account except `keep` (REQ-183 AC-2)."
  def drop_account(account_id, keep \\ nil) do
    for {token, %{account_id: ^account_id} = data} <- :ets.tab2list(@table), token != keep do
      drop(token)
      ended(data)
    end

    :ok
  end

  @doc "Ends every session in a membership, when the member leaves (REQ-183 AC-2, WI-074)."
  def drop_membership(membership_id) do
    for {token, %{membership: %{id: ^membership_id}} = data} <- :ets.tab2list(@table) do
      drop(token)
      ended(data)
    end

    :ok
  end

  @doc """
  A checked bring-in file waiting between its preview and its confirmation (REQ-158; REV-103 I2), held with the
  session in memory only, and gone with it.
  """
  def put_pending(token, pending) do
    case :ets.lookup(@table, token) do
      [{^token, %{} = data}] -> :ets.insert(@table, {token, Map.put(data, :pending, pending)})
      _ -> false
    end
  end

  @doc "The waiting bring-in file, if any."
  def pending(token) do
    case :ets.lookup(@table, token) do
      [{^token, %{pending: p}}] -> p
      _ -> nil
    end
  end

  @doc "Takes the waiting bring-in file away (it is used or dropped)."
  def take_pending(token) do
    case :ets.lookup(@table, token) do
      [{^token, %{pending: p} = data}] ->
        :ets.insert(@table, {token, Map.delete(data, :pending)})
        p

      _ ->
        nil
    end
  end

  @doc "Whether any session holds a key for this account (tests)."
  def held?(account_id),
    do: Enum.any?(:ets.tab2list(@table), &match?({_, %{account_id: ^account_id}}, &1))

  @doc "Runs the idle sweep now (tests)."
  def sweep, do: GenServer.call(__MODULE__, :sweep)

  @impl true
  def handle_call(:sweep, _from, st), do: {:reply, do_sweep(), st}

  @impl true
  def handle_info(:sweep, st) do
    do_sweep()
    schedule()
    {:noreply, st}
  end

  # An idle session's key is discarded; a keyless marker tells its next request why it is signed out.
  defp do_sweep do
    limit = now() - idle_ms()

    for {token, %{touched: t} = data} <- :ets.tab2list(@table), t < limit do
      :ets.insert(@table, {token, {:idle, data.membership && data.membership.id}})
      ended(data)
    end

    :ok
  end

  defp ended(data) do
    Audit.record("session_ended", :ok, %{
      account_id: data.account_id,
      household_id: data.membership && data.membership.household_id
    })
  end

  defp schedule, do: Process.send_after(self(), :sweep, config(:sweep_ms))
  defp idle_ms, do: config(:idle_ms)
  defp config(key), do: Application.fetch_env!(:findependence_hosted, :sessions)[key]
  defp now, do: System.monotonic_time(:millisecond)
end
