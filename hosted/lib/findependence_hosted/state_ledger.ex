defmodule FindependenceHosted.StateLedger do
  @moduledoc """
  Each household's change counter, kept outside the database (REQ-198 AC-5, WI-086; ASSESS-002 FND-209): an
  append-only file on the app host (HOUSEHOLD_LEDGER_PATH; DEPLOY.md: owned by the service, `chattr +a`, backed
  up apart from the database) of lines `<household id> <counter>`. Every change the service commits records its
  new counter here; every read refuses a household whose counter in the database is lower than the one recorded,
  which is what restoring an earlier copy of it looks like. Someone who can write the database but not this file
  can no longer roll a household back unnoticed. The operator, who can write both, is trusted (REV-111).

  One node: the file is the node's own (the hosted form keeps sessions in one node's memory too).
  """
  use GenServer

  @table __MODULE__

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    path = path()
    ensure_dir(path)
    if File.exists?(path), do: read_into_table(path)
    {:ok, nil}
  end

  # The path is the operator's setting (HOUSEHOLD_LEDGER_PATH), never anything a request sends, so the file module's
  # traversal finding doesn't apply (reviewed, WI-086).
  # sobelow_skip ["Traversal.FileModule"]
  defp ensure_dir(path), do: File.mkdir_p!(Path.dirname(path))

  # sobelow_skip ["Traversal.FileModule"]
  defp read_into_table(path) do
    path
    |> File.stream!()
    |> Enum.each(fn line ->
      with [hid, n] <- String.split(String.trim(line), " "),
           {version, ""} <- Integer.parse(n),
           do: bump(hid, version)
    end)
  end

  @doc """
  Checks a household's counter as read from the database: `:ok` when it is at least the one recorded (a higher
  one, from a change committed after a crash before it was recorded, is recorded now), `{:rolled_back, recorded}`
  when it is lower.
  """
  def check(household_id, version) do
    case latest(household_id) do
      nil ->
        record(household_id, version)

      recorded when version < recorded ->
        {:rolled_back, recorded}

      recorded when version > recorded ->
        record(household_id, version)

      _ ->
        :ok
    end
  end

  @doc "Records a counter the service committed (after the commit)."
  def record(household_id, version) when is_integer(version),
    do: GenServer.call(__MODULE__, {:record, household_id, version})

  @doc "The latest counter recorded for a household, or nil."
  def latest(household_id) do
    case :ets.lookup(@table, household_id) do
      [{_, v}] -> v
      [] -> nil
    end
  end

  @doc "The file's path, from the configuration."
  def path, do: Application.fetch_env!(:findependence_hosted, :household_ledger_path)

  @impl true
  def handle_call({:record, hid, version}, _from, st) do
    if version > (latest(hid) || -1) do
      {:ok, f} = :file.open(path(), [:append, :raw, :binary])
      :ok = :file.write(f, [hid, " ", Integer.to_string(version), "\n"])
      :ok = :file.sync(f)
      :ok = :file.close(f)
      bump(hid, version)
    end

    {:reply, :ok, st}
  end

  defp bump(hid, version) do
    if version > (latest(hid) || -1), do: :ets.insert(@table, {hid, version})
  end
end
