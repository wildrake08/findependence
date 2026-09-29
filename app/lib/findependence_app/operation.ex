defmodule FindependenceApp.Operation do
  @moduledoc """
  How a context operation reaches canonical state in the local-first form (DP-001 section 10, REV-083 D2):
  one core rule, run as the scope's member through `Store`, the vault's single writer. This is the form's
  persistence coordination, the counterpart of a Repo transaction in the hosted form; it holds no rules.
  """

  alias FindependenceApp.{Failure, Scope, Store}

  @doc """
  Runs `fun` (a core rule on the household) for the scope's member. Returns `{:ok, session}` with the
  saved session, or `{:error, category, reason, session}` with the session refreshed on the latest vault.
  """
  def run(%Scope{session: %FindependenceApp.Session{} = session}, fun) do
    case Store.apply(session, fun) do
      {:ok, saved} -> {:ok, saved}
      {:error, reason, refreshed} -> {:error, Failure.category(reason), reason, refreshed}
    end
  end

  @doc "The scope rebuilt on the latest vault, for reading."
  def refresh(%Scope{session: %FindependenceApp.Session{} = session}),
    do: Scope.new(Store.refresh(session))

  @doc "A new random identifier for an entry."
  def new_id, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
end
