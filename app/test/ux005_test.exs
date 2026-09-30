defmodule FindependenceApp.UX005Test do
  @moduledoc "UX-005 S1, S2, and S3 (WI-051) against their acceptance criteria, with the demo family."
  use ExUnit.Case, async: false

  alias FindependenceApp.{Session, Vault}
  alias FindependenceApp.Web.Html
  alias Mix.Tasks.Findependence.Demo

  @today ~D[2026-09-27]
  @source "lib/findependence_app/web.ex"

  setup_all do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-ux005-#{System.unique_integer([:positive])}.vault")
    :ok = Demo.build(path, iterations: 1_000, unsafe_test: true, today: @today)
    on_exit(fn -> File.rm(path) end)
    {:ok, s} = Session.open(Vault.read!(path), "Dad", Map.new(Demo.members())["Dad"])
    %{h: s.household}
  end

  # the page stylesheet, as the browser receives it
  # WI-070 (REV-090): the tokens are read from design/tokens.css, the rules from web.ex
  defp css do
    [rules] =
      Regex.run(~r/@css_rules """\n(.*?)\n  """/s, File.read!(@source), capture: :all_but_first)

    File.read!("../design/tokens.css") <> rules
  end

  defp token(name) do
    [hex] = Regex.run(~r/--#{name}:(#[0-9a-f]{6}|#[0-9a-f]{3})\b/, css(), capture: :all_but_first)
    hex
  end

  defp lum("#" <> <<r, g, b>>), do: lum(<<?#, r, r, g, g, b, b>>)

  defp lum(hex) do
    <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = String.trim_leading(hex, "#")

    [r, g, b]
    |> Enum.map(&(String.to_integer(&1, 16) / 255))
    |> Enum.map(fn c ->
      if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
    end)
    |> then(fn [r, g, b] -> 0.2126 * r + 0.7152 * g + 0.0722 * b end)
  end

  defp ratio(a, b) do
    [l1, l2] = Enum.sort([lum(a), lum(b)], :desc)
    (l1 + 0.05) / (l2 + 0.05)
  end

  defp forced_colors do
    [block] =
      Regex.run(~r/@media \(forced-colors:active\)\{\n(.*?)\n  \}/s, css(),
        capture: :all_but_first
      )

    block
  end

  test "S1: under forced colours, each state that is drawn by a fill or shadow also has a border" do
    fc = forced_colors()
    assert fc =~ "input[aria-invalid=true],select[aria-invalid=true]{border-width:3px}"
    assert fc =~ ".msg,.below,.badge{border:1px solid CanvasText}"
    assert fc =~ ".card.attention,.card.warn{border-width:3px}"
    # solid buttons (and the confirming danger button) are heavier than outline ones
    assert fc =~ "button,.card.warn button.danger{border-width:2px}"
    assert fc =~ ".inline button:not(.primary),td button,button.danger{border-width:1px}"
  end

  test "S2: the attention edge has at least 3:1 on the card and the ground, and is heavier than a card's border" do
    for surface <- ["card", "bg"], do: assert(ratio(token("attention"), token(surface)) >= 3.0)

    assert css() =~
             ~r/\.card\.attention\{border-color:var\(--attention\);border-inline-start-width:4px;/

    assert css() =~ ~r/\.card\{[^}]*border:1px solid/
    # it stays amber, apart from error red and the focus ink
    refute token("attention") in [token("err"), token("focus")]
  end

  test "S3: no figure after 'about' has cents; rounded retirement figures keep 'about'", %{h: h} do
    pages = [
      Html.home(h, "Dad", ""),
      Html.next_60_page(h, "Dad", @today),
      Html.item_page(h, "Dad", "dad_visa", ""),
      Html.item_page(h, "Dad", "dad_pay", ""),
      Html.item_page(h, "Dad", "car_ins", ""),
      Html.retirement_page(h, "Dad", "", @today)
    ]

    for page <- pages, do: refute(page =~ ~r/about [+\x{2212}]?\$[\d,]+\.\d\d/iu)

    [next_60, visa, pay] = [Enum.at(pages, 1), Enum.at(pages, 2), Enum.at(pages, 3)]
    assert next_60 =~ "Setting aside <b>$390.00 a month</b> covers these:"

    assert visa =~
             ~r/a month&#39;s interest on \$6,200\.00 is \$129\.12\.|a month's interest on \$6,200\.00 is \$129\.12\./

    assert visa =~ ~r/to clear, with \$4,291\.12 of interest\./
    assert pay =~ "Counted as +$5,741.67 a month in your totals."
    assert Enum.at(pages, 5) =~ ~s(<p class="amount-big">about $244,200</p>)
  end
end
