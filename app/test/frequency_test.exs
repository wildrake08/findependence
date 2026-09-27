defmodule FindependenceApp.FrequencyTest do
  @moduledoc "REQ-127 and REQ-126 at the interface (WI-025): how often an item happens, and per-month totals."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-freq-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)

    ana =
      post_form(request(:get, "/"), "/login", %{
        "member" => "ana",
        "passphrase" => "ana passphrase 1"
      })

    %{path: path, ana: ana}
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp post_form(prev, path, params) do
    page = request(:get, "/", %{}, prev)
    token = Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last()
    request(:post, path, Map.put(params, "_csrf_token", token), page)
  end

  defp household(path) do
    {:ok, s} = Session.open(Vault.read!(path), "ana", "ana passphrase 1")
    s.household
  end

  defp add(ana, note, amount, direction, frequency),
    do:
      post_form(ana, "/act/add_item", %{
        "note" => note,
        "amount" => amount,
        "direction" => direction,
        "frequency" => frequency
      })

  test "the vault can decode every frequency, whatever order modules load in" do
    for atom <- Findependence.Alignment.frequency_atoms(),
        do: assert(atom in Vault.format_atoms(), "#{atom} missing from the vault's atom list")
  end

  test "the form offers no default: nothing chosen or an unknown choice saves nothing, and says why",
       %{path: path, ana: ana} do
    form = request(:get, "/", %{}, ana).resp_body

    assert form =~
             ~s(<select id=frequency name=frequency required><option value="">Choose…</option>)

    refute form =~ "selected"

    for bad <- [nil, "", "hourly"] do
      params = %{"note" => "Bus pass", "amount" => "32.50", "direction" => "out"}
      params = if bad, do: Map.put(params, "frequency", bad), else: params
      resp = post_form(ana, "/act/add_item", params)
      assert resp.status == 422

      assert resp.resp_body =~
               ~s(<p class="field-error" id="frequency-error" role="alert">Choose how often this happens.</p>)

      assert resp.resp_body =~ ~s(aria-describedby="frequency-error" aria-invalid="true")
      assert resp.resp_body =~ ~s(value="Bus pass")
      assert resp.resp_body =~ ~s(value="32.50")
    end

    assert household(path).items == %{}
  end

  test "a chosen frequency is kept when the amount is what's wrong", %{ana: ana} do
    resp = add(ana, "Bus pass", "32,5O", "out", "weekly")
    assert resp.status == 422
    assert resp.resp_body =~ ~s(id="amount-error")
    assert resp.resp_body =~ ~s(<option value="weekly" selected>Every week</option>)
  end

  test "the frequency is stored and shown wherever the amount is", %{path: path, ana: ana} do
    assert add(ana, "Bus pass", "32.50", "out", "weekly").status == 303
    [item] = Map.values(household(path).items)
    assert item.attrs.frequency == {:every, 1, :week}
    assert item.attrs.amount == -3250

    home = request(:get, "/", %{}, ana).resp_body
    assert home =~ "−$32.50 a week"

    page = request(:get, "/items/#{item.id}", %{}, ana).resp_body
    assert page =~ "−$32.50 a week"
    # 3250 x 52 / 12 = 14083.33
    assert page =~ "About −$140.83 a month in your totals."

    assert request(:get, "/export", %{}, ana).resp_body =~ ", −$32.50 a week"
  end

  test "a monthly or one-off item has no per-month hint; one-off reads as such", %{
    path: path,
    ana: ana
  } do
    add(ana, "Rent", "2,150", "out", "monthly")
    add(ana, "Couch", "649.99", "out", "one_off")
    items = household(path).items |> Map.values() |> Map.new(&{&1.attrs.note, &1.id})
    rent = request(:get, "/items/#{items["Rent"]}", %{}, ana).resp_body
    couch = request(:get, "/items/#{items["Couch"]}", %{}, ana).resp_body
    assert rent =~ "−$2,150.00 a month"
    assert couch =~ "−$649.99, one-off"
    refute rent =~ "in your totals"
    refute couch =~ "in your totals"
  end

  test "totals show per month in and out, and one-offs apart, with nothing evaluative",
       %{path: path, ana: ana} do
    post_form(ana, "/act/add_value", %{"label" => "Home"})
    add(ana, "Rent", "2,150", "out", "monthly")
    add(ana, "Pay", "1,480", "in", "biweekly")
    add(ana, "Couch", "649.99", "out", "one_off")
    add(ana, "Bus pass", "32.50", "out", "weekly")

    items =
      household(path).items
      |> Map.values()
      |> Map.new(&{&1.attrs[:note] || &1.attrs[:label], &1.id})

    for note <- ["Rent", "Couch"],
        do: post_form(ana, "/act/link", %{"item" => items[note], "value" => items["Home"]})

    home = request(:get, "/", %{}, ana).resp_body

    row = fn name ->
      Regex.run(
        ~r/<tr role=row[^>]*><td role=cell data-label="Value">(?:<a[^>]*>)?#{name}.*?<\/tr>/s,
        home
      )
      |> List.first()
    end

    home_row = row.("Home")
    assert home_row =~ ~s(data-label="Money out, per month" data-short="Out/month">−$2,150.00<)
    assert home_row =~ ~s(data-label="One-off out" data-short="One-off out">−$649.99<)
    assert home_row =~ ~s(data-label="Money in, per month" data-short="In/month">$0.00<)
    assert home_row =~ ~s(data-label="Items" data-short="Items">2<)

    rest = row.("Not linked to anything")
    # 148000 x 26 / 12 = 320666.67; -3250 x 52 / 12 = -14083.33
    assert rest =~ ~s(data-label="Money in, per month" data-short="In/month">+$3,206.67<)
    assert rest =~ ~s(data-label="Money out, per month" data-short="Out/month">−$140.83<)

    [table] =
      Regex.run(
        ~r/<table class="stack dist" role=table aria-label="Totals by value">.*?<\/table>/s,
        home
      )

    refute table =~ ~r/\b(score|rank|on track|over budget|too much|good|bad|target)\b/i
  end

  test "CP-012: every preset is offered, stored, shown, converted, and exported", %{
    path: path,
    ana: ana
  } do
    form = request(:get, "/", %{}, ana).resp_body

    assert form =~
             ~s(<option value="every_2_months">Every two months</option><option value="every_3_months">Every three months</option><option value="twice_a_year">Twice a year</option>)

    assert form =~ ~s|<option value="irregular">Irregular (enter the total for a year)</option>|

    cases = [
      {"Water", "120", "every_2_months", {:every, 2, :month}, "−$120.00 every two months",
       "About −$60.00 a month"},
      {"Taxes", "900", "every_3_months", {:every, 3, :month}, "−$900.00 every three months",
       "About −$300.00 a month"},
      {"Insurance", "450", "twice_a_year", {:every, 6, :month}, "−$450.00 twice a year",
       "About −$75.00 a month"},
      {"Repairs", "1,200", "irregular", :irregular, "−$1,200.00, a year, irregular",
       "About −$100.00 a month"}
    ]

    for {note, amount, form_value, stored, shown, hint} <- cases do
      assert add(ana, note, amount, "out", form_value).status == 303
      item = household(path).items |> Map.values() |> Enum.find(&(&1.attrs.note == note))
      assert item.attrs.frequency == stored
      page = request(:get, "/items/#{item.id}", %{}, ana).resp_body
      assert page =~ shown
      assert page =~ hint
    end

    json = request(:get, "/export.json", %{}, ana).resp_body

    assert json =~ ~s("frequency":{"every":2,"unit":"month"}) or
             json =~ ~s("frequency":{"unit":"month","every":2})

    assert json =~ ~s("frequency":"irregular")
  end

  test "an item stored with a legacy frequency still reads and converts the same", %{
    path: path,
    ana: ana
  } do
    # added exactly as REQ-127 code stored it (item contents are write-once, ASM-021)
    {:ok, s} = Store.open("ana", "ana passphrase 1")
    attrs = %{note: "Bus pass", amount: -3250, unit: :cents, frequency: :weekly}
    {:ok, _} = Store.apply(s, &Findependence.Household.add_item(&1, "ana", "legacy1", attrs))

    assert household(path).items["legacy1"].attrs.frequency == :weekly
    page = request(:get, "/items/legacy1", %{}, ana).resp_body
    assert page =~ "−$32.50 a week"
    assert page =~ "About −$140.83 a month in your totals."
  end
end
