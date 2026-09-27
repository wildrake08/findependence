defmodule Findependence.Ledger do
  @moduledoc """
  MEC-003: per-item append-only record of ownership and visibility changes (REQ-105).

  Entries are only ever appended. `read/3` returns the full ledger of an item to its
  current owners and to nobody else.
  """

  @events [
    :created,
    :owners_changed,
    :owner_relinquished,
    :granted,
    :grant_revoked,
    :grantee_departed,
    :reading_added
  ]

  @doc false
  def record(h, item_id, actors, event, details) when event in @events do
    entries = Map.get(h.ledger, item_id, [])

    entry = %{
      seq: length(entries) + 1,
      event: event,
      by: Enum.sort(List.wrap(actors)),
      details: details
    }

    %{h | ledger: Map.put(h.ledger, item_id, entries ++ [entry])}
  end

  @doc "Content-free records of the items `actor` deleted (REQ-108). Readable only by the deleter."
  def deletions(h, actor), do: Map.get(h.deletions, actor, [])

  @doc "The item's ledger, oldest first, if `actor` currently owns the item."
  def read(h, actor, item_id) do
    case h.items[item_id] do
      %{owners: owners} ->
        if actor in owners, do: {:ok, h.ledger[item_id]}, else: {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end
end
