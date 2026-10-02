defmodule Findependence.CoolingTest do
  @moduledoc """
  REQ-201, REQ-202 (CP-030 option A, REV-115, WI-088): changes that widen someone's access or take away a
  member's own wait out a cooling-off once every current owner has agreed; the member whose agreement a change
  rests on can cancel it alone; protective changes are immediate; leaving is never delayed.
  """
  use ExUnit.Case, async: true

  alias Findependence.{Exit, Household, Ledger, View}

  @day 86_400
  @wait 3 * @day

  defp h0 do
    h = %{Household.new([:a, :b, :c]) | cooling: @wait, now: 1_000_000}
    {:ok, h} = Household.add_item(h, :a, :rent, %{note: "Rent"})
    h
  end

  defp at(h, t), do: %{h | now: t}
  defp later(h, s), do: at(h, h.now + s)

  describe "REQ-201: what waits" do
    test "a sole owner's grant waits; the grantee sees nothing until it ends and an owner settles it" do
      {:ok, h, pid} = Household.propose_grant(h0(), :a, :rent, :b)
      refute View.visible?(h, :b, :rent)
      assert h.proposals[pid].due == h.now + @wait
      assert Household.due(h, :a) == []

      h = later(h, @wait - 1)
      assert Household.due(h, :a) == []
      {:ok, h} = Household.settle(h, :a)
      refute View.visible?(h, :b, :rent)

      h = later(h, 1)
      assert Household.due(h, :a) == [pid]
      # only an owner's session settles: it is the one that can seal the key
      assert Household.due(h, :b) == []
      {:ok, h} = Household.settle(h, :a)
      assert View.visible?(h, :b, :rent)
      assert h.proposals == %{}
    end

    test "adding an owner: the joiner isn't shown it until the window ends, then their agreement applies it at once" do
      {:ok, h, pid} = Household.propose_owners(h0(), :a, :rent, [:a, :b])
      assert Household.pending(h, :b) == []
      assert {:error, :not_found} = Household.consent(h, :b, pid)

      h = later(h, @wait)
      {:ok, h} = Household.settle(h, :a)
      assert [%{id: ^pid, attrs: %{note: "Rent"}}] = Household.pending(h, :b)
      assert h.proposals[pid].released

      {:ok, h} = Household.consent(h, :b, pid)
      assert h.items[:rent].owners == MapSet.new([:a, :b])
    end

    test "giving away waits too, and the receiver still agrees" do
      {:ok, h, pid} = Household.propose_owners(h0(), :a, :rent, [:b])
      h = later(h, @wait)
      {:ok, h} = Household.settle(h, :a)
      assert h.items[:rent].owners == MapSet.new([:a])
      {:ok, h} = Household.consent(h, :b, pid)
      assert h.items[:rent].owners == MapSet.new([:b])
    end

    test "deleting waits; the owner can cancel it; after the window it goes, with its deletion record" do
      {:ok, h, pid} = Exit.delete(h0(), :a, :rent)
      assert Map.has_key?(h.items, :rent)
      {:ok, cancelled} = Household.withdraw(h, :a, pid)
      assert cancelled.proposals == %{} and Map.has_key?(cancelled.items, :rent)

      h = later(h, @wait)
      {:ok, h} = Household.settle(h, :a)
      refute Map.has_key?(h.items, :rent)
      assert Ledger.deletions(h, :a) == [%{seq: 1, item_id: :rent}]
    end

    test "on a joint item the window starts only when the last owner agrees" do
      {:ok, h, _} = Household.propose_owners(h0(), :a, :rent, [:a, :b])
      h = later(h, @wait)
      {:ok, h} = Household.settle(h, :a)
      [p] = Household.pending(h, :b)
      {:ok, h} = Household.consent(h, :b, p.id)

      {:ok, h, g} = Household.propose_grant(h, :a, :rent, :c)
      refute Map.has_key?(h.proposals[g], :due)
      h = later(h, @day)
      {:ok, h} = Household.consent(h, :b, g)
      assert h.proposals[g].due == h.now + @wait
    end
  end

  describe "REQ-202: cancelling" do
    test "an owner whose agreement completed it takes it back alone, and the window resets" do
      {:ok, h, _} = Household.propose_owners(h0(), :a, :rent, [:a, :b])
      h = later(h, @wait)
      {:ok, h} = Household.settle(h, :a)
      {:ok, h} = Household.consent(h, :b, Household.pending(h, :b) |> hd() |> Map.get(:id))

      {:ok, h, g} = Household.propose_grant(h, :a, :rent, :c)
      {:ok, h} = Household.consent(h, :b, g)
      assert is_integer(h.proposals[g].due)

      {:ok, h} = Household.retract(h, :b, g)
      refute Map.has_key?(h.proposals[g], :due)
      h = later(h, @wait)
      assert Household.due(h, :a) == []
      refute View.visible?(h, :c, :rent)
    end

    test "the proposer taking back their agreement withdraws it; nobody else can take back someone's" do
      {:ok, h, pid} = Household.propose_grant(h0(), :a, :rent, :b)
      assert {:error, :not_found} = Household.retract(h, :b, pid)
      {:ok, h} = Household.retract(h, :a, pid)
      assert h.proposals == %{}
    end

    test "a joiner takes back their agreement while it hasn't applied" do
      {:ok, h0, _} = Household.propose_owners(h0(), :a, :rent, [:a, :b, :c])
      h = later(h0, @wait)
      {:ok, h} = Household.settle(h, :a)
      [p] = Household.pending(h, :b)
      {:ok, h} = Household.consent(h, :b, p.id)
      assert :b in h.proposals[p.id].consents
      {:ok, h} = Household.retract(h, :b, p.id)
      refute :b in h.proposals[p.id].consents
    end
  end

  describe "REQ-201: what never waits" do
    test "revoking, stopping owning, and withdrawing are immediate" do
      {:ok, h, g} = Household.propose_grant(h0(), :a, :rent, :b)
      h = later(h, @wait)
      {:ok, h} = Household.settle(h, :a)
      assert View.visible?(h, :b, :rent)
      {:ok, h} = Household.revoke_grant(h, :a, :rent, :b)
      refute View.visible?(h, :b, :rent)
      assert g not in Map.keys(h.proposals)
    end

    test "leaving is never delayed: a deletion the leaver scheduled takes effect as they leave" do
      {:ok, h, _} = Exit.delete(h0(), :a, :rent)
      assert {:ok, h} = Exit.leave(h, :a)
      refute :a in h.members
      refute Map.has_key?(h.items, :rent)
    end

    test "with the cooling-off off (0), every change applies at once, as before" do
      h = %{h0() | cooling: 0}
      {:ok, h, _} = Household.propose_grant(h, :a, :rent, :b)
      assert View.visible?(h, :b, :rent)
    end

    test "WI-089: a request agreed under the earlier rules stays shown and applies on agreement, after an upgrade" do
      # made with the cooling-off off (v0.8.3), then opened with it on
      {:ok, old, pid} = Household.propose_owners(%{h0() | cooling: 0}, :a, :rent, [:a, :b])
      h = Household.carry_over(%{old | cooling: @wait})

      assert [%{id: ^pid}] = Household.pending(h, :b)
      {:ok, h} = Household.consent(h, :b, pid)
      assert h.items[:rent].owners == MapSet.new([:a, :b])
    end

    test "WI-089: carry-over leaves alone a request some owner hasn't agreed to, and does nothing with the wait off" do
      {:ok, h, _} = Household.propose_owners(h0(), :a, :rent, [:a, :b])
      h = later(h, @wait)
      {:ok, h} = Household.settle(h, :a)
      {:ok, h} = Household.consent(h, :b, h.proposals |> Map.keys() |> hd())

      # a joint item with a grant only :a has agreed to, from before the cooling-off
      unagreed = %{
        h
        | proposals: %{
            9 => %{
              item_id: :rent,
              change: {:grant, :c},
              proposed_by: :a,
              consents: MapSet.new([:a])
            }
          }
      }

      assert Household.carry_over(unagreed).proposals[9] == unagreed.proposals[9]
      off = %{unagreed | cooling: 0}
      assert Household.carry_over(off) == off
    end

    test "with the cooling-off on and no clock, the rules refuse to guess" do
      h = %{h0() | now: nil}
      assert_raise ArgumentError, fn -> Household.propose_grant(h, :a, :rent, :b) end
    end
  end
end
