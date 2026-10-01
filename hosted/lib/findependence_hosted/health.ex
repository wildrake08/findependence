defmodule FindependenceHosted.Health do
  @moduledoc """
  What readiness depends on (REQ-196, WI-084): the database answers a trivial query. Kept out of the web layer,
  which names no storage internals (REQ-188 AC-2).
  """

  @doc "Whether the database answers a trivial query within two seconds."
  def database_reachable? do
    match?(
      {:ok, _},
      Ecto.Adapters.SQL.query(FindependenceHosted.Repo, "SELECT 1", [], timeout: 2_000)
    )
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
