defmodule FindependenceHosted.TestStore do
  @moduledoc """
  WI-086: a household's records are one encrypted block (`FindependenceHosted.Domain`), so tests reach them as
  the two attackers can. Whoever can write only the database can change bytes, copy blocks between households,
  and put back an earlier copy (`corrupt/1`, `snapshot/1`, `restore/2`); the operator, who holds the keys, can
  change the records themselves and write a fresh block and code (`as_operator/2`).
  """
  import Ecto.Query

  alias FindependenceHosted.{Domain, Repo}
  alias FindependenceHosted.Schemas.{Household, Membership}

  @doc "The household's records (items, proposals, next_proposal, personal), opened with the server's key."
  def held(hid) do
    {:ok, held} = Domain.open(hid)
    held
  end

  @doc "Every household's items together (what a count of the old items table gave)."
  def all_items do
    for %{id: hid} <- Repo.all(Household), {:ok, held} <- [Domain.open(hid)], reduce: %{} do
      acc -> Map.merge(acc, held.items)
    end
  end

  @doc "The operator changes the records with `fun` and writes a fresh block and code; returns the counter."
  def as_operator(hid, fun) do
    {:ok, version} = Domain.store!(hid, fun.(held(hid)))
    version
  end

  @doc "What a database copy holds of the household's own row and its members' rows."
  def snapshot(hid) do
    h = Repo.get!(Household, hid)

    %{
      household: Map.take(h, [:state_box, :version, :state_mac, :next_proposal]),
      members: Repo.all(from(m in Membership, where: m.household_id == ^hid))
    }
  end

  @doc "The database writer puts a copy back (the household's row; members as they were)."
  def restore(hid, %{household: fields}) do
    from(h in Household, where: h.id == ^hid) |> Repo.update_all(set: Map.to_list(fields))
  end

  @doc "The database writer changes one byte of the block."
  def corrupt(hid) do
    %{state_box: box} = Repo.get!(Household, hid)
    n = byte_size(box) - 1
    <<head::binary-size(^n), last>> = box

    from(h in Household, where: h.id == ^hid)
    |> Repo.update_all(set: [state_box: head <> <<Bitwise.bxor(last, 1)>>])
  end
end
