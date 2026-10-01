defmodule FindependenceHosted.RequestRefs do
  @moduledoc """
  The identifiers members see for requests (REQ-199, WI-085; ASSESS-002 FND-205). Core numbers a household's
  requests in order, and the stored rows keep those numbers; a member's view is keyed instead by an identifier
  derived from the household and the number under a key held outside the database, so it looks random and
  says nothing about how many requests others have made. The rules don't care what a request's key is, so the
  view is re-keyed when it is built (`out/1`) and keyed back by number just before it is saved (`back/2`).
  """

  @info "findependence request identifiers v1"

  @doc "The identifier members see for request `n` of a household: 12 URL-safe characters."
  def ref(household_id, n) when is_integer(n) do
    :crypto.mac(:hmac, :sha256, key(), [Ecto.UUID.dump!(household_id), <<n::64>>])
    |> binary_part(0, 9)
    |> Base.url_encode64(padding: false)
  end

  @doc "A view whose household's requests are keyed by their identifiers."
  def out(%{household_id: hid, household: h} = view),
    do: %{view | household: %{h | proposals: rekey(h.proposals, &ref(hid, &1))}}

  @doc """
  A household from a view (as `out/1` keyed it, after the rules ran) keyed by number again: identifiers back to
  the numbers they came from (the stored requests' numbers); a request the rules just made keeps its number.
  """
  def back(%{household_id: hid, vault: vault}, h) do
    numbers = Map.new(Map.keys(vault.proposals), &{ref(hid, &1), &1})

    %{
      h
      | proposals:
          rekey(h.proposals, fn k -> if is_integer(k), do: k, else: Map.fetch!(numbers, k) end)
    }
  end

  defp rekey(proposals, f), do: Map.new(proposals, fn {k, p} -> {f.(k), p} end)

  defp key,
    do:
      :crypto.mac(
        :hmac,
        :sha256,
        Application.fetch_env!(:findependence_hosted, :household_state_key),
        @info
      )
end
