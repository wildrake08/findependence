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
    rest |> String.split("<div class=share-item") |> hd()
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

defmodule FindependenceApp.AgreementClarityTest do
  @moduledoc "WI-019: the interface says when a change needs agreement, and labels actions by their effect."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Household}

  defp block(body, title) do
    [_, rest] = String.split(body, "<h3>#{title}</h3>", parts: 2)
    rest |> String.split("<div class=share-item") |> hd()
  end

  defp h0 do
    h = Household.new(["ana", "ben"])
    {:ok, h} = Household.add_item(h, "ana", "solo", %{note: "Solo"})
    {:ok, h} = Household.add_item(h, "ana", "joint", %{note: "Joint"})
    {:ok, h, _} = Household.propose_owners(h, "ana", "joint", ["ana", "ben"])
    {:ok, h} = Alignment.add_value(h, "ana", "val", "Holiday")
    h
  end

  test "empty waiting list explains when agreement is needed" do
    body = Html.home(Household.new(["ana"]), "ana", "")
    assert body =~ "Nothing is waiting for you."
    assert body =~ "only need agreement when something has more than one owner"
  end

  test "a solely owned item applies changes right away, labelled Share and Change owners" do
    solo = h0() |> Html.home("ana", "") |> block("Solo")
    assert solo =~ "You're the only owner, so changes here take effect right away."
    assert solo =~ ">Share</button>"
    assert solo =~ ">Change owners</button>"
    assert solo =~ "<details open>"
  end

  test "a jointly owned item says changes wait, labelled Propose" do
    joint = h0() |> Html.home("ana", "") |> block("Joint")
    assert joint =~ "Owned jointly, so changes here wait until every owner agrees."
    assert joint =~ ">Propose change</button>"
    refute joint =~ ">Change owners</button>"
  end

  test "a solely owned value explains that adding an owner waits for them" do
    val = h0() |> Html.home("ana", "") |> block("Holiday")
    assert val =~ "Adding someone as an owner of a value waits for them to agree."
    assert val =~ ">Share</button>"
    assert val =~ ">Propose change</button>"
  end

  test "labels match behaviour: Change owners on a solo item applies at once; Propose change on a joint item waits" do
    {:ok, h, _} = Household.propose_owners(h0(), "ana", "solo", ["ana", "ben"])
    assert Household.pending(h, "ana") == []
    {:ok, h, _} = Household.propose_owners(h, "ana", "joint", ["ana"])
    assert [%{item_id: "joint"}] = Household.pending(h, "ana")
  end
end

defmodule FindependenceApp.OwnershipActionsTest do
  @moduledoc "UX-001 R3: only ownership actions that can succeed are offered."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Exit, Household}

  defp h0 do
    h = Household.new(["ana", "ben"])
    {:ok, h} = Household.add_item(h, "ana", "solo", %{note: "Solo", amount: -100, unit: :cents})
    {:ok, h} = Household.add_item(h, "ana", "joint", %{note: "Joint", amount: -200, unit: :cents})
    {:ok, h, _} = Household.propose_owners(h, "ana", "joint", ["ana", "ben"])
    {:ok, h} = Alignment.add_value(h, "ana", "vsolo", "Solo value")
    {:ok, h} = Alignment.add_value(h, "ana", "vjoint", "Joint value")
    {:ok, h, pid} = Household.propose_owners(h, "ana", "vjoint", ["ana", "ben"])
    {:ok, h} = Household.consent(h, "ben", pid)
    h
  end

  # {action, item} for every ownership-changing form the page offers ana
  defp offered(h) do
    body = Html.home(h, "ana", "")

    Regex.scan(~r/action="\/(?:confirm|act)\/(delete|relinquish)"><input type=hidden name=item value="([^"]+)"/, body)
    |> Enum.map(fn [_, action, id] -> {action, id} end)
  end

  test "sole-owned things offer Give away and Delete; jointly owned things offer only Stop owning" do
    offered = offered(h0())
    assert {"delete", "solo"} in offered and {"delete", "vsolo"} in offered
    assert {"relinquish", "joint"} in offered and {"relinquish", "vjoint"} in offered
    refute {"relinquish", "solo"} in offered
    refute {"delete", "joint"} in offered

    body = Html.home(h0(), "ana", "")
    assert body =~ ~s(href="#own-solo")
    assert body =~ ~s(id="own-solo")
    refute body =~ ~s(action="/act/relinquish")
  end

  test "no offered ownership action can fail with sole_owner or not_sole_owner" do
    h = h0()

    for {action, id} <- offered(h) do
      result =
        case action do
          "delete" -> Exit.delete(h, "ana", id)
          "relinquish" -> Household.relinquish(h, "ana", id)
        end

      assert match?({:ok, _}, result), "#{action} on #{id} was offered but gave #{inspect(result)}"
    end
  end

  test "the Stop owning confirmation names who keeps it and what regaining it takes" do
    page = Html.confirm_page("relinquish", %{"item" => "joint"}, "Joint", "", ["ben"])
    assert page =~ "Stop owning “Joint”?"
    assert page =~ "ben will keep it"
    assert page =~ "they would have to agree"
    assert page =~ ~s(action="/act/relinquish")
    assert page =~ ">Yes, stop owning<"
  end
end
