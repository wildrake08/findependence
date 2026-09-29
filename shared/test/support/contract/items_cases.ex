defmodule FindependenceShared.Contract.Cases.Items do
  @moduledoc "Contract cases: the harness check (a grant makes an item readable) and REQ-119 AC-2 (WI-074)."

  defmacro __using__(_) do
    quote do
      describe "contract: items" do
        test "an item is readable only by its readers; a grant makes it readable" do
          h = household(@form, ~w(ana ben))
          id = add_item(@form, h, "ana", "Rent", amount: -145_000)

          assert reads?(@form, h, "ana", id)
          refute reads?(@form, h, "ben", id)

          {:ok, _} =
            FindependenceShared.Items.propose_grant(
              scope(@form, h, "ana"),
              id,
              id(@form, h, "ben")
            )

          assert reads?(@form, h, "ben", id)
        end

        test "REQ-119 AC-2: each item has its own key, and one item's key can't open another's content" do
          h = household(@form, ~w(ana))
          a = add_item(@form, h, "ana", "Rent")
          b = add_item(@form, h, "ana", "Pay", amount: 500_000)
          session = scope(@form, h, "ana").session
          state = stored(@form, h)
          ka = session.item_keys[a]
          kb = session.item_keys[b]

          assert is_binary(ka) and is_binary(kb) and ka != kb
          aad = fn id -> FindependenceShared.Envelope.aad(state.hid, {:content, id}) end

          assert {:ok, _} =
                   FindependenceShared.Crypto.decrypt(ka, state.items[a].content, aad.(a))

          assert :error = FindependenceShared.Crypto.decrypt(ka, state.items[b].content, aad.(b))
          assert :error = FindependenceShared.Crypto.decrypt(kb, state.items[a].content, aad.(a))
        end
      end
    end
  end
end
