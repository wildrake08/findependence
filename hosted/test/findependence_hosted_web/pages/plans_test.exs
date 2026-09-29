defmodule FindependenceHostedWeb.Pages.PlansTest do
  @moduledoc """
  WI-076: the plans pages, a plan request's preview, and their forms say what the local form's say (REQ-106
  AC-2, REQ-143 AC-3, REQ-166 AC-3 and AC-6), each criterion as the local form's asserting test checks it
  (VV-002), and each form's success and a refusal.
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceShared.{Balances, Items, Planning, Values, Words}

  # ---------------------------------------------------------------------------
  # helpers

  defp new_id, do: "t" <> Integer.to_string(System.unique_integer([:positive]))

  defp add_item(h, who, note, cents) do
    {:ok, _} =
      Items.add_item(scope(h, who), %{
        note: note,
        amount: {:ok, cents},
        frequency: {:every, 1, :month},
        on: nil
      })

    scope(h, who) |> Items.visible() |> Enum.find(&(Words.title(&1) == note)) |> Map.fetch!(:id)
  end

  defp new_plan(h, who, name) do
    id = new_id()
    {:ok, _} = Planning.new_plan(scope(h, who), id, name)
    id
  end

  defp switch_off(h, who, plan, items, from) do
    {:ok, _} =
      Planning.add_step(scope(h, who), plan, %{kind: "switch_off", items: items, from: from})
  end

  defp plan(h, who, id), do: Planning.plan(scope(h, who), id)

  defp doc(conn), do: LazyHTML.from_document(conn.resp_body)

  defp text(%LazyHTML{} = d),
    do: d |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(conn), do: conn |> doc() |> LazyHTML.query("main") |> text()

  defp h1(conn), do: conn |> doc() |> LazyHTML.query("h1") |> text()

  defp forms_to(conn), do: conn |> doc() |> LazyHTML.query("form") |> LazyHTML.attribute("action")

  defp info(conn), do: Phoenix.Flash.get(conn.assigns.flash, :info)

  defp ok_page(h, who, path) do
    conn = page(h, who, path)
    assert conn.status == 200, path
    conn
  end

  # The per-request tokens are the only part of a page that may differ between two visits; the layout's
  # notices also get fresh element ids on each request (as the flow pages' test sets aside).
  defp normalize(html) do
    html
    |> String.replace(~r/((?:id|aria-labelledby|aria-describedby)=")(?:alert-\d+|c-[^"]*)/, "\\1")
    |> String.replace(~r/(name="_csrf_token"[^>]*value=")[^"]*/, "\\1")
    |> String.replace(~r/(name="_form"[^>]*value=")[^"]*/, "\\1")
    |> String.replace(~r/("csrf-token" content=")[^"]*/, "\\1")
  end

  # ---------------------------------------------------------------------------
  # REQ-143 AC-3

  test "REQ-143 AC-3: the plans list, a plan's page, its delete confirmation, a plan request, and a shared plan each say it is a plan" do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -50_000)
    trip = new_plan(h, "ana", "Trip")
    switch_off(h, "ana", trip, [rent], "2026-11")
    switch_off(h, "ana", trip, [rent], "2026-12")

    assert text(ok_page(h, "ana", "/plans")) =~ "Trip 2 steps, private to you"
    plan_page = ok_page(h, "ana", "/plans/#{trip}")
    assert h1(plan_page) == "Trip"
    assert text(plan_page) =~ "A plan, private to you."
    assert text(plan_page) =~ "This is a plan, not what's real."

    confirm = act(h, "ana", "/confirm/delete_plan", %{"plan" => trip})
    assert h1(confirm) == "Delete the plan “Trip”?"

    {:ok, _} = Planning.share_plan(scope(h, "ana"), trip, [id(h, "ben")])
    [request] = Items.pending(scope(h, "ben"))
    assert text(ok_page(h, "ben", "/")) =~ "Request: share the plan “Trip” with Ana."
    preview = ok_page(h, "ben", "/requests/#{request.id}")
    assert h1(preview) == "Trip"
    assert text(preview) =~ "Ana asked you to share this plan."
    assert text(preview) =~ "From November 2026: switch off an item you can't see."
    assert "/act/consent" in forms_to(preview)

    {:ok, _} = Items.consent(scope(h, "ben"), request.id)

    for {who, owners} <- [{"ana", "you and Ben"}, {"ben", "Ana and you"}] do
      assert text(ok_page(h, who, "/plans")) =~ "Trip shared plan, owned by #{owners}"
      assert text(ok_page(h, who, "/items/#{request.item_id}")) =~ "A shared plan, owned by"
      refute text(ok_page(h, who, "/plans")) =~ id(h, "ana")
    end
  end

  # ---------------------------------------------------------------------------
  # REQ-166

  test "REQ-166 AC-3: deleting a plan first shows its name and how many steps go with it, and asks to confirm; going back keeps it" do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -500)
    plan = new_plan(h, "ana", "If pay stops")
    for month <- ["2026-11", "2026-12"], do: switch_off(h, "ana", plan, [rent], month)

    plan_page = ok_page(h, "ana", "/plans/#{plan}")
    assert "/confirm/delete_plan" in forms_to(plan_page)
    refute "/act/delete_plan" in forms_to(plan_page)

    confirm = act(h, "ana", "/confirm/delete_plan", %{"plan" => plan})
    assert confirm.status == 200
    assert h1(confirm) == "Delete the plan “If pay stops”?"

    assert text(confirm) =~
             "Its 2 steps will be deleted with it. Your real items and totals don't change. This can't be undone."

    assert forms_to(confirm) -- ["/sign-out"] == ["/act/delete_plan"]

    assert confirm |> doc() |> LazyHTML.query("button[type=submit]") |> text() =~
             "Yes, delete the plan"

    [back] =
      confirm
      |> doc()
      |> LazyHTML.query("main a")
      |> Enum.filter(&(text(&1) =~ "No, go back"))
      |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))

    assert back == "/plans/#{plan}"
    assert page(h, "ana", back).status == 200
    assert length(plan(h, "ana", plan).steps) == 2

    # one step is counted as one
    one = new_plan(h, "ana", "Trip")
    switch_off(h, "ana", one, [rent], "2026-11")
    assert text(act(h, "ana", "/confirm/delete_plan", %{"plan" => one})) =~ "Its 1 step will be"

    # a plan that no longer exists
    gone = act(h, "ana", "/confirm/delete_plan", %{"plan" => "no-such-plan"})
    assert redirected_to(gone) == "/plans"
    assert info(gone) == "That plan no longer exists."
  end

  test "REQ-166 AC-6: removing a single plan step posts straight to the removal, and one press removes it" do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -500)
    plan = new_plan(h, "ana", "If pay stops")
    switch_off(h, "ana", plan, [rent], "2026-11")

    plan_page = ok_page(h, "ana", "/plans/#{plan}")
    assert "/act/remove_step" in forms_to(plan_page)

    refute Enum.any?(
             forms_to(plan_page),
             &(String.contains?(&1, "step") and String.starts_with?(&1, "/confirm"))
           )

    assert plan_page
           |> doc()
           |> LazyHTML.query(~s(button[aria-label="Remove step 1"]))
           |> Enum.count() ==
             1

    removed =
      act(h, "ana", "/act/remove_step", %{
        "plan" => plan,
        "n" => "1",
        "return" => "/plans/#{plan}"
      })

    assert redirected_to(removed) == "/plans/#{plan}"
    assert info(removed) == "Removed the step."
    assert plan(h, "ana", plan).steps == []

    # a step that isn't there is refused, on the plan's page
    again =
      act(h, "ana", "/act/remove_step", %{
        "plan" => plan,
        "n" => "1",
        "return" => "/plans/#{plan}"
      })

    assert again.status == 422
    assert h1(again) == "If pay stops"
    assert text(again) =~ "That isn't available to you."
  end

  # ---------------------------------------------------------------------------
  # REQ-106 AC-2

  test "REQ-106 AC-2: another member's private entries change neither the plans page nor a plan's page" do
    h = household(~w(ana ben cy))
    bus = add_item(h, "ben", "Bus", -2_000)
    bens = new_plan(h, "ben", "Ben's plan")
    switch_off(h, "ben", bens, [bus], "2026-11")
    pages = ["/plans", "/plans/#{bens}"]
    before = Map.new(pages, &{&1, normalize(ok_page(h, "ben", &1).resp_body)})
    assert before["/plans"] =~ "Ben&#39;s plan"

    # everything Ana adds is hers alone, or shared with Cy only
    rent = add_item(h, "ana", "Rent", -215_000)
    pay = add_item(h, "ana", "Pay", 480_000)
    {:ok, _} = Values.add_value(scope(h, "ana"), "Security")
    chk = new_id()
    {:ok, _} = Balances.add_account(scope(h, "ana"), chk, "Ana checking", :checking)

    {:ok, _} =
      Balances.add_reading(scope(h, "ana"), chk, %{
        balance: {:ok, 350_000, false},
        on: {:ok, "2026-09-20"},
        rate: {:ok, nil},
        min_payment: {:ok, nil}
      })

    {:ok, _} = Planning.mark(scope(h, "ana"), rent, pay)
    anas = new_plan(h, "ana", "Ana's plan")
    switch_off(h, "ana", anas, [pay], "2026-11")
    {:ok, _} = Planning.share_plan(scope(h, "ana"), anas, [id(h, "cy")])
    {:ok, _} = Items.propose_grant(scope(h, "ana"), pay, id(h, "cy"))

    assert Map.new(pages, &{&1, normalize(ok_page(h, "ben", &1).resp_body)}) == before
    assert page(h, "ben", "/plans/#{anas}").status == 404
  end

  # ---------------------------------------------------------------------------
  # The forms: each one's success and a refusal

  test "starting a plan goes to its page; a plan with no name is refused on the plans page" do
    h = household(~w(ana ben))
    started = act(h, "ana", "/act/new_plan", %{"name" => " Trip "})
    "/plans/" <> id = redirected_to(started)
    assert info(started) == "Started “Trip”. Add its steps below."
    assert plan(h, "ana", id).name == "Trip"

    refused = act(h, "ana", "/act/new_plan", %{"name" => "  "})
    assert refused.status == 422
    assert h1(refused) == "Plans"
    assert text(refused) =~ "Give the plan a name of up to 200 characters."
    assert map_size(Planning.plans(scope(h, "ana"))) == 1
  end

  test "adding each kind of step returns to the plan's page with the comparison; a mistake is named on it" do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -50_000)
    plan = new_plan(h, "ana", "Trip")

    for {params, words} <- [
          {%{"kind" => "switch_off", "items" => [rent], "from" => "2026-11"},
           "From November 2026: switch off Rent."},
          {%{
             "kind" => "add",
             "note" => "Premium",
             "amount" => "600",
             "frequency" => "monthly",
             "direction" => "out",
             "from" => "2026-12"
           }, "From December 2026: Premium, "},
          {%{
             "kind" => "borrow",
             "amount" => "5,000",
             "rate" => "9",
             "payment" => "200",
             "from" => "2027-01"
           }, "From January 2027: borrow $5,000.00 at 9%, paying $200.00 a month."}
        ] do
      added = act(h, "ana", "/act/plan_step", Map.put(params, "plan", plan))
      assert redirected_to(added) == "/plans/#{plan}"
      assert info(added) == "Added the step. The comparison below includes it."
      assert text(ok_page(h, "ana", "/plans/#{plan}")) =~ words
    end

    plan_page = ok_page(h, "ana", "/plans/#{plan}")
    assert length(plan(h, "ana", plan).steps) == 3
    assert text(plan_page) =~ "Interest on the planned borrowing over these months: $"
    assert text(plan_page) =~ "Showing net money in and out each month"

    # with cash to start from, the answer comes first, in a sentence
    chk = new_id()
    {:ok, _} = Balances.add_account(scope(h, "ana"), chk, "Checking", :checking)

    {:ok, _} =
      Balances.add_reading(scope(h, "ana"), chk, %{
        balance: {:ok, 100_000, false},
        on: {:ok, "2026-09-20"},
        rate: {:ok, nil},
        min_payment: {:ok, nil}
      })

    summary = ok_page(h, "ana", "/plans/#{plan}") |> doc() |> LazyHTML.query("#plan-summary")

    assert text(summary) =~
             ~r/^With this plan, cash first goes below zero in \w+ \d{4} and is lowest in \w+ \d{4}, at −\$[\d,.]+\. Without it, cash first goes below zero in/

    heads =
      plan_page |> doc() |> LazyHTML.query("#comparison th[scope=col]") |> Enum.map(&text/1)

    assert heads == ["Month", "Without this plan", "With this plan", "Difference"]
    assert plan_page |> doc() |> LazyHTML.query("#comparison th[scope=row]") |> Enum.count() == 12

    for id <-
          ~w(switch-from add-note add-amount add-frequency add-from borrow-amount borrow-rate borrow-payment borrow-from) do
      assert plan_page |> doc() |> LazyHTML.query(~s(label[for="#{id}"])) |> Enum.count() == 1, id
    end

    mistake =
      act(h, "ana", "/act/plan_step", %{
        "plan" => plan,
        "kind" => "switch_off",
        "from" => "2026-11"
      })

    assert mistake.status == 422
    assert h1(mistake) == "Trip"
    assert text(mistake) =~ "Tick at least one item to switch off."
    assert length(plan(h, "ana", plan).steps) == 3
  end

  test "asking others to share a plan names them by name; asking no one is refused on the plan's page" do
    h = household(~w(ana ben))
    plan = new_plan(h, "ana", "Trip")
    plan_page = ok_page(h, "ana", "/plans/#{plan}")
    assert text(plan_page) =~ "Ben"
    refute text(plan_page) =~ id(h, "ben")

    sent = act(h, "ana", "/act/share_plan", %{"plan" => plan, "members" => [id(h, "ben")]})
    assert redirected_to(sent) == "/plans/#{plan}"
    assert info(sent) == "Sent the request. It becomes a shared plan when Ben agrees."
    assert [_] = Items.pending(scope(h, "ben"))

    refused = act(h, "ana", "/act/share_plan", %{"plan" => plan})
    assert refused.status == 422
    assert h1(refused) == "Trip"
    assert text(refused) =~ "That person isn't in this household."
  end

  test "deleting a plan returns to the plans list; deleting one that isn't there is refused there" do
    h = household(~w(ana ben))
    plan = new_plan(h, "ana", "Trip")
    deleted = act(h, "ana", "/act/delete_plan", %{"plan" => plan, "return" => "/plans"})
    assert redirected_to(deleted) == "/plans"
    assert info(deleted) == "Deleted the plan “Trip”."
    assert plan(h, "ana", plan) == nil

    refused = act(h, "ana", "/act/delete_plan", %{"plan" => plan, "return" => "/plans"})
    assert refused.status == 422
    assert h1(refused) == "Plans"
    assert text(refused) =~ "That isn't available to you."
  end

  test "a plan or a request that isn't the member's reads as not available" do
    h = household(~w(ana ben))
    plan = new_plan(h, "ana", "Trip")
    missing = page(h, "ben", "/plans/#{plan}")
    assert missing.status == 404
    assert text(missing) =~ "That plan isn't available to you."

    missing = page(h, "ben", "/requests/99")
    assert missing.status == 404
    assert text(missing) =~ "That request isn't waiting for you."
  end
end
