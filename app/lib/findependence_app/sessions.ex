defmodule FindependenceApp.Sessions do
  @moduledoc """
  Server-side registry of unlocked sessions, keyed by a random token. The browser holds only the
  token, in a signed cookie. Unlocked keys never leave this process. A session is discarded on
  logout, or once it has been idle for 15 minutes (REQ-123): a sweep every few seconds replaces it
  with a marker that holds no keys, so the next request can still say the app locked itself (UX-001
  R4). Logging in replaces any other active session, so one member at a time uses the device (ASM-022).
  """
  use Agent

  @idle_ms 15 * 60 * 1000
  @sweep_ms 5_000

  def idle_ms, do: @idle_ms

  # DEF-039 (WI-052): the sweeper is linked to the agent, so it stops with it.
  def start_link(opts) do
    every = Keyword.get(opts, :sweep_ms, @sweep_ms)
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn ->
        agent = self()
        spawn_link(fn -> sweep_every(agent, every) end)
        # DEF-051 (REQ-165): the forms each member has saved, kept across their sessions while the
        # server runs. It holds member names, random form tokens, and the address the form went to;
        # nothing from the household. Owned by the agent, so it goes when the agent stops.
        :ets.new(saved_table(name), [:named_table, :public, :set])
        %{}
      end,
      name: name
    )
  end

  defp saved_table(server), do: :"#{server}.saved_forms"

  @doc "Where `member`'s form `form` went, if they saved it in any session since the server started."
  def saved(member, form, server \\ __MODULE__) do
    case :ets.lookup(saved_table(server), {member, form}) do
      [{_, where}] -> where
      [] -> nil
    end
  end

  defp sweep_every(agent, every) do
    Process.sleep(every)
    sweep(now(), agent)
    sweep_every(agent, every)
  end

  @doc """
  Replaces every session idle for longer than the limit with a marker that holds nothing but its
  time: no session, keys, waiting file, or form tokens (REQ-123).
  """
  def sweep(now \\ now(), server \\ __MODULE__),
    do:
      Agent.update(server, fn sessions ->
        Map.new(sessions, fn
          {_token, %{expired: true}} = kept ->
            kept

          {token, %{at: at} = e} when now - at > @idle_ms ->
            {token, %{expired: true, at: at, member: member_of(e)}}

          kept ->
            kept
        end)
      end)

  def put(session, now \\ now(), server \\ __MODULE__) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    Agent.update(server, fn _ -> %{token => %{session: session, at: now}} end)
    token
  end

  @doc """
  The live session for `token`, touching its idle timer. `{:locked, :expired}` if it timed out
  (so the interface can say so, UX-001 R4), `:locked` if it is unknown.
  """
  def fetch(token, now \\ now(), server \\ __MODULE__) do
    Agent.get_and_update(server, fn sessions ->
      case sessions[token] do
        %{expired: true} ->
          {{:locked, :expired}, Map.delete(sessions, token)}

        %{at: at} = entry when now - at <= @idle_ms ->
          {{:ok, entry.session}, Map.put(sessions, token, %{entry | at: now})}

        %{} ->
          {{:locked, :expired}, Map.delete(sessions, token)}

        nil ->
          {:locked, sessions}
      end
    end)
  end

  @doc "Whether `token` names an unlocked session that hasn't idled out. Reads only; touches nothing."
  def live?(token, now \\ now(), server \\ __MODULE__),
    do:
      Agent.get(server, fn sessions ->
        match?(%{session: _, at: at} when now - at <= @idle_ms, sessions[token])
      end)

  def update(token, session, server \\ __MODULE__),
    do:
      Agent.update(server, fn sessions ->
        case sessions[token] do
          %{session: _} = e -> Map.put(sessions, token, %{e | session: session})
          _ -> sessions
        end
      end)

  def drop(token, server \\ __MODULE__), do: Agent.update(server, &Map.delete(&1, token))

  @doc """
  REQ-158: a checked file waiting for the member to confirm, held beside their session and dropped
  with it (on locking, on idling out, or when a new session replaces it). Never written to disk.
  """
  def put_pending(token, pending, server \\ __MODULE__),
    do:
      Agent.update(server, fn sessions ->
        if match?(%{session: _}, sessions[token]),
          do: Map.update!(sessions, token, &Map.put(&1, :pending, pending)),
          else: sessions
      end)

  @doc "Takes the waiting file, if any, leaving none."
  def take_pending(token, server \\ __MODULE__),
    do:
      Agent.get_and_update(server, fn sessions ->
        case sessions[token] do
          %{pending: p} = e -> {p, Map.put(sessions, token, Map.delete(e, :pending))}
          _ -> {nil, sessions}
        end
      end)

  @doc """
  REQ-165 (UX-004 P1): claims a form's one-time token for this session. `:fresh` the first time (the
  token is then marked busy until `settle_form/4`); `{:repeat, where}` if that form already changed
  the household; `:busy` while its first sending is still being handled. An unknown or locked session
  is `:fresh`: the request is refused as locked anyway. Every form a session sends is remembered for
  the session's life (DEF-041, WI-052), so a repeat is caught however many forms came between.
  """
  def claim_form(token, form, server \\ __MODULE__, now \\ now()),
    do:
      Agent.get_and_update(server, fn sessions ->
        entry = sessions[token]
        member = entry && (entry[:member] || member_of(entry))
        saved = member && saved(member, form, server)
        expired? = match?(%{expired: true}, entry) or (entry && now - entry.at > @idle_ms)

        case entry do
          # DEF-051: the session has idled out, but this member already saved this form
          %{} when expired? and saved != nil ->
            {{:repeat_locked, saved}, sessions}

          %{session: _} when saved != nil ->
            {{:repeat, saved}, sessions}

          %{session: _} ->
            forms = Map.get(entry, :forms, %{})

            case forms[form] do
              nil -> {:fresh, Map.put(sessions, token, put_form(entry, form, :busy))}
              :busy -> {:busy, sessions}
              {:done, where} -> {{:repeat, where}, sessions}
            end

          _ ->
            {:fresh, sessions}
        end
      end)

  @doc "Records where a form that changed the household went, or forgets it (`nil`) so it may be sent again."
  def settle_form(token, form, where, server \\ __MODULE__),
    do:
      Agent.update(server, fn sessions ->
        case sessions[token] do
          %{session: _} = entry when where == nil ->
            forms = entry |> Map.get(:forms, %{}) |> Map.delete(form)
            Map.put(sessions, token, Map.put(entry, :forms, forms))

          %{session: %{member: m}} = entry ->
            :ets.insert(saved_table(server), {{m, form}, where})
            Map.put(sessions, token, put_form(entry, form, {:done, where}))

          _ ->
            sessions
        end
      end)

  defp put_form(entry, form, state),
    do: Map.put(entry, :forms, entry |> Map.get(:forms, %{}) |> Map.put(form, state))

  def count(server \\ __MODULE__), do: Agent.get(server, &map_size/1)

  defp now, do: System.monotonic_time(:millisecond)

  defp member_of(%{session: %{member: m}}), do: m
  defp member_of(_), do: nil
end
