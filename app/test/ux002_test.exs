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

    assert dad =~
             "Counts only items you own. Joint checking is also owned by Mom, and items Mom owns aren't counted, so the balance after each day is your part of the picture, not the account's balance."

    mom = text(Html.coming_up_card(v["Mom"], "Mom", @today))
    assert mom =~ "Joint checking is also owned by Dad, and items Dad owns aren't counted"

    ahead = text(Html.ahead_page(v["Dad"], "Dad", @today))

    assert ahead =~
             "Joint checking and Savings are also owned by Mom, and items Mom owns aren't counted, so the cash at the end of each month is your part of the picture, not the accounts' balance."

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
    assert own =~ "Counts only items you own; items others share with you"
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

    assert text(page) =~
             "With this plan, cash first goes below zero in November 2026 and is lowest in September 2027, at −$45,128.33. Without it, cash doesn't go below zero in these 12 months; it is lowest in October 2026, at $3,426.67."

    assert page =~ "<details><summary>Month by month</summary>"
    assert Glossary.judgments(text(page)) == []
  end

  test "R6: retirement estimates are rounded to $100 and say so; what was typed stays exact", %{
    views: v
  } do
    page = Html.retirement_page(v["Dad"], "Dad", "", @today)
    assert page =~ ~s(<p class="amount-big">about $244,200.00</p>)
    refute page =~ "$244,195.37"
    # every estimate on the page ends in whole hundreds
    for [_, cents] <- Regex.scan(~r/about [+−]?\$[\d,]+\.(\d\d)/u, page),
        do: assert(cents == "00")

    for [_, d] <- Regex.scan(~r/about [+−]?\$[\d,]*(\d\d)\.00/u, page), do: assert(d == "00")
    # the difference to pay comes from what Dad typed, so it stays exact
    assert page =~ "$3,200.00 a month"
    assert page =~ "estimates are rounded to the nearest $100"
  end

  test "R8: what a file brings in is named by kind; the word entries is kept out" do
    assert Glossary.violations("Brought in 5 entries") != []
    assert Glossary.violations("Brought in 3 items and 1 value") == []
  end
end
