defmodule FindependenceApp.Store do
  @moduledoc """
  Holds the household's vault and serializes every change to it: refresh the acting member's
  session on the latest vault, run one core operation, save, and write the file atomically.

  F-16 (WI-026): the Store remembers a fingerprint of the file it last read or wrote. If another
  process (a second copy of the app, a restore, a sync tool) changed the file since, the Store
  reloads it: reads show the new content, and a change in flight is refused with `:file_changed`
  rather than overwriting what the other process wrote. The member sees the latest version and
  can try again.

  WI-079 (the security assessment's FND-17): a file that can no longer be read (malformed, or holding data
  that isn't plain; `Vault.read!` refuses it) doesn't stop the server. The Store keeps the last copy it could
  read for reading, refuses every change with `:file_unreadable` until the file is readable again, and logs
  one line without the file's contents. A file unreadable at start stops the server with a message.
  """
  use GenServer

  alias FindependenceApp.{Session, Vault}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def vault(server \\ __MODULE__), do: GenServer.call(server, :vault)

  @doc "Unlocks a member against the current vault."
  def open(member, passphrase, server \\ __MODULE__),
    do: Session.open(vault(server), member, passphrase)

  @doc """
  Runs `fun` (a core operation on a Household) as the session's member. Returns
  `{:ok, session}` on the refreshed, saved session, or `{:error, reason, session}`.
  """
  def apply(session, fun, server \\ __MODULE__),
    do: GenServer.call(server, {:apply, session, fun})

  @doc "The session rebuilt on the latest vault, for reading."
  def refresh(session, server \\ __MODULE__), do: Session.refresh(session, vault(server))

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    {:ok, load(%{path: path})}
  end

  @impl true
  def handle_call(:vault, _from, st) do
    {_changed?, st} = sync(st)
    {:reply, st.vault, st}
  end

  def handle_call({:apply, session, fun}, _from, st) do
    case sync(st) do
      {:unreadable, st} ->
        {:reply, {:error, :file_unreadable, Session.refresh(session, st.vault)}, st}

      {true, st} ->
        # Another process wrote the file: don't overwrite it; show the member the latest version.
        {:reply, {:error, :file_changed, Session.refresh(session, st.vault)}, st}

      {false, st} ->
        s = Session.refresh(session, st.vault)

        case fun.(s.household) do
          {:error, reason} ->
            {:reply, {:error, reason, s}, st}

          ok ->
            saved = Session.save(%{s | household: elem(ok, 1)})
            Vault.write!(saved.vault, st.path)
            {:reply, {:ok, saved}, %{st | vault: saved.vault, fingerprint: fingerprint(st.path)}}
        end
    end
  end

  # Reloads if the file on disk differs from what this Store last read or wrote; an unreadable file leaves
  # the last good copy in place.
  defp sync(st) do
    if fingerprint(st.path) == st.fingerprint do
      {false, st}
    else
      try do
        {true, load(st)}
      rescue
        e ->
          require Logger

          Logger.error(
            "the household file can't be read (#{inspect(e.__struct__)}); keeping the last copy"
          )

          {:unreadable, st}
      end
    end
  end

  defp load(st) do
    fp = fingerprint(st.path)
    Map.merge(st, %{vault: Vault.read!(st.path), fingerprint: fp})
  end

  defp fingerprint(path), do: :crypto.hash(:sha256, File.read!(path))
end
