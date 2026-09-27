defmodule FindependenceApp.V04WebTest do
  @moduledoc "v0.4 at the interface (REQ-149..154), with today fixed at Sunday, November 15, 2026."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  setup do
    Application.put_env(:findependence_app, :today, ~D[2026-11-15])
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-v04-#{System.unique_integer([:positive])}.vault")

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

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  # the page's one-time form token, as a browser sends it with the form (REQ-165, DEF-041)
  defp form_id(page), do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

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
    do: html |> String.replace(~r/<style>.*?<\/style>/s, "") |> String.replace(~r/<[^>]+>/, " ")

  # born 1961, retiring at 67 (January 2028), 12% a year (1% a month), 100.00 a month into the 401(k)
  defp assumptions(k401, extra \\ %{}) do
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

  test "home links to the retirement page without adding forms", %{ana: ana} do
    home = request(:get, "/", %{}, ana).resp_body
    assert home =~ ~s(<a href="/goals">Goals</a> · <a href="/retirement">Retirement</a>)
    refute home =~ ~s(action="/act/retirement")
  end

  test "REQ-149: a 401(k) is an account with a balance, but never cash", %{ana: ana, k401: k401} do
    page = request(:get, "/items/#{k401}", %{}, ana).resp_body
    assert page =~ "401(k)" and page =~ "$10,000.00"

    assert page =~ "A retirement account: it isn&#39;t counted as cash." or
             page =~ "A retirement account: it isn't counted as cash."

    assert request(:get, "/balances/new", %{}, ana).resp_body =~
             ~s(<option value="ira">IRA</option>)

    # the next twelve months start from checking alone
    assert request(:get, "/ahead", %{}, ana).resp_body =~
             "Cash starts from Checking: $1,000.00."
  end

  test "REQ-150/151: assumptions saved together; the projection with its assumptions stated", %{
    path: path,
    ana: ana,
    k401: k401
  } do
    page = request(:get, "/retirement", %{}, ana).resp_body

    assert page =~
             "To see a projection, enter your birth year, a retirement age, and a yearly return below."

    # nothing is filled in for the member
    assert page =~
             ~s(id="retire_age" name="retire_age" inputmode=numeric autocomplete=off value="")

    resp = post(ana, "/act/retirement", assumptions(k401))
    page = follow(resp)
    assert page =~ "Saved your retirement assumptions."
    assert page =~ "In January 2028, the year you turn 67:"
    assert page =~ ~s(<p class="amount-big">about $13,000</p>)
    # 2026: November and December at 1% a month plus 100.00 each (computed as in the core test)
    assert page =~
             ~s(data-label="Growth" data-short="Growth">about +$200</td><td role=cell class=num data-label="Balance at the end" data-short="Balance">about $10,400<)

    # the year-by-year table is folded away under its own summary
    assert page =~ "<details><summary>Year by year, 2 years</summary>"
    assert page =~ "starting from Work 401(k) ($10,000.00 as of Sunday, November 1)"
    assert page =~ "adding $100.00 a month as you entered"
    assert page =~ "at 12% a year after inflation, the return you entered"

    assert page =~
             "Everything is in today's dollars, and estimates are rounded to the nearest $100."

    assert page =~ "Enter a target income below to compare with it."

    # stored in ana's private record; ben's are untouched
    s = Findependence.Retirement.settings(household(path), "ana")
    assert s.return_bp == 1200 and s.contributions == %{k401 => 10_000}
    # ben's session can't read ana's record: he sees only his own, empty assumptions
    ben_h = household(path, "ben", "ben pass 2")
    assert Findependence.Retirement.settings(ben_h, "ana").retire_age == nil
    assert Findependence.Retirement.settings(ben_h, "ben").retire_age == nil

    ben = login("ben", "ben pass 2")
    ben_page = request(:get, "/retirement", %{}, ben).resp_body
    refute ben_page =~ "1961"
    refute ben_page =~ "Work 401(k)"

    # an empty field clears that assumption
    ana = login("ana", "ana pass 1")
    follow(post(ana, "/act/retirement", assumptions(k401, %{"return" => ""})))
    assert Findependence.Retirement.settings(household(path), "ana").return_bp == nil
  end

  test "REQ-150: invalid values are refused at the field, with what was typed kept", %{
    path: path,
    ana: ana,
    k401: k401
  } do
    resp =
      post(
        ana,
        "/act/retirement",
        assumptions(k401, %{"return" => "20", "retire_age" => "sixty", "target" => "5,00"})
      )

    assert resp.status == 422
    page = resp.resp_body
    assert page =~ "Nothing was saved. Check the fields marked below."
    # said where the page opens, too, with a link to the fields
    assert page =~
             ~s(<p class="msg err" role="alert">Nothing was saved. <a href="#assumptions">Check the fields marked in your assumptions.</a></p>)

    assert page =~ ~s(<section class=card id=assumptions>)
    assert page =~ "Enter a yearly return from −5 to 15, like 5 or 4.5."
    assert page =~ "Enter an age from 40 to 90."
    assert page =~ ~s(value="sixty" aria-invalid="true" aria-describedby="retire_age-error")
    assert page =~ ~s(value="20" aria-invalid="true")
    assert page =~ ~s(value="5,00" aria-invalid="true")
    # the valid ones are kept as typed too, and nothing was saved
    assert page =~ ~s(value="1961")
    assert Findependence.Retirement.settings(household(path), "ana").birth_year == nil

    # a negative return is allowed, down to −5
    follow(post(ana, "/act/retirement", assumptions(k401, %{"return" => "−1.5"})))
    assert Findependence.Retirement.settings(household(path), "ana").return_bp == -150
  end

  test "REQ-152/153: compared with the member's own target; what changes the result", %{
    ana: ana,
    k401: k401
  } do
    page =
      follow(
        post(ana, "/act/retirement", assumptions(k401, %{"target" => "3,000", "ss" => "2,000"}))
      )

    assert page =~
             "Paying the difference between your target income and Social Security, $1,000.00 a month, from these accounts would last 1 year and 1 month, to about age 68."

    assert page =~ "<h2>What changes the result</h2>"
    assert page =~ "Nothing here is saved."

    for label <- [
          "As you entered",
          "Return 2 points lower",
          "Return 2 points higher",
          "Retiring 2 years earlier",
          "Retiring 2 years later"
        ],
        do: assert(page =~ "<b>#{label}</b>")

    # retiring two years earlier is this year: the balance is today's 10,000.00
    assert page =~
             ~s(<b>Retiring 2 years earlier</b></td><td role=cell class=num data-label="Return" data-short="Return">12%</td><td role=cell class=num data-label="Retiring at" data-short="Retiring at">65</td><td role=cell class=num data-label="At retirement" data-short="At retirement">about $10,000</td>)

    covered =
      follow(
        post(ana, "/act/retirement", assumptions(k401, %{"target" => "2,000", "ss" => "2,500"}))
      )

    assert covered =~ "The Social Security estimate you entered is at least your target income"
  end

  test "REQ-149/150: an IRA can be added; 15% is the highest return; a zero contribution clears it",
       %{
         path: path,
         ana: ana,
         k401: k401
       } do
    ira = new_id(post(ana, "/act/add_account", %{"label" => "My IRA", "type" => "ira"}))
    assert household(path).items[ira].attrs.account_type == :ira
    assert request(:get, "/items/#{ira}", %{}, ana).resp_body =~ "IRA"

    assert post(ana, "/act/retirement", assumptions(k401, %{"return" => "15.01"})).status == 422
    over = post(ana, "/act/retirement", assumptions(k401, %{"return" => "16"}))
    # refused at the field, not by a general message after the fact
    assert over.status == 422
    assert over.resp_body =~ ~s(<span class="field-error" id="return-error" role="alert">)
    follow(post(ana, "/act/retirement", assumptions(k401, %{"return" => "15"})))
    assert Findependence.Retirement.settings(household(path), "ana").return_bp == 1500

    follow(post(ana, "/act/retirement", assumptions(k401, %{("contribution_" <> k401) => "0"})))
    assert Findependence.Retirement.settings(household(path), "ana").contributions == %{}
  end

  test "REQ-153: each alternative is labelled with the assumption it changes", %{
    ana: ana,
    k401: k401
  } do
    page = follow(post(ana, "/act/retirement", assumptions(k401)))

    for {label, ret, age} <- [
          {"As you entered", "12%", 67},
          {"Return 2 points lower", "10%", 67},
          {"Return 2 points higher", "14%", 67},
          {"Retiring 2 years earlier", "12%", 65},
          {"Retiring 2 years later", "12%", 69}
        ],
        do:
          assert(
            page =~
              ~s(<b>#{label}</b></td><td role=cell class=num data-label="Return" data-short="Return">#{ret}</td><td role=cell class=num data-label="Retiring at" data-short="Retiring at">#{age}</td>)
          )
  end

  test "REQ-154: no suggestions and no judgment words on the retirement pages", %{
    ana: ana,
    k401: k401
  } do
    empty = request(:get, "/retirement", %{}, ana).resp_body

    full =
      follow(
        post(ana, "/act/retirement", assumptions(k401, %{"target" => "3,000", "ss" => "2,000"}))
      )

    for page <- [empty, full] do
      text = visible_text(page)
      assert FindependenceApp.Web.Glossary.judgments(text) == []
      refute text =~ ~r/\b(you should|we recommend|recommended|consider|invest in|enough)\b/i
      assert FindependenceApp.Web.Glossary.violations(text) == []
    end
  end
end
