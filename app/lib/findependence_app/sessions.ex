defmodule FindependenceApp.Sessions do
  @moduledoc """
  Server-side registry of unlocked sessions, keyed by a random token. The browser holds only the
  token, in a signed cookie. Unlocked keys never leave this process. A session is discarded on
  logout, or on its first use after 15 minutes idle (REQ-123). Logging in replaces any other
  active session, so one member at a time uses the device (ASM-022).
  """
  use Agent

  @idle_ms 15 * 60 * 1000

  def idle_ms, do: @idle_ms

  def start_link(opts),
    do: Agent.start_link(fn -> %{} end, name: Keyword.get(opts, :name, __MODULE__))

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
        %{at: at} = entry when now - at <= @idle_ms ->
          {{:ok, entry.session}, Map.put(sessions, token, %{entry | at: now})}

        %{} ->
          {{:locked, :expired}, Map.delete(sessions, token)}

        nil ->
          {:locked, sessions}
      end
    end)
  end

  def update(token, session, server \\ __MODULE__),
    do: Agent.update(server, &Map.update!(&1, token, fn e -> %{e | session: session} end))

  def drop(token, server \\ __MODULE__), do: Agent.update(server, &Map.delete(&1, token))

  @doc """
  REQ-158: a checked file waiting for the member to confirm, held beside their session and dropped
  with it (on locking, on idling out, or when a new session replaces it). Never written to disk.
  """
  def put_pending(token, pending, server \\ __MODULE__),
    do:
      Agent.update(server, fn sessions ->
        if Map.has_key?(sessions, token),
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

  @forms_kept 64

  @doc """
  REQ-165 (UX-004 P1): claims a form's one-time token for this session. `:fresh` the first time (the
  token is then marked busy until `settle_form/4`); `{:repeat, where}` if that form already changed
  the household; `:busy` while its first sending is still being handled. An unknown session is
  `:fresh`: the request is refused as locked anyway. The last #{@forms_kept} forms are remembered.
  """
  def claim_form(token, form, server \\ __MODULE__),
    do:
      Agent.get_and_update(server, fn sessions ->
        case sessions[token] do
          nil ->
            {:fresh, sessions}

          entry ->
            forms = Map.get(entry, :forms, %{})

            case forms[form] do
              nil -> {:fresh, Map.put(sessions, token, remember(entry, form, :busy))}
              :busy -> {:busy, sessions}
              {:done, where} -> {{:repeat, where}, sessions}
            end
        end
      end)

  @doc "Records where a form that changed the household went, or forgets it (`nil`) so it may be sent again."
  def settle_form(token, form, where, server \\ __MODULE__),
    do:
      Agent.update(server, fn sessions ->
        case sessions[token] do
          nil ->
            sessions

          entry when where == nil ->
            forms = Map.get(entry, :forms, %{})
            order = Map.get(entry, :form_order, [])

            entry =
              entry
              |> Map.put(:forms, Map.delete(forms, form))
              |> Map.put(:form_order, List.delete(order, form))

            Map.put(sessions, token, entry)

          entry ->
            forms = entry |> Map.get(:forms, %{}) |> Map.put(form, {:done, where})
            Map.put(sessions, token, Map.put(entry, :forms, forms))
        end
      end)

  defp remember(entry, form, state) do
    order = Enum.take([form | Map.get(entry, :form_order, [])], @forms_kept)
    forms = entry |> Map.get(:forms, %{}) |> Map.put(form, state) |> Map.take(order)
    entry |> Map.put(:forms, forms) |> Map.put(:form_order, order)
  end

  def count(server \\ __MODULE__), do: Agent.get(server, &map_size/1)

  defp now, do: System.monotonic_time(:millisecond)
end
