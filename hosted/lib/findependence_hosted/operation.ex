defmodule FindependenceHosted.Operation do
  @moduledoc """
  The hosted form's persistence (WI-074; REV-083 D2; DP-001 section 10): one core rule, run as the scope's
  member in a database transaction that locks the household (REV-099 G5), so a household's changes apply one at
  a time, as the local form's single writer applies them. Each run loads the latest state, pins members' keys
  (G4), rebuilds the member's view, runs the rule, seals the result with the shared envelope code, and writes
  what changed. It implements `FindependenceShared.Persistence`; it holds no rules.
  """

  @behaviour FindependenceShared.Persistence

  alias FindependenceHosted.{Domain, Limits, Repo, RequestRefs, Sessions}
  alias FindependenceHosted.Domain.View
  alias FindependenceShared.{Envelope, Failure, Scope}

  @impl true
  def run(%Scope{session: %View{household_id: hid, member: m} = view}, fun) do
    # a member's changes in 15 minutes are bounded (REQ-190 AC-6 as CP-025 adds it; WI-080)
    if Limits.limited?([{:writes, m}]),
      do: {:error, Failure.category(:too_many_changes), :too_many_changes, view},
      else: run_counted(hid, m, view, fun)
  end

  defp run_counted(hid, m, view, fun) do
    Repo.transaction(fn ->
      :ok = Domain.lock!(hid)
      state = Domain.load(hid)
      view = view |> Domain.pin(state) |> Domain.refresh(state)

      case fun.(view.household) do
        {:error, reason} ->
          Repo.rollback({:refused, reason, view})

        ok when is_tuple(ok) and elem(ok, 0) == :ok ->
          # every page loads the whole household, so its size is bounded (REQ-190 AC-4; ASSESS-001 FND-10), per
          # member (as CP-028 amends it; ASSESS-002 FND-204), so a refusal says nothing about others' items
          if grows_past_limit?(m, view.household, elem(ok, 1)),
            do: Repo.rollback({:refused, :items_full, view})

          # REQ-199 (WI-085): requests keyed by number again for saving, and as members see them after
          saved = Envelope.save(%{view | household: RequestRefs.back(view, elem(ok, 1))})
          {:ok, departed} = Domain.write(hid, state, saved.vault)
          {RequestRefs.out(saved), departed}
      end
    end)
    |> case do
      {:ok, {saved, departed}} ->
        Limits.count([{:writes, m}])
        # a member who left keeps no session in the household (REQ-183 AC-2)
        for m <- departed, do: Sessions.drop_membership(m)
        {:ok, saved}

      {:error, {:refused, reason, view}} ->
        {:error, Failure.category(reason), reason, view}
    end
  end

  @doc "The most items a member owns (REQ-190 AC-4): 2,000, unless configured otherwise (tests)."
  def max_items, do: Application.get_env(:findependence_hosted, :max_items, 2_000)

  # A change that takes the member past max_items/0 items they own is refused. Items given to someone else still
  # count somewhere, so the household holds at most max_items/0 per member: a change taking it past that is
  # refused too, with the same words (it can only bind once some member holds more than the limit, by being
  # given items).
  defp grows_past_limit?(m, before, after_) do
    owned = fn h -> Enum.count(h.items, fn {_, i} -> m in i.owners end) end
    mine = owned.(after_)
    ceiling = max_items() * max(Enum.count(after_.members), 1)

    (mine > max_items() and mine > owned.(before)) or
      (map_size(after_.items) > ceiling and map_size(after_.items) > map_size(before.items))
  end

  @impl true
  def refresh(%Scope{session: %View{household_id: hid} = view}),
    do: Scope.new(Domain.refresh(view, Domain.load(hid)))
end
