defmodule FindependenceShared.Contract.Cases.Items do
  @moduledoc "Contract cases: items and grants (WI-074 harness check; the criteria cases follow)."

  defmacro __using__(_) do
    quote do
      describe "contract: items" do
        test "an item is readable only by its readers; a grant makes it readable" do
          h = household(@form, ~w(ana ben))
          id = add_item(@form, h, "ana", "Rent", amount: -145_000)

          assert reads?(@form, h, "ana", id)
          refute reads?(@form, h, "ben", id)

          {:ok, _} = FindependenceShared.Items.propose_grant(scope(@form, h, "ana"), id, id(@form, h, "ben"))
          assert reads?(@form, h, "ben", id)
        end
      end
    end
  end
end
