defmodule FindependenceApp.VVF05ATest do
  @moduledoc """
  WI-057 (VV-001 F-05, F-08), batch A: interface-level tests for acceptance criteria of REQ-106,
  REQ-111, REQ-114, and REQ-167 that no earlier test asserted. The criteria are in
  project/assurance/vv/acceptance-a.yaml.
  """
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}
  alias Findependence.{Alignment, Balances, Exit, Household, Plans, View}

  @pass %{"ana" => "ana pass 1", "ben" => "ben pass 2", "cy" => "cy pass 3"}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-vvf05a-#{System.unique_integer([:positive])}.vault")

    @pass
    |> Enum.to_list()
    |> Vault.create(iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    :ok
  end

  # Helpers as in http_actions_test.exs.
  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

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

  defp login(m),
    do: post(request(:get, "/"), "/login", %{"member" => m, "passphrase" => @pass[m]})

  # Runs one core operation as `m` through the Store, as the interface does.
  defp act(m, fun) do
    {:ok, s} = Store.open(m, @pass[m])
    assert {:ok, _} = Store.apply(s, fun)
  end

  # The per-request form tokens are the only part of a page that may differ between two visits.
  defp normalize(body) do
    body
    |> String.replace(~r/name=_csrf_token value="[^"]+"/, "name=_csrf_token value=\"\"")
    |> String.replace(~r/name=_form value="[^"]+"/, "name=_form value=\"\"")
  end

  @household_pages [
    "/",
    "/next-60-days",
    "/ahead",
    "/plans",
    "/retirement",
    "/goals",
    "/leave",
    "/export",
    "/export.json",
    "/balances/new"
  ]

  defp pages(session, paths) do
    # a first visit takes any one-time message, so what follows is the page itself
    request(:get, "/", %{}, session)

    Map.new(paths, fn p ->
      resp = request(:get, p, %{}, session)
      {p, {resp.status, normalize(resp.resp_body)}}
    end)
  end

  # Ben's own item and value, so his pages have something on them.
  defp bens_own do
    act(
      "ben",
      &Household.add_item(&1, "ben", "ben-bus", %{
        note: "Bus",
        amount: -2_000,
        unit: :cents,
        frequency: {:every, 1, :month}
      })
    )

    act("ben", &Alignment.add_value(&1, "ben", "ben-v", "Getting around"))
  end

  test "REQ-106 and REQ-167: another member's private entries change none of a member's household pages, and an item page for one reads as missing" do
    bens_own()
    ben = login("ben")
    before = pages(ben, @household_pages)
    # these are Ben's own pages, not the login page
    assert {200, home} = before["/"]
    assert home =~ "Bus" and home =~ "Getting around"
    assert {200, json} = before["/export.json"]
    assert json =~ "ben-bus"
    missing = request(:get, "/items/no-such-item", %{}, ben)

    act(
      "ana",
      &Household.add_item(&1, "ana", "ana-rent", %{
        note: "Rent",
        amount: -215_000,
        unit: :cents,
        frequency: {:every, 1, :month}
      })
    )

    act(
      "ana",
      &Household.add_item(&1, "ana", "ana-pay", %{
        note: "Pay",
        amount: 480_000,
        unit: :cents,
        frequency: {:every, 2, :week},
        on: "2026-10-02"
      })
    )

    act("ana", &Alignment.add_value(&1, "ana", "ana-v", "Security"))
    act("ana", &Alignment.link(&1, "ana", "ana-rent", "ana-v"))
    act("ana", &Balances.add_account(&1, "ana", "ana-chk", "Ana checking", :checking))
    act("ana", &Balances.add_reading(&1, "ana", "ana-chk", %{on: "2026-09-20", balance: 350_000}))
    act("ana", &Balances.add_debt(&1, "ana", "ana-visa", "Ana visa", :card))

    act(
      "ana",
      &Balances.add_reading(&1, "ana", "ana-visa", %{
        on: "2026-09-20",
        balance: 90_000,
        rate_bp: 2199,
        min_payment: 3_000
      })
    )

    act("ana", &Plans.new_plan(&1, "ana", "ana-plan", "Ana's plan"))
    act("ana", &Household.propose_grant(&1, "ana", "ana-pay", "cy"))

    assert pages(ben, @household_pages) == before

    for id <- ["ana-rent", "ana-v", "ana-chk", "ana-visa"] do
      resp = request(:get, "/items/#{id}", %{}, ben)

      assert {resp.status, normalize(resp.resp_body)} ==
               {missing.status, normalize(missing.resp_body)},
             id
    end
  end

  test "REQ-114: after another member revokes or deletes what a member had linked, the member's pages are as before it was shared" do
    bens_own()

    act(
      "ana",
      &Household.add_item(&1, "ana", "ana-rent", %{
        note: "Rent",
        amount: -215_000,
        unit: :cents,
        frequency: {:every, 1, :month}
      })
    )

    act(
      "ana",
      &Household.add_item(&1, "ana", "ana-gym", %{
        note: "Gym",
        amount: -4_000,
        unit: :cents,
        frequency: {:every, 1, :month}
      })
    )

    act("ana", &Alignment.add_value(&1, "ana", "ana-v", "Security"))
    ben = login("ben")

    paths =
      @household_pages ++ ["/items/ben-v", "/items/ben-bus", "/items/ana-rent", "/items/ana-v"]

    before = pages(ben, paths)
    assert {200, bus_page} = before["/items/ben-bus"]
    assert bus_page =~ "Bus" and elem(before["/items/ben-v"], 1) =~ "Getting around"

    # revocation: rent and ana's value are shared with Ben, he links them, and the grants are revoked
    act("ana", &Household.propose_grant(&1, "ana", "ana-rent", "ben"))
    act("ana", &Household.propose_grant(&1, "ana", "ana-v", "ben"))
    act("ben", &Alignment.link(&1, "ben", "ana-rent", "ben-v"))
    act("ben", &Alignment.link(&1, "ben", "ben-bus", "ana-v"))
    refute pages(ben, paths) == before
    act("ana", &Household.revoke_grant(&1, "ana", "ana-rent", "ben"))
    act("ana", &Household.revoke_grant(&1, "ana", "ana-v", "ben"))
    assert pages(ben, paths) == before

    # deletion: the gym is shared with Ben, he links it, and Ana deletes it
    paths = paths ++ ["/items/ana-gym"]
    before = pages(ben, paths)
    act("ana", &Household.propose_grant(&1, "ana", "ana-gym", "ben"))
    act("ben", &Alignment.link(&1, "ben", "ana-gym", "ben-v"))
    refute pages(ben, paths) == before
    act("ana", &Exit.delete(&1, "ana", "ana-gym"))
    assert pages(ben, paths) == before
  end

  test "REQ-111: a new household has no items, so no values, for any member" do
    v = Store.vault()
    assert v.items == %{}

    for m <- Map.keys(@pass) do
      {:ok, s} = Store.open(m, @pass[m])
      assert s.household.items == %{}
      assert View.visible_items(s.household, m) == []
      assert Alignment.distribution(s.household, m).by_value == %{}
    end
  end
end
