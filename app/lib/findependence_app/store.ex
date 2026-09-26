defmodule FindependenceApp.Store do
  @moduledoc """
  Holds the household's vault and serializes every change to it: refresh the acting member's
  session on the latest vault, run one core operation, save, and write the file atomically.
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
    {:ok, %{path: path, vault: Vault.read!(path)}}
  end

  @impl true
  def handle_call(:vault, _from, st), do: {:reply, st.vault, st}

  def handle_call({:apply, session, fun}, _from, st) do
    s = Session.refresh(session, st.vault)

    case fun.(s.household) do
      {:error, reason} ->
        {:reply, {:error, reason, s}, st}

      ok ->
        saved = Session.save(%{s | household: elem(ok, 1)})
        Vault.write!(saved.vault, st.path)
        {:reply, {:ok, saved}, %{st | vault: saved.vault}}
    end
  end
end
