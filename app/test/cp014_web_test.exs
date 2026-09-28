defmodule FindependenceApp.CP014WebTest do
  @moduledoc "CP-014 A at the interface (REQ-160..162), with today fixed at Sunday, September 27, 2026."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  setup do
    Application.put_env(:findependence_app, :today, ~D[2026-09-27])
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-cp014-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana pass 1"}, {"ben", "ben pass 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)

    # ben's paycheck, shared with ana; ana's rent, checking account, and a debt
    ben = login("ben", "ben pass 2")

    post(ben, "/act/add_item", %{
      "note" => "Ben's paycheck",
      "amount" => "1,980",
      "direction" => "in",
      "frequency" => "monthly",
      "on" => "2026-09-29"
    })

    pay = id_of(path, "Ben's paycheck", "ben", "ben pass 2")
    post(ben, "/act/grant", %{"item" => pay, "member" => "ana"})

    ana = login("ana", "ana pass 1")

    post(ana, "/act/add_item", %{
      "note" => "Rent",
      "amount" => "2,240",
      "direction" => "out",
      "frequency" => "monthly",
      "on" => "2026-10-01"
    })

    rent = id_of(path, "Rent", "ana", "ana pass 1")

    chk =
      new_id(post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"}))

    post(ana, "/act/add_reading", %{"item" => chk, "balance" => "850", "on" => "2026-09-26"})
    visa = new_id(post(ana, "/act/add_debt", %{"label" => "Visa", "type" => "card"}))
    %{path: path, ana: ana, pay: pay, rent: rent, chk: chk, visa: visa}
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

  defp id_of(path, note, m, p),
    do:
      Enum.find_value(household(path, m, p).items, fn {id, i} -> i.attrs[:note] == note && id end)

  defp household(path, m \\ "ana", p \\ "ana pass 1") do
    {:ok, s} = Session.open(Vault.read!(path), m, p)
    s.household
  end

  test "REQ-160: an item's page asks which account it goes through, worded for owned and shared items",
       %{ana: ana, pay: pay, rent: rent, chk: chk} do
    own = request(:get, "/items/#{rent}", %{}, ana).resp_body
    assert own =~ "<h2>Which account does it go through?</h2>"

    assert own =~
             "Only you see this. Until you choose, an item you own counts toward all your accounts."

    assert own =~
             ~s(<option value="" selected>Not said</option><option value="#{chk}">Checking</option>)

    # a debt isn't offered
    refute own =~ ">Visa</option>"

    shared = request(:get, "/items/#{pay}", %{}, ana).resp_body

    assert shared =~
             "Shared with you, it counts in your Coming up and the next 12 months only once you choose its account."
  end

  test "REQ-160/161: choosing the account counts a shared paycheck in Coming up; clearing it stops",
       %{
         path: path,
         ana: ana,
         pay: pay,
         chk: chk
       } do
    home = request(:get, "/", %{}, ana).resp_body
    refute home =~ "Ben&#39;s paycheck</a>"

    resp =
      post(ana, "/act/attach", %{"item" => pay, "account" => chk, "return" => "/items/#{pay}"})

    page = follow(resp)

    assert page =~
             "“Ben&#39;s paycheck” now goes through “Checking” in your Coming up and the next 12 months."

    assert page =~ ~s(<option value="#{chk}" selected>Checking</option>)
    assert Findependence.Attach.attached(household(path), "ana") == %{pay => chk}
    # ben knows nothing of it
    assert Findependence.Attach.attached(household(path, "ben", "ben pass 2"), "ana") == %{}

    home = request(:get, "/", %{}, resp).resp_body
    assert home =~ "Ben&#39;s paycheck</a>"
    # 850 + 1,980 on September 29
    assert home =~ "$2,830.00"

    cleared =
      post(ana, "/act/attach", %{"item" => pay, "account" => "", "return" => "/items/#{pay}"})

    assert follow(cleared) =~
             "“Ben&#39;s paycheck” no longer goes through a particular account for you."

    refute request(:get, "/", %{}, cleared).resp_body =~ "Ben&#39;s paycheck</a>"
  end

  test "REQ-160: a debt can't be chosen, and the reason is given", %{
    ana: ana,
    rent: rent,
    visa: visa
  } do
    resp =
      post(ana, "/act/attach", %{"item" => rent, "account" => visa, "return" => "/items/#{rent}"})

    assert resp.status == 422

    assert resp.resp_body =~
             "Choose a checking, savings, or other account; not a debt or a retirement account."
  end

  test "CP-015: an owner is told how to record a new amount today, and what is lost", %{
    ana: ana,
    pay: pay,
    rent: rent
  } do
    assert request(:get, "/items/#{rent}", %{}, ana).resp_body =~
             "Amounts can't be changed yet. For a new amount, add a new item with it and remove this one; its links and history don't carry over."

    refute request(:get, "/items/#{pay}", %{}, ana).resp_body =~ "Amounts can"
  end

  test "REQ-164: the saved file carries the account an item goes through, and the preview counts it",
       %{
         ana: ana,
         rent: rent,
         chk: chk,
         pay: pay
       } do
    post(ana, "/act/attach", %{"item" => rent, "account" => chk, "return" => "/items/#{rent}"})
    # ben's paycheck isn't ana's, so its attachment stays out of her file
    post(ana, "/act/attach", %{"item" => pay, "account" => chk, "return" => "/items/#{pay}"})
    file = request(:get, "/export.json", %{}, ana).resp_body
    data = :json.decode(file)
    assert data["version"] == 3
    assert data["attached"] == [%{"item" => rent, "account" => chk}]

    upload = Path.join(System.tmp_dir!(), "fv-cp014-#{System.unique_integer([:positive])}.json")
    File.write!(upload, file)
    on_exit(fn -> File.rm(upload) end)

    preview =
      post(ana, "/act/bring-in", %{
        "file" => %Plug.Upload{path: upload, filename: "x.json", content_type: "application/json"}
      }).resp_body

    assert preview =~ "<li>1 choice of the account an item goes through</li>"
  end
end
