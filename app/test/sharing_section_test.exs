defmodule FindependenceApp.SharingSectionTest do
  @moduledoc "WI-017: the sharing section reflects and acts on each item's current state."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.Household

  @csrf ""

  defp h0 do
    h = Household.new(["ana", "ben", "cy"])
    {:ok, h} = Household.add_item(h, "ana", "rent", %{note: "Rent", amount: -1000})
    {:ok, h, _} = Household.propose_owners(h, "ana", "rent", ["ana", "ben"])
    {:ok, h} = Household.add_item(h, "ana", "food", %{note: "Groceries", amount: -300})
    {:ok, h, _} = Household.propose_grant(h, "ana", "food", "cy")
    {:ok, h} = Household.add_item(h, "ben", "phone", %{note: "Phone", amount: -50})
    {:ok, h, _} = Household.propose_grant(h, "ben", "phone", "ana")
    h
  end

  # the HTML block for one item in the sharing section
  defp block(body, title) do
    [_, rest] = String.split(body, "<h3>#{title}</h3>", parts: 2)
    rest |> String.split("<div class=share-item>") |> hd()
  end

  defp sharing_section(body),
    do:
      body
      |> String.split("Sharing and ownership</h2>")
      |> List.last()
      |> String.split("<h2>")
      |> hd()

  test "owner checkboxes start ticked with the CURRENT owners (co-owners are not silently removed)" do
    rent = h0() |> Html.home("ana", @csrf) |> sharing_section() |> block("Rent")
    assert rent =~ ~s(value="ana" checked)
    assert rent =~ ~s(value="ben" checked)
    refute rent =~ ~s(value="cy" checked)
  end

  test "shows who else can see each item, with stop sharing only for them" do
    food = h0() |> Html.home("ana", @csrf) |> sharing_section() |> block("Groceries")
    assert food =~ "Also visible to "
    assert food =~ "<span class=person>cy <form"
    assert food =~ ~s(aria-label="Stop sharing Groceries with cy")
    refute food =~ "Stop sharing Groceries with ben"
    # share-with offers only members who cannot already see it
    [options] =
      Regex.run(~r/<select[^>]*name=member[^>]*>(.*?)<\/select>/s, food, capture: :all_but_first)

    assert options =~ "<option>ben</option>"
    refute options =~ "<option>cy</option>"

    rent = h0() |> Html.home("ana", @csrf) |> sharing_section() |> block("Rent")
    assert rent =~ "Nobody else can see it."
    assert rent =~ "Share with"
  end

  test "a pending change is shown on its item with who it needs" do
    {:ok, h, _} = Household.propose_owners(h0(), "ana", "rent", ["ana"])
    rent = h |> Html.home("ana", @csrf) |> sharing_section() |> block("Rent")
    assert rent =~ "Waiting: Make “Rent” owned by ana."
    assert rent =~ "Needs ben to agree."
  end

  test "things shared with you are listed, with who shared them" do
    section = h0() |> Html.home("ana", @csrf) |> sharing_section()
    assert section =~ "Shared with you"
    assert section =~ "<b>Phone</b>. ben let you see this."
  end

  test "nothing to share with when everyone already can see it" do
    {:ok, h, _} = Household.propose_grant(h0(), "ana", "food", "ben")
    food = h |> Html.home("ana", @csrf) |> sharing_section() |> block("Groceries")
    refute food =~ "Share with"
  end
end

defmodule FindependenceApp.WithdrawUiTest do
  @moduledoc "REQ-125 in the interface: owners see Withdraw; prospective joiners don't."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Household}

  test "an owner sees Withdraw on pending changes; a prospective joiner sees only Agree" do
    {:ok, h} = Alignment.add_value(Household.new(["ana", "ben"]), "ana", "v", "Holiday")
    {:ok, h, _} = Household.propose_owners(h, "ana", "v", ["ana", "ben"])

    ana = Html.home(h, "ana", "")
    assert ana =~ ~s(action="/act/withdraw")
    assert ana =~ "Withdraw this proposal"

    ben = Html.home(h, "ben", "")
    assert ben =~ "You&#39;re invited to share “Holiday”"
    refute ben =~ ~s(action="/act/withdraw")
    assert Html.done_text("withdraw") =~ "Withdrawn"
  end
end
