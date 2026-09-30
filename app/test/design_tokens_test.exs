defmodule FindependenceApp.DesignTokensTest do
  @moduledoc """
  WI-070 (ARCH-003 28, REV-092): one semantic design language for both forms. The colours are defined only
  in design/: the semantic tokens (design/tokens.css), which the local-first form serves as they are, and the
  fixed palette the hosted form's component library reads (design/palette.css), every colour of which is one
  of the tokens' light or dark values. Neither form's own stylesheet defines a colour.
  """
  use ExUnit.Case, async: true
  import Plug.Test

  @tokens "../design/tokens.css"
  @palette "../design/palette.css"
  @hosted "../hosted/assets/css/app.css"

  defp rules do
    [rules] =
      Regex.run(~r/@css_rules """\n(.*?)\n  """/s, File.read!("lib/findependence_app/web.ex"),
        capture: :all_but_first
      )

    rules
  end

  # every colour literal: hex, and rgb/hsl/hwb/lab/lch/oklab/oklch/color() functions
  defp colours(css) do
    css = String.replace(css, ~r{/\*.*?\*/}s, "")

    Regex.scan(
      ~r/#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\([^)]*\)/,
      css
    )
    |> List.flatten()
  end

  defp hex(css),
    do: css |> colours() |> Enum.filter(&String.starts_with?(&1, "#")) |> Enum.map(&norm/1)

  defp norm("#" <> <<r, g, b>>), do: String.downcase(<<?#, r, r, g, g, b, b>>)
  defp norm(h), do: String.downcase(h)

  test "every palette colour is one of the semantic tokens' light or dark values" do
    tokens = @tokens |> File.read!() |> hex() |> MapSet.new()
    missing = @palette |> File.read!() |> hex() |> Enum.reject(&(&1 in tokens)) |> Enum.uniq()
    assert missing == [], "palette colours that are not tokens: #{inspect(missing)}"
    assert @palette |> File.read!() |> hex() |> length() > 50
  end

  test "neither form's own stylesheet defines a colour" do
    assert colours(rules()) == [], "local-first rules"
    assert colours(File.read!(@hosted)) == [], "hosted app.css"
  end

  test "the local-first form serves the tokens exactly as design/tokens.css holds them" do
    conn = Plug.Conn.put_private(conn(:get, "/nowhere"), :fv_port, 4848)
    conn = %{conn | host: "127.0.0.1", port: 4848}
    body = FindependenceApp.Web.call(conn, FindependenceApp.Web.init(port: 4848)).resp_body
    [served] = Regex.run(~r/<style>(.*?)<\/style>/s, body, capture: :all_but_first)
    assert String.starts_with?(served, File.read!(@tokens))
    # the rules as the heredoc compiles them: its two-space source indentation removed
    assert served == File.read!(@tokens) <> String.replace(rules(), ~r/^  /m, "") <> "\n"
  end

  test "the checks find a planted colour in a stylesheet and a palette colour that is not a token" do
    assert colours(".x{color:#123456}.y{background:rgb(1 2 3)}/* #abcdef */") == [
             "#123456",
             "rgb(1 2 3)"
           ]

    tokens = MapSet.new(hex(File.read!(@tokens)))
    refute "#123456" in tokens
    assert norm("#FFF") == "#ffffff"
  end
end
