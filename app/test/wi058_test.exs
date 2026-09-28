defmodule FindependenceApp.WI058Test do
  @moduledoc "WI-058: defects found while closing VV-001's test gaps (DEF-047 REQ-143, DEF-048 REQ-162)."
  use ExUnit.Case, async: true

  alias Findependence.{Exit, Household, Plans}
  alias FindependenceApp.Web.Html

  @today ~D[2026-09-27]

  # Ana makes a plan and asks Ben to share it; with `agreed`, Ben agrees.
  defp shared_plan(agreed) do
    h = Household.new(["ana", "ben"])
    {:ok, h} = Plans.new_plan(h, "ana", "trip", "Trip")
    {:ok, h, pid} = Plans.propose_shared(h, "ana", "trip", "shared_trip", ["ben"])
    if agreed, do: elem(Household.consent(h, "ben", pid), 1), else: h
  end

  describe "DEF-047: a shared plan says it is a plan wherever it is named" do
    test "the proposal line on the owner's home" do
      assert Html.home(shared_plan(false), "ana", "") =~
               "Make “Trip (a plan)” owned by ana and ben."
    end

    test "the export page, the leave page, and the confirmation to stop owning" do
      h = shared_plan(true)
      names = Html.names(h, "ben")
      assert names["shared_trip"] == "Trip (a plan)"
      assert Html.export_page(Exit.export(h, "ben"), names) =~ "<b>Trip (a plan)</b>"
      assert Html.leave_page(h, "ben", "") =~ "<b>Trip (a plan)</b>"

      assert Html.confirm_page(
               "relinquish",
               %{"item" => "shared_trip"},
               names["shared_trip"],
               "",
               ["ana"]
             ) =~
               "Stop owning “Trip (a plan)”?"
    end

    test "other items are named as before" do
      {:ok, h} =
        Household.add_item(Household.new(["ana"]), "ana", "rent", %{note: "Rent", amount: -1})

      assert Html.names(h, "ana")["rent"] == "Rent"
    end
  end

  test "DEF-048: the twelve months say they count shared items attached to the member's accounts" do
    page = Html.ahead_page(Household.new(["ana"]), "ana", @today)
    refute page =~ "It counts only items you own"

    assert page =~ "items shared with you that you&#39;ve said go through your accounts" or
             page =~ "items shared with you that you've said go through your accounts"
  end
end
