defmodule FindependenceApp.Operation do
  @moduledoc """
  The local-first form's persistence (DP-001 section 10, REV-083 D2): one core rule, run as the scope's
  member through `Store`, the vault's single writer. It implements `FindependenceShared.Persistence`, which the
  shared contexts use (WI-072); it holds no rules.
  """

  @behaviour FindependenceShared.Persistence

  alias FindependenceApp.{Session, Store}
  alias FindependenceShared.{Failure, Scope}

  @impl true
  def run(%Scope{session: %Session{} = session}, fun) do
    case Store.apply(session, fun) do
      {:ok, saved} -> {:ok, saved}
      {:error, reason, refreshed} -> {:error, Failure.category(reason), reason, refreshed}
    end
  end

  @impl true
  def refresh(%Scope{session: %Session{} = session}), do: Scope.new(Store.refresh(session))
end
