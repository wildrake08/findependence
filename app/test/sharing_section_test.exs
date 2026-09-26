defmodule FindependenceApp.SharingSectionTest do
  @moduledoc """
  WI-017 behaviour, now on the item page (UX-001 R1, WI-022): sharing and ownership reflect and act
  on the item's current state.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.Household

  defp h0 do
    h = Household.new(["ana", "ben", "cy"])
    {:ok, h} = Household.add_item(h, "ana", "rent", %{note: "Rent", amount: -1000, unit: :cents})
    {:ok, h, _} = Household.propose_owners(h, "ana", "rent", ["ana", "ben"])

    {:ok, h} =
      Household.add_item(h, "ana", "food", %{note: "Groceries", amount: -300, unit: :cents})

    {:ok, h, _} = Household.propose_grant(h, "ana", "food", "cy")
    {:ok, h} = Household.add_item(h, "ben", "phone", %{note: "Phone", amount: -50, unit: :cents})
    {:ok, h, _} = Household.propose_grant(h, "ben", "phone", "ana")
    h
  end

  test "owner checkboxes start ticked with the CURRENT owners (co-owners are not silently removed)" do
    rent = Html.item_page(h0(), "ana", "rent", "")
    assert rent =~ ~s(value="ana" checked)
    assert rent =~ ~s(value="ben" checked)
    refute rent =~ ~s(value="cy" checked)
  end

  test "shows who else can see it, with stop sharing only for them, and share-with only for the rest" do
    food = Html.item_page(h0(), "ana", "food", "")
    assert food =~ "cy can see it"
    assert food =~ ~s(aria-label="Stop sharing Groceries with cy")
    refute food =~ "Stop sharing Groceries with ben"

    [options] =
      Regex.run(~r/<select[^>]*name=member[^>]*>(.*?)<\/select>/s, food, capture: :all_but_first)

    assert options =~ "<option>ben</option>"
    refute options =~ "<option>cy</option>"

    rent = Html.item_page(h0(), "ana", "rent", "")
    assert rent =~ "Nobody else can see it."
    assert rent =~ "Share with"
  end

  test "a pending change is shown on its item with who it needs" do
    {:ok, h, _} = Household.propose_owners(h0(), "ana", "rent", ["ana"])
    rent = Html.item_page(h, "ana", "rent", "")
    assert rent =~ "Make “Rent” owned by ana."
    assert rent =~ "Waiting for ben."
  end

  test "an item shared with you says who shared it, and offers no ownership controls" do
    phone = Html.item_page(h0(), "ana", "phone", "")
    assert phone =~ "ben shared this with you."
    refute phone =~ ~s(action="/act/owners")
    refute phone =~ ~s(action="/act/grant")
    refute phone =~ "Give away or delete"
    refute phone =~ "<h2>Stop owning</h2>"
  end

  test "nothing to share with when everyone already can see it" do
    {:ok, h, _} = Household.propose_grant(h0(), "ana", "food", "ben")
    refute Html.item_page(h, "ana", "food", "") =~ "Share with"
  end

  test "someone who can't see an item gets no page" do
    assert Html.item_page(h0(), "cy", "rent", "") == nil
  end
end

defmodule FindependenceApp.ItemPagesTest do
  @moduledoc "UX-001 R1 and R7 (WI-022): a compact home page, and one page per thing."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Household}

  defp h0 do
    h = Household.new(["ana", "ben"])

    {:ok, h} =
      Household.add_item(h, "ana", "rent", %{note: "Rent", amount: -145_000, unit: :cents})

    {:ok, h} =
      Household.add_item(h, "ana", "food", %{note: "Groceries", amount: -6240, unit: :cents})

    {:ok, h} = Alignment.add_value(h, "ana", "home", "A safe home")
    {:ok, h} = Alignment.link(h, "ana", "rent", "home")
    h
  end

  test "the home page links to each thing and carries no per-item action forms" do
    body = Html.home(h0(), "ana", "")
    for id <- ["rent", "food", "home"], do: assert(body =~ ~s(href="/items/#{id}"))

    for action <- ~w(grant revoke owners relinquish delete link unlink consent withdraw),
        do: refute(body =~ ~s(action="/act/#{action}"), "home has a #{action} form")

    refute body =~ ~s(action="/confirm/delete")
  end

  test "an item page holds its links, history, and give-away or delete actions" do
    rent = Html.item_page(h0(), "ana", "rent", "")
    assert rent =~ "−$1,450.00"
    assert rent =~ "A safe home"
    assert rent =~ ~s(action="/act/unlink")
    assert rent =~ "History"
    assert rent =~ "<h2>Give away or delete</h2>"
    assert rent =~ ~s(action="/confirm/delete")
    # every form returns to this page (R6)
    assert rent =~ ~s(<input type=hidden name=return value="/items/rent">)
  end

  test "a value's page lists what is linked to it" do
    home = Html.item_page(h0(), "ana", "home", "")
    assert home =~ "Linked to this value"
    assert home =~ ~s(href="/items/rent")
  end

  test "R7: something waiting for you comes first, and is counted; nothing waiting shows no section" do
    {:ok, h} = Alignment.add_value(h0(), "ben", "hol", "Holiday")
    {:ok, h, _} = Household.propose_owners(h, "ben", "hol", ["ben", "ana"])
    body = Html.home(h, "ana", "")
    [before_items, _] = String.split(body, "Your items", parts: 2)
    assert before_items =~ "Waiting for you"
    assert before_items =~ "Request: own “Holiday” together with ben."
    assert Html.waiting_count(h, "ana") == 1
    assert Html.waiting_count(h, "ben") == 0
    refute Html.home(h0(), "ana", "") =~ "Waiting for you"
  end

  test "the agreement rules are explained on the item page" do
    assert Html.item_page(h0(), "ana", "rent", "") =~
             "You're the only owner, so changes here take effect right away."
  end
end

defmodule FindependenceApp.OutcomeTest do
  @moduledoc "UX-001 R6 (WI-022): feedback states what actually happened."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.Household

  defp h0 do
    h = Household.new(["ana", "ben", "cy"])
    {:ok, h} = Household.add_item(h, "ana", "rent", %{note: "Rent", unit: :cents})
    {:ok, h} = Household.add_item(h, "ana", "car", %{note: "Car", unit: :cents})
    {:ok, h, _} = Household.propose_owners(h, "ana", "car", ["ana", "ben"])
    h
  end

  test "a grant that applied names who can now see it; one that waits names who it waits for" do
    before = h0()
    {:ok, applied, _} = Household.propose_grant(before, "ana", "rent", "ben")

    assert Html.outcome("grant", %{"item" => "rent", "member" => "ben"}, before, applied, "ana") ==
             "ben can now see “Rent”."

    {:ok, waiting, _} = Household.propose_grant(before, "ana", "car", "cy")

    assert Html.outcome("grant", %{"item" => "car", "member" => "cy"}, before, waiting, "ana") ==
             "Requested. Waiting for ben to agree."
  end

  test "owner changes: applied or proposed" do
    before = h0()
    {:ok, h, _} = Household.propose_owners(before, "ana", "rent", ["ana", "ben"])

    assert Html.outcome(
             "owners",
             %{"item" => "rent", "owners" => ["ana", "ben"]},
             before,
             h,
             "ana"
           ) == "“Rent” is now owned by you and ben."

    {:ok, h, _} = Household.propose_owners(before, "ana", "car", ["ana"])

    assert Html.outcome("owners", %{"item" => "car", "owners" => ["ana"]}, before, h, "ana") =~
             "Waiting for ben"
  end

  test "consent: completed, or still waiting" do
    {:ok, h, pid} = Household.propose_owners(h0(), "ana", "car", ["ana"])
    {:ok, done} = Household.consent(h, "ben", pid)

    assert Html.outcome("consent", %{"proposal" => "#{pid}"}, h, done, "ben") ==
             "You agreed, and the change has been made."

    assert Html.outcome("consent", %{"proposal" => "not a number"}, h, done, "ben") == "Done."
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
    assert ana =~ "Withdraw this request"
    assert Html.item_page(h, "ana", "v", "") =~ ~s(action="/act/withdraw")

    ben = Html.home(h, "ben", "")
    assert ben =~ "Request: own “Holiday” together with ana."
    refute ben =~ ~s(action="/act/withdraw")
  end
end

defmodule FindependenceApp.AgreementClarityTest do
  @moduledoc "WI-019, on the item page: says when a change needs agreement; labels actions by effect."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Household}

  defp h0 do
    h = Household.new(["ana", "ben"])
    {:ok, h} = Household.add_item(h, "ana", "solo", %{note: "Solo"})
    {:ok, h} = Household.add_item(h, "ana", "joint", %{note: "Joint"})
    {:ok, h, _} = Household.propose_owners(h, "ana", "joint", ["ana", "ben"])
    {:ok, h} = Alignment.add_value(h, "ana", "val", "Holiday")
    h
  end

  test "a solely owned item applies changes right away, labelled Share and Change owners" do
    solo = Html.item_page(h0(), "ana", "solo", "")
    assert solo =~ "You're the only owner, so changes here take effect right away."
    assert solo =~ ">Share</button>"
    assert solo =~ ">Change owners</button>"
  end

  test "a jointly owned item says changes wait, labelled Request" do
    joint = Html.item_page(h0(), "ana", "joint", "")
    assert joint =~ "Owned jointly, so changes here wait until every owner agrees."
    assert joint =~ ">Request change</button>"
    refute joint =~ ">Change owners</button>"
  end

  test "a solely owned value explains that adding an owner waits for them" do
    val = Html.item_page(h0(), "ana", "val", "")
    assert val =~ "Adding someone as an owner of a value waits for them to agree."
    assert val =~ ">Share</button>"
    assert val =~ ">Request change</button>"
  end

  test "labels match behaviour: Change owners on a solo item applies at once; Propose change on a joint item waits" do
    {:ok, h, _} = Household.propose_owners(h0(), "ana", "solo", ["ana", "ben"])
    assert Household.pending(h, "ana") == []
    {:ok, h, _} = Household.propose_owners(h, "ana", "joint", ["ana"])
    assert [%{item_id: "joint"}] = Household.pending(h, "ana")
  end
end

defmodule FindependenceApp.OwnershipActionsTest do
  @moduledoc "UX-001 R3, on the item page: only ownership actions that can succeed are offered."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Exit, Household}

  @ids ["solo", "joint", "vsolo", "vjoint"]

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

  # {action, item} for every ownership-changing form ana is offered, across all item pages
  defp offered(h) do
    for id <- @ids,
        [_, action, item] <-
          Regex.scan(
            ~r/action="\/(?:confirm|act)\/(delete|relinquish)">(?:<input[^>]*>)*?<input type=hidden name=item value="([^"]+)"/,
            Html.item_page(h, "ana", id, "")
          ),
        do: {action, item}
  end

  test "sole-owned things offer Give away and Delete; jointly owned things offer only Stop owning" do
    offered = offered(h0())
    assert {"delete", "solo"} in offered and {"delete", "vsolo"} in offered
    assert {"relinquish", "joint"} in offered and {"relinquish", "vjoint"} in offered
    refute {"relinquish", "solo"} in offered
    refute {"delete", "joint"} in offered

    solo = Html.item_page(h0(), "ana", "solo", "")
    assert solo =~ ~s(href="#owners")
    assert solo =~ ~s(id=owners)
    refute solo =~ ~s(action="/act/relinquish")
  end

  test "no offered ownership action can fail with sole_owner or not_sole_owner" do
    h = h0()

    for {action, id} <- offered(h) do
      result =
        case action do
          "delete" -> Exit.delete(h, "ana", id)
          "relinquish" -> Household.relinquish(h, "ana", id)
        end

      assert match?({:ok, _}, result),
             "#{action} on #{id} was offered but gave #{inspect(result)}"
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

defmodule FindependenceApp.StableOrderTest do
  @moduledoc "WI-030: lists of items and values appear in name order, not in the order of their random ids."
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Exit, Household}

  # ids chosen so that id order and name order disagree
  defp h do
    h = Household.new(["ana"])
    {:ok, h} = Household.add_item(h, "ana", "z1", %{note: "Apples"})
    {:ok, h} = Household.add_item(h, "ana", "a1", %{note: "Zucchini"})

    for {id, label} <- [{"zz", "Arts"}, {"mm", "Music"}, {"aa", "Zen"}], reduce: h do
      h ->
        {:ok, h} = Alignment.add_value(h, "ana", id, label)
        h
    end
  end

  defp in_order?(body, names) do
    positions = Enum.map(names, fn n -> :binary.match(body, n) |> elem(0) end)
    positions == Enum.sort(positions)
  end

  test "the Link to choices are in name order" do
    body = Html.item_page(h(), "ana", "z1", "")
    [select] = Regex.run(~r/<select id=link-value.*?<\/select>/s, body)
    assert in_order?(select, [">Arts<", ">Music<", ">Zen<"])
  end

  test "linked lists and the export's links are in name order" do
    h = h()
    {:ok, h} = Alignment.link(h, "ana", "a1", "zz")
    {:ok, h} = Alignment.link(h, "ana", "z1", "zz")
    {:ok, h} = Alignment.link(h, "ana", "z1", "aa")
    {:ok, h} = Alignment.link(h, "ana", "z1", "mm")

    assert in_order?(Html.item_page(h, "ana", "zz", ""), ["Apples", "Zucchini"])
    assert in_order?(Html.item_page(h, "ana", "z1", "") |> String.split("What it's for") |> List.last(), ["Arts", "Music", "Zen"])

    export = Html.export_page(Exit.export(h, "ana"), Html.names(h, "ana"))
    [links] = Regex.run(~r/<h3>Your links<\/h3><ul>.*?<\/ul>/s, export)
    assert in_order?(links, ["Apples → Arts", "Apples → Music", "Apples → Zen", "Zucchini → Arts"])
  end
end

