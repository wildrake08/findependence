defmodule FindependenceApp.UX003Test do
  @moduledoc "UX-003's craft fixes (C1-C12) against their acceptance criteria, with the demo family."
  use ExUnit.Case, async: false

  alias FindependenceApp.{Session, Vault}
  alias FindependenceApp.Web.Html
  alias Mix.Tasks.Findependence.Demo

  @today ~D[2026-09-27]
  @source "lib/findependence_app/web.ex"

  setup_all do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-ux003-#{System.unique_integer([:positive])}.vault")
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

  defp pages(h) do
    [
      Html.home(h, "Dad", ""),
      Html.ahead_page(h, "Dad", @today),
      Html.next_60_page(h, "Dad", @today),
      Html.plan_page(h, "Dad", "job_stops", "", @today),
      Html.retirement_page(h, "Dad", "", @today),
      Html.item_page(h, "Dad", "dad_pay", "")
    ]
  end

  test "C1: focus is a token with at least 3:1 on every surface it can sit on, in no semantic hue" do
    focus = token("focus")

    for surface <- ~w(card bg err-bg ok-bg info-bg attention-bg),
        do: assert(ratio(focus, token(surface)) >= 3.0, "focus on --#{surface}")

    for other <- ~w(attention err accent), do: refute(focus == token(other))
    assert css() =~ ":focus-visible{outline:3px solid var(--focus);"

    assert css() =~
             "input[type=date]:focus,input[type=date]:focus-within{outline:3px solid var(--focus);"

    refute css() =~ "#f0b400"
  end

  test "C2: every numeric column's header is marked numeric, and only those", %{h: h} do
    tables = Enum.flat_map(pages(h), &Regex.scan(~r/<table .*?<\/table>/s, &1))
    assert length(tables) >= 8

    for [table] <- tables do
      heads = Regex.scan(~r/<th [^>]*>/, table) |> Enum.map(fn [th] -> th =~ "class=num" end)

      rows =
        Regex.scan(~r/<tr role=row(?: class=muted)?>\s*(<td.*?)<\/tr>/s, table,
          capture: :all_but_first
        )

      cols =
        for [row] <- rows,
            do: Regex.scan(~r/<td role=cell([^>]*)>/, row, capture: :all_but_first)

      cols = Enum.filter(cols, &(length(&1) == length(heads)))
      assert cols != []

      for {head_num?, i} <- Enum.with_index(heads) do
        cells_num? =
          Enum.all?(cols, fn cells ->
            cells |> Enum.at(i) |> hd() =~ ~r/class="?[a-z ]*\bnum\b/
          end)

        assert head_num? == cells_num?, "column #{i} of #{String.slice(table, 0, 120)}"
      end
    end

    assert css() =~ "th.num{white-space:normal}"
  end

  test "C3: a below-zero pill never moves its figure; on phones it has one place", %{h: h} do
    # DEF-034 (WI-047): the figure and its pill are one unit that doesn't wrap; read figure first
    assert Html.next_60_page(h, "Dad", @today) =~
             ~s(<span class=neg>−$1,790.00 <span class=below>Below zero</span></span>)

    assert css() =~
             ".neg{display:inline-flex;flex-direction:row-reverse;align-items:baseline;gap:.5rem;white-space:nowrap}"

    refute css() =~ ~r/\.below\{[^}]*float/
    assert css() =~ "table.stack td.num .neg{display:inline;white-space:normal}"
    assert css() =~ "table.flow td.fbal .below{display:table;margin:.1rem 0 0 auto}"
  end

  test "C4: inputs, selects, and buttons share one height; selects are white like inputs" do
    assert css() =~ ~r/input,select\{[^}]*height:var\(--control-h\)/
    assert css() =~ ~r/input,select\{[^}]*background-color:var\(--card\)/
    assert css() =~ ~r/(^|\n)  button\{[^}]*min-height:var\(--control-h\)/
    assert css() =~ ~r/\.inline button,td button\{[^}]*min-height:var\(--control-h-sm\)/
    assert css() =~ ~r/a\.button-link\{[^}]*min-height:var\(--control-h-sm\)/
    assert css() =~ "fieldset.direction>*{line-height:var(--control-h)}"
  end

  test "C5: every link is the accent, visited or not, and stays underlined" do
    assert css() =~ ":where(a:link,a:visited){color:var(--accent)}"
    refute css() =~ ~r/(^|[}\n])\s*a(:link|:visited)?\{[^}]*text-decoration:none/
  end

  test "C6: a field's error sits in the field's own group, right after its control", %{h: h} do
    home =
      Html.home(h, "Dad", "", nil, %{
        error: "Enter an amount like 62.40 or 1,200.",
        error_field: :amount,
        amount: "55,5"
      })

    assert home =~
             ~s(aria-describedby="amount-error" aria-invalid="true"><span class="field-error" id="amount-error" role="alert">Enter an amount like 62.40 or 1,200.</span></p>)

    visa =
      Html.item_page(h, "Dad", "dad_visa", "", nil, %{query: %{"extra" => "lots", "rate" => "x"}})

    assert visa =~
             ~s(value="lots" aria-invalid="true" aria-describedby="extra-error"><span class="field-error" id="extra-error" role="alert">)

    assert visa =~
             ~s(value="x" aria-invalid="true" aria-describedby="whatif-rate-error"><span class="field-error" id="whatif-rate-error" role="alert">)

    # each message appears once, and only inside the form
    for message <- [
          "Enter the extra amount like 100 or 100.00.",
          "Enter the rate as a percentage, like 10.5."
        ] do
      assert length(String.split(visa, message)) == 2
      [before, _] = String.split(visa, message)
      assert before =~ ~s(<form method=get action="/items/dad_visa" class=row>)
    end

    empty =
      Html.new_balance_page("", %{
        which: "debt",
        label: "",
        type: "card",
        error: "Give it a name."
      })

    assert empty =~
             ~s(aria-invalid="true" aria-describedby="debt-label-error"><span class="field-error" id="debt-label-error" role="alert">Give it a name.</span></p>)

    kind =
      Html.new_balance_page("", %{
        which: "account",
        label: "Joint",
        type: "",
        error: "Choose what kind it is."
      })

    assert kind =~
             ~s(<select id=account-type name=type required aria-invalid="true" aria-describedby="account-type-error">)

    assert kind =~ ~s(</select><span class="field-error" id="account-type-error" role="alert">)

    # a message is never a <p> after the whole row any more
    for page <- [home, visa, empty, kind], do: refute(page =~ ~s(<p class="field-error"))

    assert css() =~
             "input[aria-invalid=true],select[aria-invalid=true]{border-color:var(--err);box-shadow:0 0 0 1px var(--err)}"
  end

  test "C7: deleting, giving up ownership, and leaving are styled as destructive", %{h: h} do
    plan = Html.plan_page(h, "Dad", "job_stops", "", @today)

    assert plan =~
             ~s(<button class=danger aria-label="Delete the plan If Dad&#39;s job stops">Delete plan…</button>)

    # a joint item's page offers "Stop owning…", which leads to the confirmation
    home = Html.item_page(h, "Dad", "mortgage", "")
    assert home =~ ~s(<button class=danger aria-label="Stop owning Mortgage">)
    refute home =~ ~r/<button aria-label="(Delete|Stop owning)/
  end

  test "C8: cards trim their first and last margins; a plain list has no rule under its last item" do
    assert css() =~ ".card>:first-child{margin-top:0}.card>:last-child{margin-bottom:0}"
    assert css() =~ "ul.plain li:last-child{border-bottom:0}"
  end

  test "C9: the header sits on the same column as the page" do
    assert css() =~ "padding:.75rem max(1rem,calc((100% - var(--column))/2 + 1rem))"
    assert css() =~ ~r/main,footer\{max-width:var\(--column\)/
    assert css() =~ "header form.inline{display:flex;flex-wrap:wrap;justify-content:flex-end;"
  end

  test "C10: on home, the figure and how often it happens have their own cells", %{h: h} do
    home = Html.home(h, "Dad", "")

    assert home =~
             ~s(<th role=columnheader scope=col class=num>Amount</th><th role=columnheader scope=col>How often</th>)

    assert home =~
             ~s(>−$2,400.00<span class=phone-only> a year, irregular</span></td><td role=cell class=freq data-label="How often">a year, irregular</td>)

    refute home =~ ", a year, irregular"
    # the item's own page reads the same way, with no comma before "a year"
    assert Html.item_page(h, "Dad", "repairs", "") =~
             ~s(<p class="amount-big">−$2,400.00 a year, irregular</p>)

    # phones show the one cell they always did; the separate one is not displayed
    assert css() =~ "table.stack.compact td.freq{display:none}"
  end

  test "C11: every font size is a named step, and a detail page's title is the largest", %{h: h} do
    sizes = Regex.scan(~r/font-size:([^;}]+)/, css(), capture: :all_but_first) |> List.flatten()
    assert sizes != []
    for s <- sizes, do: assert(s =~ ~r/^var\(--fs-[a-z0-9]+\)$/, "font-size:#{s}")
    assert css() =~ ~r/font:var\(--fs-body\)\/1\.5/

    steps =
      Regex.scan(~r/--fs-([a-z0-9]+):([\d.]+)rem/, css(), capture: :all_but_first)
      |> Map.new(fn [k, v] -> {k, ("0" <> v) |> Float.parse() |> elem(0)} end)

    assert steps["title"] > steps["lg"] and steps["lg"] > steps["h2"]
    assert css() =~ ".back~section:first-of-type>h2{font-size:var(--fs-title)}"
    assert css() =~ ".amount-big{font-size:var(--fs-lg);"

    for page <- tl(pages(h)), do: assert(page =~ ~r/<p class=back><a href="[^"]+">← /)
    refute Html.home(h, "Dad", "") =~ "<p class=back>"
  end

  test "C12: checkbox groups are grids", %{h: h} do
    plan = Html.plan_page(h, "Dad", "job_stops", "", @today)
    assert plan =~ ~r/<legend>Which items\?<\/legend><div class=checks><label class=check>/
    assert plan =~ ~r/<legend>Ask<\/legend><div class=checks><label class=check>/
    pay = Html.item_page(h, "Dad", "dad_pay", "")

    assert pay =~
             ~r/<legend>Owners of “Dad&#39;s paycheck”<\/legend><div class=checks><label class=check>/

    assert css() =~
             ".checks{display:grid;grid-template-columns:repeat(auto-fill,9rem);"

    # two columns on phones, so a long list doesn't become one tall column
    assert css() =~ ".checks{grid-template-columns:repeat(2,minmax(0,1fr))}"
  end

  test "nothing moves: no transitions or animations (UX-003 section 4)" do
    refute css() =~ ~r/transition|animation|@keyframes/
  end
end
