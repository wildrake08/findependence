defmodule FindependenceShared.Contract.Cases.Cooling do
  @moduledoc """
  Contract cases for the cooling-off (REQ-201, REQ-202; CP-030 option A, REV-115, WI-088), run on both forms
  through the shared contexts and each form's real storage and encryption. Each case turns the cooling-off on and
  fixes the clock (`FindependenceShared.Clock`), and puts both back after; the contract modules run on their own
  (async: false), after the concurrent tests, so nothing else sees the setting.
  """

  defmacro __using__(_) do
    quote do
      alias FindependenceShared.{Households, Items}
      alias FindependenceShared.Contract.B4

      @wait 72 * 3600

      defp cooling_on do
        before = {
          Application.get_env(:findependence_shared, :cooling_seconds),
          Application.get_env(:findependence_shared, :now)
        }

        Application.put_env(:findependence_shared, :cooling_seconds, @wait)
        Application.put_env(:findependence_shared, :now, 1_900_000_000)

        on_exit(fn ->
          {c, n} = before
          Application.put_env(:findependence_shared, :cooling_seconds, c)

          if n,
            do: Application.put_env(:findependence_shared, :now, n),
            else: Application.delete_env(:findependence_shared, :now)
        end)
      end

      defp pass(seconds) do
        now = Application.fetch_env!(:findependence_shared, :now)
        Application.put_env(:findependence_shared, :now, now + seconds)
      end

      defp settle(h, name), do: Households.settle(scope(@form, h, name))

      describe "REQ-201 (cooling-off)" do
        test "REQ-201 AC-1: a sole owner's share waits 72 hours; no key is sealed to the grantee before" do
          cooling_on()
          h = household(@form, ~w(ana ben))
          ben = id(@form, h, "ben")
          item = add_item(@form, h, "ana", "Rent", amount: -150_000)
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), item, ben)

          refute reads?(@form, h, "ben", item)
          refute ben in B4.key_holders(B4.stored(@form, h, "ana"), item)

          pass(@wait - 1)
          settle(h, "ana")
          refute ben in B4.key_holders(B4.stored(@form, h, "ana"), item)

          pass(1)
          # only an owner's session can seal it: Ben's own pages don't
          settle(h, "ben")
          refute reads?(@form, h, "ben", item)
          settle(h, "ana")
          assert reads?(@form, h, "ben", item)
        end

        test "REQ-201 AC-2: someone asked to own an item is sealed nothing, and shown nothing, until it ends" do
          cooling_on()
          h = household(@form, ~w(ana ben))
          ben = id(@form, h, "ben")
          a = B4.account(@form, h, "ana", "Savings", :savings)
          {:ok, _} = B4.reading(@form, h, "ana", a, 100_000, "2026-09-01")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), a, B4.ids(@form, h, ~w(ana ben)))

          stored = B4.stored(@form, h, "ana")
          refute Enum.any?(B4.entry_readers(stored, a), &(ben in &1))
          refute ben in B4.key_holders(stored, a)
          assert Items.pending(scope(@form, h, "ben")) == []

          pass(@wait)
          settle(h, "ana")
          assert [%{id: p, attrs: %{label: "Savings"}}] = Items.pending(scope(@form, h, "ben"))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), p)

          assert B4.ids(@form, h, ~w(ana ben)) ==
                   FindependenceShared.Contract.B1.owners(@form, h, "ana", a)
        end

        test "REQ-201 AC-3: deleting waits, and the owner can withdraw it; after the window it goes" do
          cooling_on()
          h = household(@form, ~w(ana ben))
          keep = add_item(@form, h, "ana", "Keep")
          gone = add_item(@form, h, "ana", "Gone")

          {:ok, _} = Items.delete(scope(@form, h, "ana"), keep)
          [p] = Items.pending(scope(@form, h, "ana"))
          {:ok, _} = Items.withdraw(scope(@form, h, "ana"), p.id)
          {:ok, _} = Items.delete(scope(@form, h, "ana"), gone)

          pass(@wait)
          settle(h, "ana")
          assert reads?(@form, h, "ana", keep)
          refute Map.has_key?(B4.stored(@form, h, "ana").items, gone)
        end

        test "REQ-201 AC-4: protective changes don't wait, and a scheduled deletion takes effect as its owner leaves" do
          cooling_on()
          h = household(@form, ~w(ana ben))
          ben = id(@form, h, "ben")
          shared = add_item(@form, h, "ana", "Shared")
          {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), shared, ben)
          pass(@wait)
          settle(h, "ana")
          assert reads?(@form, h, "ben", shared)

          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), shared, ben)
          refute reads?(@form, h, "ben", shared)

          mine = add_item(@form, h, "ben", "Mine")
          {:ok, _} = Items.delete(scope(@form, h, "ben"), mine)
          assert {:ok, _} = Households.leave(scope(@form, h, "ben"))
          refute Map.has_key?(B4.stored(@form, h, "ana").items, mine)
        end
      end

      describe "REQ-202 (cancelling)" do
        test "REQ-202 AC-1: someone asked to own an item who agreed takes it back alone" do
          cooling_on()
          h = household(@form, ~w(ana ben cy))
          item = add_item(@form, h, "ana", "Car")

          {:ok, _} =
            Items.propose_owners(scope(@form, h, "ana"), item, B4.ids(@form, h, ~w(ana ben cy)))

          pass(@wait)
          settle(h, "ana")
          [p] = Items.pending(scope(@form, h, "ben"))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), p.id)
          {:ok, _} = Items.retract(scope(@form, h, "ben"), p.id)
          refute id(@form, h, "ben") in Items.proposal(scope(@form, h, "ana"), p.id).consents
        end
      end
    end
  end
end
