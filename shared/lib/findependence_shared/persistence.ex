defmodule FindependenceShared.Persistence do
  @moduledoc """
  How the contexts reach a form's canonical state (REV-083 D2, WI-072). Each form implements this behaviour
  once and names its implementation in its own configuration:

      config :findependence_shared, persistence: MyForm.Operation

  The local-first form's implementation runs a core rule through the vault's single writer
  (`FindependenceApp.Operation`); the hosted form's runs it in a database transaction (WI-074). Two concrete
  forms justify the behaviour (ARCH-003 36 forbids one introduced only for symmetry); it has two callbacks and
  no generic repository functions.
  """

  alias FindependenceShared.Scope

  @doc """
  Runs `fun`, a core rule on the household, as the scope's member, and keeps the result. Returns
  `{:ok, session}` with the saved session, or `{:error, category, reason, session}` with the session on the
  latest state (`FindependenceShared.Failure` for the category). Only a scope with a session can do this.
  """
  @callback run(Scope.t(), (term() -> {:ok, term()} | {:error, atom()})) ::
              {:ok, term()} | {:error, atom(), atom(), term()}

  @doc "The scope rebuilt on the latest state, for reading."
  @callback refresh(Scope.t()) :: Scope.t()

  def run(%Scope{} = scope, fun), do: impl().run(scope, fun)
  def refresh(%Scope{} = scope), do: impl().refresh(scope)

  @doc "A new random identifier for an entry; the same in every form."
  def new_id, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  defp impl do
    case Application.get_env(:findependence_shared, :persistence) do
      nil ->
        raise "no persistence configured: set config :findependence_shared, persistence: <module>"

      module ->
        module
    end
  end
end
