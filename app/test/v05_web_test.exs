defmodule FindependenceApp.V05WebTest do
  @moduledoc "v0.5 at the interface (REQ-155..159), with today fixed at Sunday, September 27, 2026."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}
  alias FindependenceApp.Web.Html
  alias Findependence.{Balances, Exit, Household, Plans, Retirement}

  @dir System.tmp_dir!()

  setup do
    Application.put_env(:findependence_app, :today, ~D[2026-09-27])
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(@dir, "fv-v05-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana pass 1"}, {"ben", "ben pass 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path, ana: login("ana", "ana pass 1")}
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

  # sends a form from the page the member is on (here, the preview), as a browser does
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
  defp follow(resp), do: request(:get, loc(resp), %{}, resp).resp_body

  defp household(path, m \\ "ana", p \\ "ana pass 1") do
    {:ok, s} = Session.open(Vault.read!(path), m, p)
    s.household
  end

  # The file someone saved in another household: Dad's own record there, with a joint bill, a
  # value and link, an account with balances, a plan, a mark, a goal, and a shared plan.
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
    {:ok, h} = Plans.mark(h, "dad", "health", "pay")
    {:ok, h} = Plans.new_plan(h, "dad", "p1", "If the job stops")
    {:ok, h} = Plans.add_step(h, "dad", "p1", {:switch_off, ["pay"], "2026-11"})
    {:ok, h} = Plans.set_fund_goal(h, "dad", 3)
    {:ok, h} = Retirement.set(h, "dad", :retire_age, 67)
    {:ok, h, _} = Plans.propose_shared(h, "dad", "p1", "sp1", ["mom"])
    Html.export_json(Exit.export(h, "dad"))
  end

  defp upload(prev, contents, name \\ "findependence-export.json") do
    file = Path.join(@dir, "fv-upload-#{System.unique_integer([:positive])}.json")
    File.write!(file, contents)
    on_exit(fn -> File.rm(file) end)

    post(prev, "/act/bring-in", %{
      "file" => %Plug.Upload{path: file, filename: name, content_type: "application/json"}
    })
  end

  defp text(html),
    do:
      html
      |> String.replace(~r/<style>.*?<\/style>/s, "")
      |> String.replace(~r/<[^>]+>/, " ")
      |> String.replace(~r/\s+/, " ")

  test "home links to bringing a record in, next to saving one", %{ana: ana} do
    home = request(:get, "/", %{}, ana).resp_body
    assert home =~ ~s(<a href="/bring-in">Bring in a file you saved</a> from another household.)
    page = request(:get, "/bring-in", %{}, ana).resp_body
    assert page =~ ~s(<form method=post action="/act/bring-in" enctype="multipart/form-data">)

    assert page =~
             ~s(<input type=file id=file name=file accept=".json,application/json" required>)
  end

  test "REQ-155/DEF-032: the saved file is versioned, even for a member who owns a shared plan" do
    data = :json.decode(saved_file())
    assert data["format"] == "findependence-export" and data["version"] == 3
    assert data["goals"]["fund_months"] == 3 and length(data["plans"]) == 1
    sp = Enum.find(data["items"], &(&1["id"] == "sp1"))
    assert [%{"kind" => "switch_off", "items" => ["pay"]}] = sp["attrs"]["steps"]
    assert Enum.find(data["items"], &(&1["id"] == "pay"))["history"] == ["Created by dad"]
    refute saved_file() =~ ~s("nil")
  end

  test "DEF-032: downloading the file works for a member who owns a shared plan", %{ana: ana} do
    plan =
      post(ana, "/act/new_plan", %{"name" => "Side business"})
      |> loc()
      |> String.split("/")
      |> List.last()

    post(ana, "/act/plan_step", %{
      "plan" => plan,
      "kind" => "add",
      "note" => "Sales",
      "amount" => "500",
      "direction" => "in",
      "frequency" => "monthly",
      "from" => "2026-11"
    })

    post(ana, "/act/share_plan", %{"plan" => plan, "members" => ["ben"]})
    file = request(:get, "/export.json", %{}, ana)
    assert file.status == 200
    data = :json.decode(file.resp_body)
    shared = Enum.find(data["items"], &(&1["attrs"]["kind"] == "plan"))
    assert [%{"kind" => "add", "note" => "Sales", "amount" => 50_000}] = shared["attrs"]["steps"]
  end

  test "REQ-156/158: check, preview, then bring in as the member's alone", %{path: path, ana: ana} do
    resp = upload(ana, saved_file())
    assert resp.status == 200
    page = resp.resp_body
    assert page =~ "What would be brought in"

    assert page =~
             "From <b>findependence-export.json</b>, checked. Nothing is saved until you choose “Bring it in”."

    assert page =~ "<li>3 items: Health plan, Paycheck, Rent</li>"
    assert page =~ "<li>1 value: A safe home</li>"
    assert page =~ "<li>1 account: Checking</li>"
    assert page =~ "<li>2 balances</li>"
    assert page =~ "<li>1 link to a value</li>"
    assert page =~ "<li>1 mark on what depends on a job</li>"
    assert page =~ "<li>1 plan: If the job stops</li>"

    assert page =~ "1 shared plan isn&#39;t brought in" or
             page =~ "1 shared plan isn't brought in"

    # nothing saved yet
    assert Enum.count(household(path).items) == 0

    done = from_page(resp, "/act/bring-in/confirm")
    assert loc(done) == "/"
    home = follow(done)

    assert home =~
             "Brought in 3 items, 1 value and 1 account from your file. Only you own them; nobody else can see them until you share."

    h = household(path)
    assert map_size(h.items) == 5

    assert Enum.all?(h.items, fn {_, i} ->
             i.owners == MapSet.new(["ana"]) and MapSet.size(i.grantees) == 0
           end)

    assert Plans.goals(h, "ana").fund_months == 3
    assert Retirement.settings(h, "ana").retire_age == 67
    assert length(Plans.depends(h, "ana")) == 1

    rent = Enum.find_value(h.items, fn {id, i} -> i.attrs[:note] == "Rent" && id end)
    assert request(:get, "/items/#{rent}", %{}, done).resp_body =~ "Brought in by ana"

    # ben sees none of it
    assert Findependence.View.visible_items(household(path, "ben", "ben pass 2"), "ben") == []

    # the same file again is refused, with the date it was brought in
    again = upload(done, saved_file())
    assert again.status == 422

    assert again.resp_body =~
             ~s(<p class="msg err" role="alert">You brought in this file on Sunday, September 27, so it wasn&#39;t brought in again.</p>)
  end

  test "REQ-158 (DEF-044): leaving the preview drops the file; its form then brings nothing in",
       %{path: path, ana: ana} do
    preview = upload(ana, saved_file())
    assert preview.status == 200

    # the member goes to another page, then comes back (or presses Back) and sends the preview's form
    left = request(:get, "/", %{}, preview)

    sent =
      request(
        :post,
        "/act/bring-in/confirm",
        %{"_csrf_token" => token(preview), "_form" => form_id(preview)},
        left
      )

    assert follow(sent) =~ "Nothing is waiting to be brought in."

    assert map_size(household(path).items) == 0
  end

  test "REQ-158: cancelling, or locking, brings nothing in", %{path: path, ana: ana} do
    preview = upload(ana, saved_file())
    assert preview.status == 200
    cancelled = from_page(preview, "/act/bring-in/cancel")
    assert follow(cancelled) =~ "Nothing was brought in."

    assert follow(post(ana, "/act/bring-in/confirm", %{})) =~
             "Nothing is waiting to be brought in."

    assert map_size(household(path).items) == 0

    assert upload(ana, saved_file()).status == 200
    post(ana, "/logout", %{})
    ana = login("ana", "ana pass 1")

    assert follow(post(ana, "/act/bring-in/confirm", %{})) =~
             "Nothing is waiting to be brought in."

    assert map_size(household(path).items) == 0
  end

  test "REQ-157: a file that fails a check is refused whole, saying what and where", %{
    path: path,
    ana: ana
  } do
    data = :json.decode(saved_file())
    i = Enum.find_index(data["items"], &(&1["id"] == "pay"))
    bad = put_in(data, ["items", Access.at(i), "attrs", "amount"], 1.5)
    resp = upload(ana, IO.iodata_to_binary(:json.encode(bad)))
    assert resp.status == 422
    assert resp.resp_body =~ "<h2>Nothing was brought in</h2>"

    assert resp.resp_body =~
             "<li>Number #{i + 1} in the file, amount: isn&#39;t an amount in whole cents within range.</li>"

    hostile = Map.put(data, "script", "<script>alert(1)</script>")
    body = upload(ana, IO.iodata_to_binary(:json.encode(hostile))).resp_body

    assert body =~ "<li>“script”: isn&#39;t part of an export.</li>"

    refute body =~ "<script>alert"

    assert upload(ana, "not json at all").resp_body =~
             "This isn&#39;t a Findependence export file. Nothing was brought in." or
             upload(ana, "not json at all").resp_body =~
               "This isn't a Findependence export file. Nothing was brought in."

    assert upload(ana, :binary.copy("a", 1_048_577)).resp_body =~ "An export file is at most 1 MB"
    assert post(ana, "/act/bring-in", %{}).resp_body =~ "Choose your saved file first."
    assert map_size(household(path).items) == 0
  end

  test "REQ-157: a body over the limit is refused before it is read", %{ana: ana} do
    boundary = "fvtest"

    body =
      "--#{boundary}\r\ncontent-disposition: form-data; name=\"file\"; filename=\"big.json\"\r\ncontent-type: application/json\r\n\r\n" <>
        :binary.copy("a", 1_200_000) <> "\r\n--#{boundary}--\r\n"

    conn =
      %{conn(:post, "/act/bring-in", body) | host: "127.0.0.1", port: 4848}
      |> recycle_cookies(ana)
      |> Plug.Conn.put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")

    resp = Web.call(conn, Web.init(port: 4848))
    assert resp.status == 413
    assert resp.resp_body =~ "That file is too large"
  end

  test "REQ-157: the upload needs the form's token like every other change", %{ana: ana} do
    file = Path.join(@dir, "fv-upload-#{System.unique_integer([:positive])}.json")
    File.write!(file, saved_file())
    on_exit(fn -> File.rm(file) end)

    resp =
      request(
        :post,
        "/act/bring-in",
        %{"file" => %Plug.Upload{path: file, filename: "x.json"}},
        ana
      )

    # DEF-035: refused with a page that says nothing was saved; nothing is checked or held
    assert resp.status == 403
    assert resp.resp_body =~ "This page was out of date, so nothing was saved."
    refute resp.resp_body =~ "What would be brought in"
  end

  test "MEC-022: only the bring-in route accepts a file; every other form stays urlencoded", %{
    ana: ana
  } do
    boundary = "fvtest"

    body =
      "--#{boundary}\r\ncontent-disposition: form-data; name=\"note\"\r\n\r\nRent\r\n--#{boundary}--\r\n"

    conn =
      %{conn(:post, "/act/add_item", body) | host: "127.0.0.1", port: 4848}
      |> recycle_cookies(ana)
      |> Plug.Conn.put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")

    assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
      Web.call(conn, Web.init(port: 4848))
    end
  end

  test "REQ-158: names from the file are shown as text, never as markup", %{ana: ana} do
    data = :json.decode(saved_file())
    i = Enum.find_index(data["items"], &(&1["id"] == "pay"))
    named = put_in(data, ["items", Access.at(i), "attrs", "note"], "<i>Paycheck</i>")
    page = upload(ana, IO.iodata_to_binary(:json.encode(named))).resp_body
    assert page =~ "&lt;i&gt;Paycheck&lt;/i&gt;"
    refute page =~ "<i>Paycheck</i>"
  end
end
