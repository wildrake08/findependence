defmodule FindependenceApp.GlossaryTest do
  @moduledoc """
  UX-001 R9 (WI-023): one word per concept. Renders every page and message for representative
  states and fails if what a person reads or hears uses a synonym the glossary rules out.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.{Glossary, Html}
  alias Findependence.{Alignment, Exit, Household}

  # What a person reads or hears: text, plus aria-label and placeholder values.
  defp user_text(html) do
    html = Regex.replace(~r/<style.*?<\/style>/s, html, " ")

    attrs =
      Regex.scan(~r/(?:aria-label|placeholder)="([^"]*)"/, html)
      |> Enum.map_join(" ", &List.last/1)

    (Regex.replace(~r/<[^>]+>/, html, " ") <> " " <> attrs)
    |> String.replace(["&#39;", "&quot;", "&amp;", "&lt;", "&gt;"], fn
      "&#39;" -> "'"
      "&quot;" -> "\""
      "&amp;" -> "&"
      "&lt;" -> "<"
      "&gt;" -> ">"
    end)
  end

  # A household exercising every state the pages show: sole, joint, shared-with-me, values with a
  # waiting request, links, and history with every kind of event.
  defp household do
    h = Household.new(["ana", "ben", "cy"])

    {:ok, h} =
      Household.add_item(h, "ana", "rent", %{note: "Rent", amount: -145_000, unit: :cents})

    {:ok, h} = Household.add_item(h, "ana", "car", %{note: "Car", amount: -31_000, unit: :cents})

    {:ok, h} =
      Household.add_item(h, "ben", "phone", %{note: "Phone", amount: -5_500, unit: :cents})

    {:ok, h, _} = Household.propose_owners(h, "ana", "car", ["ana", "ben"])
    {:ok, h, _} = Household.propose_grant(h, "ana", "rent", "cy")
    {:ok, h, _} = Household.propose_grant(h, "ana", "rent", "ben")
    {:ok, h} = Household.revoke_grant(h, "ana", "rent", "cy")
    {:ok, h, _} = Household.propose_grant(h, "ben", "phone", "ana")
    {:ok, h, _} = Household.propose_grant(h, "ana", "car", "cy")
    {:ok, h} = Alignment.add_value(h, "ana", "home", "A safe home")
    {:ok, h} = Alignment.add_value(h, "ana", "hol", "Holiday")
    {:ok, h, _} = Household.propose_owners(h, "ana", "hol", ["ana", "ben"])
    {:ok, h} = Alignment.link(h, "ana", "rent", "home")
    {:ok, h} = Household.add_item(h, "cy", "gym", %{note: "Gym", unit: :cents})
    {:ok, h, _} = Household.propose_owners(h, "cy", "gym", ["cy", "ana"])
    {:ok, h} = Household.relinquish(h, "cy", "gym")
    h
  end

  defp pages do
    h = household()
    members = ["ana", "ben", "cy"]

    member_pages =
      for m <- members do
        items = Map.keys(Html.names(h, m))

        [
          Html.home(h, m, "", {:ok, "x"}, %{error: "x"}),
          Html.leave_page(h, m, ""),
          Html.export_page(Exit.export(h, m), Html.names(h, m))
        ] ++ Enum.map(items, &Html.item_page(h, m, &1, ""))
      end

    List.flatten(member_pages) ++
      [
        Html.leave_page(Household.new(["ana", "ben"]), "ana", ""),
        # cy owns nothing after sharing and then no longer owning the gym: the leave button shows
        Html.leave_page(h, "cy", ""),
        Html.login(members, "", "x", :idle),
        Html.login(members, "", nil, :idle_action),
        Html.integrity_banner([:x]),
        Html.confirm_page("delete", %{"item" => "rent"}, "Rent", ""),
        Html.confirm_page("relinquish", %{"item" => "car"}, "Car", "", ["ben"])
      ] ++
      Enum.map(Html.error_reasons(), &Html.error_text/1) ++
      outcomes(h)
  end

  defp outcomes(h) do
    for {action, params} <- [
          {"add_item", %{"note" => "Rent"}},
          {"add_value", %{"label" => "Holiday"}},
          {"grant", %{"item" => "rent", "member" => "ben"}},
          {"grant", %{"item" => "car", "member" => "cy"}},
          {"revoke", %{"item" => "rent", "member" => "ben"}},
          {"owners", %{"item" => "car", "owners" => ["ben"]}},
          {"consent", %{"proposal" => "1"}},
          {"withdraw", %{"proposal" => "1"}},
          {"relinquish", %{"item" => "car"}},
          {"delete", %{"item" => "rent"}},
          {"let_go", %{"item" => "rent", "to" => "give:ben"}},
          {"let_go", %{"item" => "rent", "to" => "delete"}},
          {"link", %{"item" => "rent", "value" => "home"}},
          {"unlink", %{"item" => "rent", "value" => "home"}}
        ] do
      Html.outcome(action, params, h, h, "ana")
    end
  end

  test "every page and message uses the glossary's words" do
    found =
      for page <- pages(), {word, instead} <- Glossary.violations(user_text(page)) do
        "“#{word}” (use #{instead})"
      end

    assert Enum.uniq(found) == []
  end

  test "the check catches synonyms, including in labels read aloud" do
    assert [{"proposal", "request"}] =
             Glossary.violations(
               user_text(~s(<button aria-label="Withdraw this proposal">Withdraw</button>))
             )

    assert Glossary.violations(user_text("<p>Also visible to ben. Let ben see it.</p>")) != []

    assert Glossary.violations(user_text("<p>Ben can see it. Share it, or stop owning it.</p>")) ==
             []
  end

  test "the glossary names the eight terms UX-001 R9 proposes" do
    assert Enum.map(Glossary.terms(), &elem(&1, 0)) ==
             [
               "item",
               "value",
               "owner",
               "can see",
               "share / stop sharing",
               "give away",
               "stop owning",
               "request"
             ]
  end
end
