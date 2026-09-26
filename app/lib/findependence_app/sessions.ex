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

  def count(server \\ __MODULE__), do: Agent.get(server, &map_size/1)

  defp now, do: System.monotonic_time(:millisecond)
end
