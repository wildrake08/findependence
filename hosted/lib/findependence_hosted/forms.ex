defmodule FindependenceHosted.Forms do
  @moduledoc """
  REQ-165 (UX-004 P1) for the hosted form (WI-075, REV-100 H5), as the local form's Sessions keeps it: every
  form carries a one-time token. A form that changed the household is not applied again: a repeat goes where
  the first went and says so, in the same session or, for the same member, in a later one. A second sending
  while the first is being handled is told so. A sending that changed nothing frees its token. A Leave that
  was done is remembered, so a second click says it was already done.

  Held in memory only (ETS tables owned by this process): random form tokens, session tokens, membership ids,
  and the paths the forms went to; no content (REQ-187, REQ-191). Each row carries when it was written, and
  rows older than a day are swept every hour, so the tables don't grow without end (WI-079; the security
  assessment's FND-21): a form repeated more than a day later is treated as a new one.
  """
  use GenServer

  @forms :"#{__MODULE__}.forms"
  @saved :"#{__MODULE__}.saved"
  @left :"#{__MODULE__}.left"
  @keep_ms 24 * 60 * 60 * 1000
  @sweep_ms 60 * 60 * 1000

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    for t <- [@forms, @saved, @left], do: :ets.new(t, [:named_table, :public, :set])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, st) do
    sweep(now() - @keep_ms)
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, st}
  end

  @doc "Forgets every row written before `before` (a monotonic millisecond time); the hourly sweep, and tests."
  def sweep(before) do
    for t <- [@forms, @saved],
        do: :ets.select_delete(t, [{{:_, :_, :"$1"}, [{:<, :"$1", before}], [true]}])

    :ets.select_delete(@left, [{{:_, :"$1"}, [{:<, :"$1", before}], [true]}])
    :ok
  end

  @doc "How many rows the tables hold (tests)."
  def size, do: Enum.sum(for t <- [@forms, @saved, @left], do: :ets.info(t, :size))

  defp now, do: System.monotonic_time(:millisecond)

  @doc """
  Claims a form's token for a session of a member: `:fresh` the first time (the token is then busy until
  `settle/4`), `{:repeat, where}` if that form already changed the household (in any of the member's
  sessions), or `:busy` while its first sending is being handled.
  """
  def claim(token, membership_id, form) do
    case saved(membership_id, form) do
      nil ->
        if :ets.insert_new(@forms, {{token, form}, :busy, now()}) do
          :fresh
        else
          case :ets.lookup(@forms, {token, form}) do
            [{_, :busy, _}] -> :busy
            [{_, {:done, where}, _}] -> {:repeat, where}
            [] -> claim(token, membership_id, form)
          end
        end

      where ->
        {:repeat, where}
    end
  end

  @doc "Records where a form that changed the household went, or frees it (`nil`) so it may be sent again."
  def settle(token, _membership_id, form, nil), do: :ets.delete(@forms, {token, form})

  def settle(token, membership_id, form, where) do
    :ets.insert(@forms, {{token, form}, {:done, where}, now()})
    if membership_id, do: :ets.insert(@saved, {{membership_id, form}, where, now()})
    :ok
  end

  @doc "Where the member's form went, if it changed the household in any of their sessions."
  def saved(nil, _form), do: nil
  def saved(_membership_id, nil), do: nil

  def saved(membership_id, form) do
    case :ets.lookup(@saved, {membership_id, form}) do
      [{_, where, _}] -> where
      [] -> nil
    end
  end

  @doc "Remembers a Leave form that was done."
  def left(form) when is_binary(form), do: :ets.insert(@left, {form, now()})
  def left(_), do: :ok

  @doc "Whether this Leave form was already done."
  def left?(form) when is_binary(form), do: :ets.member(@left, form)
  def left?(_), do: false

  @doc "A new one-time form token."
  def new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  @doc "Forgets everything (tests)."
  def reset, do: Enum.each([@forms, @saved, @left], &:ets.delete_all_objects/1)
end
