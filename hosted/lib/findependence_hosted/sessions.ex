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

  # WI-085 (ASSESS-002 FND-203, defense in depth): the table is private to this process, so other code in the
  # node can't list it and read members' keys; everything goes through the calls below. (Code run in the node by
  # an operator can still reach this process's state; the operator is trusted, REV-111.)
  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :private, :set])
    schedule()
    {:ok, nil}
  end

  @doc "Starts a session for a signed-in account; returns its token."
  def put(%{account_id: _, private_key: _, public_key: _} = data), do: call({:put, data})

  @doc """
  The session for a token, refreshed as used: `{:ok, data}`, `{:ended, :idle, membership_id}` for one the idle
  limit ended, `{:ended, :expired, membership_id}` for one older than the fixed limit (12 hours) (the membership id, or nil, lets the next request say whether its form was saved, REQ-165), or
  `:none`.
  """
  def fetch(token) when is_binary(token), do: call({:fetch, token})
  def fetch(_), do: :none

  @doc "Records the member's household membership in the session."
  def put_membership(token, membership), do: call({:put_membership, token, membership})

  @doc "Ends a session."
  def drop(token), do: call({:drop, token})

  @doc "Ends every session of an account except `keep` (REQ-183 AC-2)."
  def drop_account(account_id, keep \\ nil), do: call({:drop_account, account_id, keep})

  @doc "Ends every session in a membership, when the member leaves (REQ-183 AC-2, WI-074)."
  def drop_membership(membership_id), do: call({:drop_membership, membership_id})

  @doc """
  A checked bring-in file waiting between its preview and its confirmation (REQ-158; REV-103 I2), held with the
  session in memory only, and gone with it.
  """
  def put_pending(token, pending), do: call({:put_pending, token, pending})

  @doc "The waiting bring-in file, if any."
  def pending(token), do: call({:pending, token})

  @doc "Takes the waiting bring-in file away (it is used or dropped)."
  def take_pending(token), do: call({:take_pending, token})

  @doc "Whether any session holds a key for this account (tests)."
  def held?(account_id), do: call({:held?, account_id})

  @doc "Runs the idle sweep now (tests)."
  def sweep, do: call(:sweep)

  @doc "Makes a session's last use (`:touched`) or its start (`:started`) `ms` earlier (tests)."
  def backdate(token, field, ms) when field in [:touched, :started],
    do: call({:backdate, token, field, ms})

  @doc "Leaves only the idle sweep's keyless marker for a session, as the sweep does (tests)."
  def mark_idle(token), do: call({:mark_idle, token})

  # The table is read and written only here. Sessions a call ends come back with its reply, and the caller
  # writes their audit records, in its own process and transaction.
  defp call(request) do
    {reply, ended} = GenServer.call(__MODULE__, request)
    Enum.each(ended, &ended/1)
    reply
  end

  @impl true
  def handle_call(request, _from, st), do: {:reply, handle(request), st}

  @impl true
  def handle_info(:sweep, st) do
    {:ok, ended} = do_sweep()
    Enum.each(ended, &ended/1)
    schedule()
    {:noreply, st}
  end

  defp handle({:put, data}) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    t = now()
    :ets.insert(@table, {token, Map.merge(data, %{touched: t, started: t, membership: nil})})
    {token, []}
  end

  defp handle({:fetch, token}) do
    case :ets.lookup(@table, token) do
      [{^token, {:idle, mid}}] ->
        :ets.delete(@table, token)
        {{:ended, :idle, mid}, []}

      [{^token, data}] ->
        cond do
          now() - data.touched > idle_ms() ->
            :ets.delete(@table, token)
            {{:ended, :idle, data.membership && data.membership.id}, [data]}

          # however it's used, a session ends after a fixed time (WI-079; REQ-183 as CP-023 amends it)
          now() - Map.get(data, :started, data.touched) > max_ms() ->
            :ets.delete(@table, token)
            {{:ended, :expired, data.membership && data.membership.id}, [data]}

          true ->
            data = %{data | touched: now()}
            :ets.insert(@table, {token, data})
            {{:ok, data}, []}
        end

      [] ->
        {:none, []}
    end
  end

  defp handle({:put_membership, token, membership}) do
    case :ets.lookup(@table, token) do
      [{^token, %{} = data}] ->
        {:ets.insert(@table, {token, %{data | membership: membership}}), []}

      _ ->
        {:ok, []}
    end
  end

  defp handle({:drop, token}), do: {:ets.delete(@table, token), []}

  defp handle({:drop_account, account_id, keep}) do
    ended =
      for {token, %{account_id: ^account_id} = data} <- :ets.tab2list(@table), token != keep do
        :ets.delete(@table, token)
        data
      end

    {:ok, ended}
  end

  defp handle({:drop_membership, membership_id}) do
    ended =
      for {token, %{membership: %{id: ^membership_id}} = data} <- :ets.tab2list(@table) do
        :ets.delete(@table, token)
        data
      end

    {:ok, ended}
  end

  defp handle({:put_pending, token, pending}) do
    case :ets.lookup(@table, token) do
      [{^token, %{} = data}] ->
        {:ets.insert(@table, {token, Map.put(data, :pending, pending)}), []}

      _ ->
        {false, []}
    end
  end

  defp handle({:pending, token}) do
    case :ets.lookup(@table, token) do
      [{^token, %{pending: p}}] -> {p, []}
      _ -> {nil, []}
    end
  end

  defp handle({:take_pending, token}) do
    case :ets.lookup(@table, token) do
      [{^token, %{pending: p} = data}] ->
        :ets.insert(@table, {token, Map.delete(data, :pending)})
        {p, []}

      _ ->
        {nil, []}
    end
  end

  defp handle({:held?, account_id}),
    do: {Enum.any?(:ets.tab2list(@table), &match?({_, %{account_id: ^account_id}}, &1)), []}

  defp handle({:backdate, token, field, ms}) do
    case :ets.lookup(@table, token) do
      [{^token, %{} = data}] ->
        {:ets.insert(@table, {token, Map.update!(data, field, &(&1 - ms))}), []}

      _ ->
        {false, []}
    end
  end

  defp handle({:mark_idle, token}) do
    case :ets.lookup(@table, token) do
      [{^token, %{} = data}] ->
        {:ets.insert(@table, {token, {:idle, data.membership && data.membership.id}}), []}

      _ ->
        {false, []}
    end
  end

  defp handle(:sweep) do
    {:ok, ended} = do_sweep()
    {:ok, ended}
  end

  # An idle session's key is discarded; a keyless marker tells its next request why it is signed out.
  defp do_sweep do
    limit = now() - idle_ms()

    ended =
      for {token, %{touched: t} = data} <- :ets.tab2list(@table), t < limit do
        :ets.insert(@table, {token, {:idle, data.membership && data.membership.id}})
        data
      end

    {:ok, ended}
  end

  defp ended(data) do
    Audit.record("session_ended", :ok, %{
      account_id: data.account_id,
      household_id: data.membership && data.membership.household_id
    })
  end

  defp schedule, do: Process.send_after(self(), :sweep, config(:sweep_ms))
  defp idle_ms, do: config(:idle_ms)
  defp max_ms, do: config(:max_ms)
  defp config(key), do: Application.fetch_env!(:findependence_hosted, :sessions)[key]
  defp now, do: System.monotonic_time(:millisecond)
end
