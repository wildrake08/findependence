defmodule FindependenceApp.AccessibilityTest do
  @moduledoc """
  UX-001 R10 (WI-024), automatable part: the phone layout restyles the item and value tables with
  display:block, which can remove table semantics in some browsers. Explicit roles keep them, the
  header row stays available to screen readers, and the on-screen labels aren't read twice.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Household}

  defp home do
    h = Household.new(["ana", "ben"])
    {:ok, h} = Household.add_item(h, "ana", "rent", %{note: "Rent", amount: -100, unit: :cents})
    {:ok, h} = Alignment.add_value(h, "ana", "home", "A safe home")
    Html.home(h, "ana", "")
  end

  defp css, do: File.read!("lib/findependence_app/web.ex")

  test "stacked tables carry explicit table roles on every part" do
    body = home()
    tables = Regex.scan(~r/<table class="?stack[^>]*>.*?<\/table>/s, body) |> List.flatten()
    assert length(tables) == 3

    for t <- tables do
      assert t =~ ~r/<table class=(?:stack|"stack[^"]*") role=table aria-label="[^"]+">/
      assert t =~ "<thead role=rowgroup><tr role=row>"
      assert t =~ "<tbody role=rowgroup>"
      assert length(Regex.scan(~r/<tr[ >](?!role=row)/, t)) == 0
      assert length(Regex.scan(~r/<td[ >](?!role=cell)/, t)) == 0
      assert length(Regex.scan(~r/<th[ >](?!role=columnheader scope=col)/, t)) == 0
    end
  end

  test "on phones the header row is hidden on screen but not from screen readers" do
    [_, phone] = String.split(css(), "@media (max-width:40rem){", parts: 2)
    refute phone =~ ~r/table\.stack thead\{[^}]*display:none/
    assert phone =~ ~r/table\.stack thead\{[^}]*clip-path:inset\(50%\)/
  end

  test "the on-screen cell labels have empty alternative text, so they aren't read twice" do
    assert css() =~
             ~s|table.stack td[data-label]::before{content:attr(data-label);content:attr(data-label) / "";|
  end

  test "on phones stacked cells wrap, so long amounts and names aren't clipped by the table's scroll box" do
    [_, phone] = String.split(css(), "@media (max-width:40rem){", parts: 2)
    assert phone =~ "table.stack td.num{text-align:left;white-space:normal}"
    assert phone =~ "table.stack td{min-width:0;overflow-wrap:anywhere}"
    assert phone =~ ~r/table\.stack td\[data-label\]::before\{[^}]*white-space:normal/
  end

  test "on phones items and values are compact two-line rows; names of who can see it say so" do
    h = Household.new(["ana", "ben"])
    {:ok, h} = Household.add_item(h, "ana", "rent", %{note: "Rent", amount: -100, unit: :cents})
    {:ok, h, _} = Household.propose_grant(h, "ana", "rent", "ben")
    body = Html.home(h, "ana", "")
    assert body =~ ~s(<table class="stack compact" role=table aria-label="Your items">)

    assert body =~
             ~s(<td role=cell class="meta vis" data-label="Who else can see it">ben<span class=phone-only> can see it</span></td>)

    css = css()
    [desktop, phone] = String.split(css, "@media (max-width:40rem){", parts: 2)
    assert desktop =~ ".phone-only{display:none}"
    assert phone =~ ".phone-only{display:inline}"
    assert phone =~ ~r/table\.stack\.compact tbody tr\{display:grid;/

    # the visual "Owned by" and separator are not read aloud; the header row already names the cell
    assert phone =~
             ~s|table.stack.compact td.owner::before{content:"Owned by ";content:"Owned by " / ""}|
  end

  test "date fields show a visible focus outline (their inner parts take focus in Chromium)" do
    assert css() =~
             "input[type=date]:focus,input[type=date]:focus-within{outline:3px solid var(--focus);"
  end

  test "on phones the totals and cash-flow tables are compact rows, and their short labels aren't read twice" do
    [_, phone] = String.split(css(), "@media (max-width:40rem){", parts: 2)
    assert phone =~ ~r/table\.dist tbody tr\{display:grid;/

    assert phone =~
             ~s|table.dist td[data-short]::before{content:attr(data-short) " ";content:attr(data-short) " " / "";|

    assert phone =~ ~r/table\.flow tbody tr\{display:grid;/

    assert phone =~
             ~s|table.flow td.fbal::before{content:"· Balance after ";content:"· Balance after " / "";|
  end

  test "on phones a figure in a compact table never splits between its sign and its digits" do
    [_, phone] = String.split(css(), "@media (max-width:40rem){", parts: 2)

    # "−" and "$" may otherwise break apart, so "−$1,328.33" would read as "$1,328.33" on its own line
    assert phone =~ "table.dist td.num{white-space:nowrap;overflow-wrap:normal}"
    # the label may still wrap above the figure, and the below-zero note takes its own line
    assert phone =~ "table.dist td.num::before{white-space:normal}"
    assert phone =~ ~r/table\.dist td\.num \.below\{display:table/
  end

  test "a hint under a field takes its own line, so it doesn't crowd the field" do
    assert css() =~ ".field-hint{display:block;"
  end
end
