defmodule FindependenceHosted.Operation do
  @moduledoc """
  The hosted form's persistence (WI-074; REV-083 D2; DP-001 section 10): one core rule, run as the scope's
  member in a database transaction that locks the household (REV-099 G5), so a household's changes apply one at
  a time, as the local form's single writer applies them. Each run loads the latest state, pins members' keys
  (G4), rebuilds the member's view, runs the rule, seals the result with the shared envelope code, and writes
  what changed. It implements `FindependenceShared.Persistence`; it holds no rules.
  """

  @behaviour FindependenceShared.Persistence

  alias FindependenceHosted.{Domain, Repo, Sessions}
  alias FindependenceHosted.Domain.View
  alias FindependenceShared.{Envelope, Failure, Scope}

  @impl true
  def run(%Scope{session: %View{household_id: hid} = view}, fun) do
    Repo.transaction(fn ->
      :ok = Domain.lock!(hid)
      state = Domain.load(hid)
      view = view |> Domain.pin(state) |> Domain.refresh(state)

      case fun.(view.household) do
        {:error, reason} ->
          Repo.rollback({:refused, reason, view})

        ok ->
          saved = Envelope.save(%{view | household: elem(ok, 1)})
          {:ok, departed} = Domain.write(hid, state, saved.vault)
          {saved, departed}
      end
    end)
    |> case do
      {:ok, {saved, departed}} ->
        # a member who left keeps no session in the household (REQ-183 AC-2)
        for m <- departed, do: Sessions.drop_membership(m)
        {:ok, saved}

      {:error, {:refused, reason, view}} ->
        {:error, Failure.category(reason), reason, view}
    end
  end

  @impl true
  def refresh(%Scope{session: %View{household_id: hid} = view}),
    do: Scope.new(Domain.refresh(view, Domain.load(hid)))
end
