defmodule FindependenceApp.VVF05DTest do
  @moduledoc """
  VV-001 F-05/F-08, batch D (WI-057): interface and encryption tests for acceptance criteria of
  REQ-149, REQ-150, REQ-153, REQ-154, REQ-156, REQ-158, and REQ-174 that no earlier test
  asserted. The criteria are in project/assurance/vv/acceptance-d.yaml. Helpers are copied from
  v04_web_test.exs, v05_web_test.exs, and readings_crypto_test.exs. Today is fixed at Sunday,
  November 15, 2026.
  """
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Money, Session, Sessions, Store, Vault, Web}
  alias FindependenceShared.Crypto
  alias FindependenceApp.Web.{Glossary, Html}
  alias Findependence.{Balances, Exit, Household, Plans, Retirement}

  @today ~D[2026-11-15]
  @dir System.tmp_dir!()

  setup do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(@dir, "fv-vvd-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana pass 1"}, {"ben", "ben pass 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    ana = login("ana", "ana pass 1")

    chk = new_id(post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"}))
    post(ana, "/act/add_reading", %{"item" => chk, "balance" => "1,000", "on" => "2026-11-01"})

    k401 =
      new_id(
        post(ana, "/act/add_account", %{"label" => "Work 401(k)", "type" => "retirement_401k"})
      )

    post(ana, "/act/add_reading", %{"item" => k401, "balance" => "10,000", "on" => "2026-11-01"})

    %{path: path, ana: ana, k401: k401}
  end

  # --- helpers copied from v04_web_test.exs and v05_web_test.exs

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  defp form_id(page), do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp from_page(page, path, params \\ %{}),
    do:
      request(
        :post,
        path,
        Map.merge(params, %{"_csrf_token" => token(page), "_form" => form_id(page)}),
        page
      )

  defp post(prev, path, params) do
    page = request(:get, "/", %{}, prev)

    request(
      :post,
      path,
      Map.merge(params, %{"_csrf_token" => token(page), "_form" => form_id(page)}),
      page
    )
  end

  defp login(m, p), do: post(request(:get, "/"), "/login", %{"member" => m, "passphrase" => p})
  defp loc(resp), do: resp |> Plug.Conn.get_resp_header("location") |> hd()
  defp new_id(resp), do: resp |> loc() |> String.split("/") |> List.last()
  defp follow(resp), do: request(:get, loc(resp), %{}, resp).resp_body

  defp household(path, m \\ "ana", p \\ "ana pass 1") do
    {:ok, s} = Session.open(Vault.read!(path), m, p)
    s.household
  end

  defp visible_text(html),
    do:
      html
      |> String.replace(~r/<style>.*?<\/style>/s, "")
      |> String.replace(~r/<[^>]+>/, " ")
      |> String.replace(~r/\s+/, " ")

  defp assumptions(k401, extra) do
    Map.merge(
      %{
        "birth_year" => "1961",
        "retire_age" => "67",
        "return" => "12",
        ("contribution_" <> k401) => "100",
        "ss" => "",
        "target" => ""
      },
      extra
    )
  end

  defp upload(prev, contents, name \\ "findependence-export.json") do
    file = Path.join(@dir, "fv-upload-#{System.unique_integer([:positive])}.json")
    File.write!(file, contents)
    on_exit(fn -> File.rm(file) end)

    post(prev, "/act/bring-in", %{
      "file" => %Plug.Upload{path: file, filename: name, content_type: "application/json"}
    })
  end

  # The file someone saved in another household (v05_web_test.exs), with a debt and a set-aside too.
  defp saved_file do
    h = Household.new(["dad", "mom"])

    {:ok, h} =
      Household.add_item(h, "dad", "pay", %{
        note: "Paycheck",
        amount: 265_000,
        unit: :cents,
        frequency: {:every, 2, :week}
      })

    {:ok, h} =
      Household.add_item(h, "dad", "health", %{
        note: "Health plan",
        amount: -9_000,
        unit: :cents,
        frequency: {:every, 1, :month}
      })

    {:ok, h} =
      Household.add_item(h, "dad", "rent", %{
        note: "Rent",
        amount: -150_000,
        unit: :cents,
        frequency: {:every, 1, :month}
      })

    {:ok, h, _} = Household.propose_owners(h, "dad", "rent", ["dad", "mom"])
    {:ok, h} = Findependence.Alignment.add_value(h, "dad", "home", "A safe home")
    {:ok, h} = Findependence.Alignment.link(h, "dad", "rent", "home")
    {:ok, h} = Balances.add_account(h, "dad", "chk", "Checking", :checking)
    {:ok, h} = Balances.add_reading(h, "dad", "chk", %{on: "2026-09-01", balance: 50_000})
    {:ok, h} = Balances.add_reading(h, "dad", "chk", %{on: "2026-09-26", balance: 42_000})
    {:ok, h} = Balances.add_debt(h, "dad", "visa", "Visa", :card)

    {:ok, h} =
      Balances.add_reading(h, "dad", "visa", %{
        on: "2026-09-26",
        balance: 620_000,
        rate_bp: 2499,
        min_payment: 19_000
      })

    {:ok, h} = Plans.mark(h, "dad", "health", "pay")
    {:ok, h} = Plans.new_plan(h, "dad", "p1", "If the job stops")
    {:ok, h} = Plans.add_step(h, "dad", "p1", {:switch_off, ["pay"], "2026-11"})
    {:ok, h} = Plans.set_fund_goal(h, "dad", 3)
    {:ok, h} = Plans.set_aside(h, "dad", "home", 2500)
    {:ok, h} = Retirement.set(h, "dad", :retire_age, 67)
    {:ok, h, _} = Plans.propose_shared(h, "dad", "p1", "sp1", ["mom"])
    Html.export_json(Exit.export(h, "dad"))
  end

  # --- helpers copied from readings_crypto_test.exs

  @opts [iterations: 1_000, unsafe_test: true]

  defp act(v, m, fun) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
    end
  end

  defp view(v, m) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)
    s
  end

  defp can_open?(v, m, id, seq) do
    s = view(v, m)
    r = Enum.find(v.items[id].readings, &(&1.seq == seq))
    sealed = r && r.keys[m]

    sealed != nil and
      match?(
        {:ok, _},
        Crypto.open(s.pub, s.priv, sealed, Vault.aad(v.hid, {:reading_key, id, seq, m}))
      )
  end

  # --- the retirement page's wording, as the page words it

  defp months_text(n) when n < 12, do: "#{n} #{if n == 1, do: "month", else: "months"}"

  defp months_text(n) do
    {y, mo} = {div(n, 12), rem(n, 12)}
    years = "#{y} #{if y == 1, do: "year", else: "years"}"
    if mo == 0, do: years, else: "#{years} and #{mo} #{if mo == 1, do: "month", else: "months"}"
  end

  defp lasts_short(%{lasts: nil}), do: "No target set"
  defp lasts_short(%{lasts: :covered}), do: "No difference to pay"
  defp lasts_short(%{lasts: :beyond}), do: "Some remains at 100"

  defp lasts_short(%{lasts: {:months, n}, retire_age: a}),
    do: "#{months_text(n)}, to about age #{a + div(n, 12)}"

  defp alt_label(:as_entered), do: "As you entered"
  defp alt_label({:return, -200}), do: "Return 2 points lower"
  defp alt_label({:return, 200}), do: "Return 2 points higher"
  defp alt_label({:retire_age, -2}), do: "Retiring 2 years earlier"
  defp alt_label({:retire_age, 2}), do: "Retiring 2 years later"

  # the text inputs a member types into, as {name, the whole tag}
  defp inputs(page) do
    for [tag] <- Regex.scan(~r/<input [^>]*>/, page),
        not (tag =~ "type=hidden"),
        do: {Regex.run(~r/name="?([^" >]+)/, tag) |> List.last(), tag}
  end

  # ---------------------------------------------------------------------------
  # REQ-149

  test "REQ-149: an IRA shared with someone shows them its latest balance only, and they can't update it",
       %{path: path, ana: ana} do
    ira = new_id(post(ana, "/act/add_account", %{"label" => "Roll-over IRA", "type" => "ira"}))

    for {bal, on} <- [{"20,000", "2026-10-01"}, {"21,500", "2026-11-01"}],
        do: post(ana, "/act/add_reading", %{"item" => ira, "balance" => bal, "on" => on})

    owner_page = request(:get, "/items/#{ira}", %{}, ana).resp_body
    assert owner_page =~ "<h2>Earlier balances</h2>" and owner_page =~ "$20,000.00"

    # before it's shared, ben can't see it at all
    ben = login("ben", "ben pass 2")
    refute request(:get, "/items/#{ira}", %{}, ben).resp_body =~ "Roll-over IRA"

    # another login ends ana's session here, so she unlocks again to share it
    ana = login("ana", "ana pass 1")
    post(ana, "/act/grant", %{"item" => ira, "member" => "ben"})
    ben = login("ben", "ben pass 2")
    page = request(:get, "/items/#{ira}", %{}, ben).resp_body
    assert page =~ "$21,500.00"
    refute page =~ "$20,000.00"
    refute page =~ "Earlier balances"
    refute page =~ ~s(action="/act/add_reading")

    resp = post(ben, "/act/add_reading", %{"item" => ira, "balance" => "1", "on" => "2026-11-15"})
    assert resp.status == 422
    assert resp.resp_body =~ "Only an owner can update the balance."
    assert length(household(path).readings[ira]) == 2
  end

  test "REQ-149 (REQ-133): each IRA reading has its own key, sealed only to those who may read it" do
    v =
      Vault.create([{"mom", "pw-mom"}, {"dad", "pw-dad"}, {"kid", "pw-kid"}], @opts)
      |> act("dad", &Balances.add_account(&1, "dad", "ira", "Dad's IRA", :ira))
      |> act("dad", &Balances.add_reading(&1, "dad", "ira", %{on: "2026-10-01", balance: 1}))
      |> act("dad", &Balances.add_reading(&1, "dad", "ira", %{on: "2026-11-01", balance: 2}))
      |> act("dad", &Household.propose_grant(&1, "dad", "ira", "mom"))

    [r1, r2] = v.items["ira"].readings
    # distinct keys: the sealed key for one reading is not the sealed key for the other
    refute r1.keys["dad"] == r2.keys["dad"]
    assert can_open?(v, "dad", "ira", 1) and can_open?(v, "dad", "ira", 2)
    refute can_open?(v, "mom", "ira", 1)
    assert can_open?(v, "mom", "ira", 2)
    refute can_open?(v, "kid", "ira", 1) or can_open?(v, "kid", "ira", 2)

    # stopping sharing removes Mom's key, and a later reading is never sealed to her
    v = act(v, "dad", &Household.revoke_grant(&1, "dad", "ira", "mom"))
    refute can_open?(v, "mom", "ira", 2)
    v = act(v, "dad", &Balances.add_reading(&1, "dad", "ira", %{on: "2026-12-01", balance: 3}))
    assert Enum.all?(v.items["ira"].readings, &(not Map.has_key?(&1.keys, "mom")))
    assert can_open?(v, "dad", "ira", 3)
  end

  # ---------------------------------------------------------------------------
  # REQ-150 and REQ-154

  test "REQ-150: every assumption, including birth year, Social Security, and target, is cleared by an empty field",
       %{path: path, ana: ana, k401: k401} do
    follow(
      post(ana, "/act/retirement", assumptions(k401, %{"ss" => "2,000", "target" => "3,000"}))
    )

    s = Retirement.settings(household(path), "ana")
    assert s.birth_year == 1961 and s.ss_monthly == 200_000 and s.target_monthly == 300_000

    empty = %{
      "birth_year" => "",
      "retire_age" => "",
      "return" => "",
      ("contribution_" <> k401) => "",
      "ss" => "",
      "target" => ""
    }

    page = follow(post(ana, "/act/retirement", empty))
    assert page =~ "Saved your retirement assumptions."

    assert Retirement.settings(household(path), "ana") == %{
             birth_year: nil,
             retire_age: nil,
             return_bp: nil,
             ss_monthly: nil,
             target_monthly: nil,
             contributions: %{}
           }

    # and the form shows them empty again
    for {name, tag} <- inputs(page), do: assert(tag =~ ~s(value=""), "#{name}: #{tag}")
  end

  test "REQ-150: an invalid birth year, Social Security estimate, or contribution is refused, with what was typed kept",
       %{path: path, ana: ana, k401: k401} do
    follow(post(ana, "/act/retirement", assumptions(k401, %{"ss" => "2,000"})))
    before = Retirement.settings(household(path), "ana")

    resp =
      post(
        ana,
        "/act/retirement",
        assumptions(k401, %{
          "birth_year" => "19x1",
          "ss" => "2,00",
          ("contribution_" <> k401) => "abc",
          "retire_age" => "70"
        })
      )

    assert resp.status == 422
    page = resp.resp_body
    assert page =~ "Nothing was saved. Check the fields marked below."

    for {name, typed} <- [
          {"birth_year", "19x1"},
          {"ss", "2,00"},
          {"contribution_" <> k401, "abc"}
        ] do
      assert page =~
               ~s(name="#{name}" inputmode=) and
               page =~ ~s(value="#{typed}" aria-invalid="true" aria-describedby="#{name}-error"),
             name

      assert page =~ ~s(id="#{name}-error")
    end

    # the valid field is kept as typed too, and nothing was saved
    assert page =~ ~s(value="70")
    assert Retirement.settings(household(path), "ana") == before
  end

  test "REQ-150/154: nothing is filled in or offered in any assumption field", %{ana: ana} do
    page = request(:get, "/retirement", %{}, ana).resp_body
    fields = inputs(page)

    assert Enum.map(fields, &elem(&1, 0)) |> Enum.sort() ==
             Enum.sort(
               ["birth_year", "retire_age", "return", "ss", "target"] ++
                 for({n, _} <- fields, String.starts_with?(n, "contribution_"), do: n)
             )

    assert Enum.any?(fields, fn {n, _} -> String.starts_with?(n, "contribution_") end)

    for {name, tag} <- fields do
      assert tag =~ ~s(value=""), "#{name} is filled in: #{tag}"
      refute tag =~ ~r/\b(placeholder|list)=/, "#{name} offers a value: #{tag}"
    end

    refute page =~ ~r/<(select|datalist|textarea)\b/
  end

  test "REQ-154: no retirement page suggests an investment, a product, or a value; every state passes the judgment-word and glossary checks",
       %{ana: ana, k401: k401} do
    get = fn who -> request(:get, "/retirement", %{}, who).resp_body end
    save = fn extra -> follow(post(ana, "/act/retirement", assumptions(k401, extra))) end

    empty = get.(ana)
    # only a birth year: the projection says what's missing
    missing = save.(%{"retire_age" => "", "return" => ""})
    full = save.(%{"target" => "3,000", "ss" => "2,000"})
    beyond = save.(%{"target" => "2,010", "ss" => "2,000"})
    covered = save.(%{"target" => "2,000", "ss" => "2,500"})
    refused = post(ana, "/act/retirement", assumptions(k401, %{"return" => "99"})).resp_body
    account = request(:get, "/items/#{k401}", %{}, ana).resp_body
    # a member with no retirement account
    none = get.(login("ben", "ben pass 2"))

    for {state, page} <- [
          empty: empty,
          missing: missing,
          full: full,
          beyond: beyond,
          covered: covered,
          refused: refused,
          account: account,
          none: none
        ] do
      text = visible_text(page)
      assert Glossary.judgments(text) == [], "#{state}: #{inspect(Glossary.judgments(text))}"
      assert Glossary.violations(text) == [], "#{state}"

      # the page's own disclaimer, "nothing here is advice or a suggestion", says the opposite
      text = String.replace(text, "nothing here is advice or a suggestion", "")

      refute text =~
               ~r/\b(you should|should|we recommend|recommend\w*|suggest\w*|consider|advis\w+|ought|try to|aim for|make sure|better|best|ideal|enough|too (little|low|much|high)|on track|behind|ahead of)\b/i,
             "#{state}: a recommending phrase"

      refute text =~
               ~r/\b(index fund|mutual fund|target[- ]date|annuit\w+|ETFs?|stocks?|bonds?|Roth|brokerage|CDs?|treasur\w+|crypto\w*|real estate|gold|Vanguard|Fidelity|Schwab)\b/i,
             "#{state}: names an investment or product"
    end
  end

  # ---------------------------------------------------------------------------
  # REQ-153 and REQ-174

  test "REQ-153: each alternative says how long it would last, beside the result",
       %{path: path, ana: ana, k401: k401} do
    page =
      follow(
        post(ana, "/act/retirement", assumptions(k401, %{"target" => "3,000", "ss" => "2,000"}))
      )

    alts = Retirement.sensitivity(household(path), "ana", @today)
    assert length(alts) == 5

    for alt <- alts do
      assert {:months, _} = alt.lasts

      assert page =~
               ~r/<b>#{Regex.escape(alt_label(alt.change))}<\/b><\/td>.*?data-label="Paying the difference" data-short="Paying the difference">#{Regex.escape(lasts_short(alt))}<\/td><\/tr>/,
             "#{alt_label(alt.change)}: #{lasts_short(alt)}"
    end

    # the alternatives don't all say the same thing
    assert alts |> Enum.map(&lasts_short/1) |> Enum.uniq() |> length() > 1
  end

  test "REQ-174: 'some would remain at age 100' is said when the balance outlasts it", %{
    ana: ana,
    k401: k401
  } do
    page =
      follow(
        post(ana, "/act/retirement", assumptions(k401, %{"target" => "2,010", "ss" => "2,000"}))
      )

    assert page =~
             "Paying the difference between your target income and Social Security, $10.00 a month, from these accounts, some would remain at age 100."

    refute page =~ "would last"
    assert page =~ "Some remains at 100"
  end

  test "REQ-174: every figure on the page is one the member set, one worked out from them, or an alternative REQ-153 shows",
       %{path: path, ana: ana, k401: k401} do
    page =
      follow(
        post(ana, "/act/retirement", assumptions(k401, %{"target" => "3,000", "ss" => "2,000"}))
      )

    h = household(path)
    s = Retirement.settings(h, "ana")
    p = Retirement.project(h, "ana", @today)
    alts = Retirement.sensitivity(h, "ana", @today)

    plain = fn c -> c |> Money.format() |> String.replace_prefix("+", "") end
    round = fn c -> div(c + 5_000, 10_000) * 10_000 end
    about = fn c -> c |> round.() |> plain.() |> String.replace_suffix(".00", "") end
    about_signed = fn c -> c |> round.() |> Money.format() |> String.replace_suffix(".00", "") end

    # set by the member
    set = [s.ss_monthly, s.target_monthly | Map.values(s.contributions)]
    # read from the member's accounts, and worked out from what they set
    worked =
      [p.start.balance, p.monthly_contribution, p.gap] ++
        for(id <- p.start.read, do: Balances.latest(h, "ana", id).balance) ++
        Enum.map(p.rows, & &1.contributed)

    allowed =
      MapSet.new(
        # the rounding the page states: "rounded to the nearest $100"
        Enum.map(set ++ worked, plain) ++
          Enum.map([p.at_retirement | Enum.map(p.rows, & &1.balance)], about) ++
          Enum.map(p.rows, &about_signed.(&1.growth)) ++
          Enum.map(alts, &about.(&1.at_retirement)) ++
          ["$100"]
      )

    text = visible_text(page)
    amounts = Regex.scan(~r/[−+]?\$[\d,]+(?:\.\d\d)?/u, text) |> Enum.map(&hd/1)
    assert amounts != []
    for a <- amounts, do: assert(a in allowed, "#{a} isn't a figure the member set")

    rates = Regex.scan(~r/[−-]?\d+(?:\.\d+)?%/u, text) |> Enum.map(&hd/1) |> Enum.uniq()
    allowed_rates = alts |> Enum.map(&Html.rate_text(&1.return_bp)) |> Enum.uniq()
    assert Enum.sort(rates) == Enum.sort(allowed_rates)
  end

  # ---------------------------------------------------------------------------
  # REQ-156 and REQ-158

  test "REQ-156: the member is told that owners, sharing, history, and shared plans aren't brought in",
       %{ana: ana} do
    preview = upload(ana, saved_file())
    assert preview.status == 200

    assert preview.resp_body =~
             "All of it becomes yours alone. Its history, owners, and who it was shared with in the other household stay in your file."

    assert preview.resp_body =~
             "1 shared plan isn&#39;t brought in: it was an agreement with others in the other household." or
             preview.resp_body =~
               "1 shared plan isn't brought in: it was an agreement with others in the other household."

    home = follow(from_page(preview, "/act/bring-in/confirm"))
    assert home =~ "Only you own them; nobody else can see them until you share."
  end

  test "REQ-158: the preview counts debts and goals, with the debts' names", %{
    path: path,
    ana: ana
  } do
    before = map_size(household(path).items)
    page = upload(ana, saved_file()).resp_body
    assert page =~ "<li>3 items: Health plan, Paycheck, Rent</li>"
    assert page =~ "<li>1 value: A safe home</li>"
    assert page =~ "<li>1 account: Checking</li>"
    assert page =~ "<li>1 debt: Visa</li>"
    assert page =~ "<li>3 balances</li>"
    assert page =~ "<li>1 link to a value</li>"
    assert page =~ "<li>1 mark on what depends on a job</li>"
    # a fund goal of 3 months and one set-aside rate
    assert page =~ "<li>2 goals</li>"
    assert page =~ "<li>1 plan: If the job stops</li>"
    assert map_size(household(path).items) == before
  end

  # ---------------------------------------------------------------------------
  # REQ-157

  test "REQ-157: a file of exactly 1 MB is checked; one byte more is refused", %{ana: ana} do
    json = saved_file()
    exact = json <> String.duplicate(" ", 1_048_576 - byte_size(json))
    assert byte_size(exact) == 1_048_576
    resp = upload(ana, exact)
    assert resp.status == 200
    assert resp.resp_body =~ "What would be brought in"

    over = upload(ana, exact <> " ")
    assert over.status == 422
    assert over.resp_body =~ "An export file is at most 1 MB"
  end
end
