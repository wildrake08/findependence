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
    tables = Regex.scan(~r/<table class=stack[^>]*>.*?<\/table>/s, body) |> List.flatten()
    assert length(tables) == 3

    for t <- tables do
      assert t =~ ~r/<table class=stack role=table aria-label="[^"]+">/
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
end
