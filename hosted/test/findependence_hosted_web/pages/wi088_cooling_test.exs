defmodule FindependenceHostedWeb.Pages.WI088CoolingTest do
  @moduledoc """
  REQ-201, REQ-202 (CP-030 option A, WI-088) through the hosted form's pages: the outcome and the waiting change
  say when it takes effect, a page an owner opens after the window applies it, and someone asked to own an item who
  agreed can take it back.
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceShared.Items

  @wait 72 * 3600

  setup do
    Application.put_env(:findependence_shared, :cooling_seconds, @wait)
    Application.put_env(:findependence_shared, :now, 1_900_000_000)

    on_exit(fn ->
      Application.put_env(:findependence_shared, :cooling_seconds, 0)
      Application.delete_env(:findependence_shared, :now)
    end)
  end

  defp pass(s),
    do:
      Application.put_env(
        :findependence_shared,
        :now,
        Application.fetch_env!(:findependence_shared, :now) + s
      )

  defp item(h, name, note) do
    {:ok, saved} =
      Items.add_item(scope(h, name), %{
        note: note,
        amount: {:ok, -1000},
        frequency: :monthly,
        on: ""
      })

    Enum.find_value(saved.household.items, fn {id, i} -> i.attrs[:note] == note && id end)
  end

  test "a share waits 72 hours, says so, and the owner's next page after that applies it" do
    h = household(~w(ana ben))
    id = item(h, "ana", "Flat rent")

    conn = act(h, "ana", "/act/grant", %{"item" => id, "member" => id(h, "ben")})
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "will be shared with Ben on"

    assert page(h, "ana", "/items/#{id}").resp_body =~
             "Everyone needed has agreed. Takes effect on"

    refute page(h, "ben", "/").resp_body =~ "Flat rent"

    pass(@wait)
    refute page(h, "ben", "/").resp_body =~ "Flat rent"
    _ = page(h, "ana", "/")
    assert page(h, "ben", "/").resp_body =~ "Flat rent"
  end

  test "someone asked to own an item who agreed can take it back" do
    h = household(~w(ana ben cy))
    id = item(h, "ana", "Flat rent")

    {:ok, _} =
      Items.propose_owners(
        scope(h, "ana"),
        id,
        Enum.sort([id(h, "ana"), id(h, "ben"), id(h, "cy")])
      )

    pass(@wait)
    _ = page(h, "ana", "/")

    [p] = Items.pending(scope(h, "ben"))
    {:ok, _} = Items.consent(scope(h, "ben"), p.id)
    assert page(h, "ben", "/").resp_body =~ "Take back my agreement"

    conn = act(h, "ben", "/act/retract", %{"proposal" => p.id})
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "You took back your agreement."
    refute id(h, "ben") in Items.proposal(scope(h, "ana"), p.id).consents
  end
end
