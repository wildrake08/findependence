defmodule FindependenceApp.WI062Test do
  @moduledoc """
  WI-062 (CP-017 option C, DIR-001): the dark palette meets the contrast rules the light palette's tests
  apply (UX-001 R5, UX-003 C4, UX-005), and the tokens added for the new look meet them in both themes.
  """
  use ExUnit.Case, async: true

  @source "lib/findependence_app/web.ex"

  defp css do
    [css] = Regex.run(~r/@css """\n(.*?)\n  """/s, File.read!(@source), capture: :all_but_first)
    css
  end

  defp tokens(block) do
    Regex.scan(~r/--([a-z0-9-]+):(#[0-9a-f]{6}|#[0-9a-f]{3})\b/, block, capture: :all_but_first)
    |> Map.new(fn [k, v] -> {k, v} end)
  end

  defp light do
    [root] = Regex.run(~r/:root\{(.*?)\}/s, css(), capture: :all_but_first)
    tokens(root)
  end

  defp dark do
    [block] =
      Regex.run(~r/@media \(prefers-color-scheme:dark\)\{:root\{(.*?)\}\}/s, css(),
        capture: :all_but_first
      )

    tokens(block)
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

  # text 4.5:1 on each surface it is used on
  @text [
    {"ink", ~w(card bg sunk)},
    {"ink-2", ~w(card bg)},
    {"muted", ~w(card bg sunk)},
    {"accent", ~w(card bg sunk)},
    {"accent-hover", ~w(card bg sunk)},
    {"err", ~w(card err-bg)},
    {"ok", ~w(ok-bg)},
    {"info-ink", ~w(info-bg)},
    {"attention-ink", ~w(attention-bg)}
  ]

  test "every text colour is at least 4.5:1 on the surfaces it sits on, in both themes" do
    for {name, t} <- [light: light(), dark: dark()], {fg, surfaces} <- @text, bg <- surfaces do
      assert ratio(t[fg], t[bg]) >= 4.5, "#{name}: --#{fg} on --#{bg} is #{ratio(t[fg], t[bg])}"
    end
  end

  test "button text is at least 4.5:1 on the accent and its hover, in both themes" do
    for {name, t} <- [light: light(), dark: dark()], bg <- ~w(accent accent-hover) do
      assert ratio(t["accent-ink"], t[bg]) >= 4.5, "#{name}: --accent-ink on --#{bg}"
    end
  end

  test "dark: focus is at least 3:1 on every surface and distinct from the accent and state colours" do
    t = dark()

    for surface <- ~w(card bg sunk err-bg ok-bg info-bg attention-bg),
        do: assert(ratio(t["focus"], t[surface]) >= 3.0, "focus on --#{surface}")

    for other <- ~w(attention err accent), do: refute(t["focus"] == t[other])
  end

  test "field borders and state edges are at least 3:1 on the surfaces behind them, in both themes" do
    for {name, t} <- [light: light(), dark: dark()] do
      for bg <- ~w(card bg sunk),
          do:
            assert(
              ratio(t["control-border"], t[bg]) >= 3.0,
              "#{name}: --control-border on --#{bg}"
            )

      assert ratio(t["err"], t["card"]) >= 3.0, "#{name}: invalid field edge"
      assert ratio(t["attention"], t["card"]) >= 3.0, "#{name}: attention edge"
    end
  end

  test "the dark palette redefines every colour the light one sets, and nothing else" do
    assert Map.keys(dark()) |> Enum.sort() == Map.keys(light()) |> Enum.sort()
  end

  test "no JavaScript, web font, or remote reference in the stylesheet" do
    refute css() =~ ~r/@import|@font-face|url\(|https?:/
  end
end
