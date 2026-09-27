defmodule FindependenceApp.UX002Test do
  @moduledoc "UX-002's small fixes (R1a, R2, R5, R6, R8) against their acceptance criteria, with the demo family."
  use ExUnit.Case, async: false

  alias FindependenceApp.{Session, Vault}
  alias FindependenceApp.Web.{Glossary, Html}
  alias Mix.Tasks.Findependence.Demo

  @today ~D[2026-09-27]

  setup_all do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-ux002-#{System.unique_integer([:positive])}.vault")
    :ok = Demo.build(path, iterations: 1_000, unsafe_test: true, today: @today)
    on_exit(fn -> File.rm(path) end)

    views =
      Map.new(Demo.members(), fn {m, p} ->
        {:ok, s} = Session.open(Vault.read!(path), m, p)
        {m, s.household}
      end)

    %{views: views}
  end

  defp text(html), do: html |> String.replace(~r/<[^>]+>/, " ") |> String.replace("&#39;", "'")

  test "R1a: a joint account's view names whose items it leaves out; a member's own account doesn't",
       %{views: v} do
    dad = text(Html.coming_up_card(v["Dad"], "Dad", @today))

    # UX-004 P2: one sentence, naming the co-owner, and saying it's the member's part
    assert dad =~
             "Mom also owns Joint checking, so this is your part: items Mom owns count only once they're shared with you and you say they go through it."

    mom = text(Html.coming_up_card(v["Mom"], "Mom", @today))

    assert mom =~
             "Dad also owns Joint checking, so this is your part: items Dad owns count only once"

    ahead = text(Html.ahead_page(v["Dad"], "Dad", @today))

    assert ahead =~
             "Mom also owns Joint checking and Savings, so this is your part: items Mom owns count only once they're shared with you and you say they go through it."

    # an account only the member owns keeps the general note
    h = Findependence.Household.new(["ana"])
    {:ok, h} = Findependence.Balances.add_account(h, "ana", "c", "Checking", :checking)

    {:ok, h} =
      Findependence.Balances.add_reading(h, "ana", "c", %{on: "2026-09-26", balance: 1_000})

    {:ok, h} =
      Findependence.Household.add_item(h, "ana", "r", %{
        note: "Rent",
        amount: -500,
        unit: :cents,
        frequency: {:every, 1, :month},
        on: "2026-10-01"
      })

    own = text(Html.coming_up_card(h, "ana", @today))

    assert own =~
             "Counts items you own, and items shared with you that you've said go through these accounts; anything others keep private isn't included."

    refute own =~ "also owned by"
  end

  test "R2: a debt's rate and minimum payment start from its latest balance", %{views: v} do
    page = Html.item_page(v["Dad"], "Dad", "dad_visa", "")

    assert page =~
             ~s(<input id=rate name=rate inputmode=decimal autocomplete=off placeholder="e.g. 21.99" value="24.99")

    assert page =~
             ~s(<input id=min_payment name=min_payment inputmode=decimal autocomplete=off placeholder="e.g. 150" value="190.00")

    # the new balance itself is left for the member
    assert page =~
             ~s(<input id=balance name=balance inputmode=decimal autocomplete=off placeholder="e.g. 5,200" value="")

    # after a refused save, what was typed wins, even if it was emptied
    refused =
      Html.item_page(v["Dad"], "Dad", "dad_visa", "", {:error, "x"}, %{
        rate: "",
        min_payment: "5",
        error: "x",
        error_field: :rate
      })

    assert refused =~ ~s(placeholder="e.g. 21.99" value="")
  end

  test "R5: a plan's outcome is said in a sentence, and the months are folded under it", %{
    views: v
  } do
    page = Html.plan_page(v["Dad"], "Dad", "job_stops", "", @today)

    assert page |> String.replace(~r{</?span[^>]*>}, "") |> text() =~
             "With this plan, cash first goes below zero in November 2026 and is lowest in September 2027, at −$45,128.33. Without it, cash doesn't go below zero in these 12 months; it is lowest in October 2026, at $3,426.67."

    assert page =~ "<details><summary>Month by month</summary>"
    # the amounts in the sentence stay whole on a phone
    assert page =~ ~s(at <span class=nowrap>−$45,128.33</span>.)
    assert Glossary.judgments(text(page)) == []
  end

  test "R6: retirement estimates are rounded to $100 and say so; what was typed stays exact", %{
    views: v
  } do
    page = Html.retirement_page(v["Dad"], "Dad", "", @today)
    # UX-003 C10: in whole dollars, without cents
    assert page =~ ~s(<p class="amount-big">about $244,200</p>)
    refute page =~ "$244,195.37"
    # every estimate on the page ends in whole hundreds and shows no cents
    estimates = Regex.scan(~r/about [+−]?\$([\d,]+)(\.\d\d)?/u, page)
    assert length(estimates) > 5

    for [_, dollars | cents] <- estimates do
      assert cents == []
      assert String.ends_with?(dollars, "00")
    end

    # the difference to pay comes from what Dad typed, so it stays exact
    assert page =~ "$3,200.00 a month"
    assert page =~ "estimates are rounded to the nearest $100"
  end

  test "R8: what a file brings in is named by kind; the word entries is kept out" do
    assert Glossary.violations("Brought in 5 entries") != []
    assert Glossary.violations("Brought in 3 items and 1 value") == []
  end
end
