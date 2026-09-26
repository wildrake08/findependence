defmodule FindependenceApp.MoneyTest do
  use ExUnit.Case, async: true
  alias FindependenceApp.Money

  test "parses money as cents, with the chosen direction" do
    assert Money.parse("62.40", "out") == {:ok, -6240}
    assert Money.parse("62.4", "out") == {:ok, -6240}
    assert Money.parse("1,200", "in") == {:ok, 120_000}
    assert Money.parse("$3,150", "in") == {:ok, 315_000}
    assert Money.parse(" 12 ", "out") == {:ok, -1200}
    assert Money.parse("0.05", "in") == {:ok, 5}
    assert Money.parse("", "out") == {:ok, nil}
  end

  test "rejects anything unclear, with a message, instead of guessing (the old code turned these into 1, 12, or 0)" do
    for bad <- ["1,20", "12.505", "12.5.0", "abc", "1 200", "12,50", "$", "1e3", "٣"] do
      assert {:error, msg} = Money.parse(bad, "out"), "#{inspect(bad)} should be rejected"
      assert msg =~ "62.40"
    end

    assert {:error, msg} = Money.parse("-50", "out")
    assert msg =~ "without a + or − sign"
    assert {:error, _} = Money.parse("50", "sideways")
  end

  test "formats cents as money" do
    assert Money.format(-6240) == "−$62.40"
    assert Money.format(320_000) == "+$3,200.00"
    assert Money.format(-123_456_789) == "−$1,234,567.89"
    assert Money.format(0) == "$0.00"
    assert Money.format(nil) == ""
  end

  test "legacy whole-unit amounts are normalized to cents once" do
    assert Money.normalize(%{note: "Rent", amount: -1450}) == %{
             note: "Rent",
             amount: -145_000,
             unit: :cents
           }

    new = %{note: "Tea", amount: -350, unit: :cents}
    assert Money.normalize(new) == new
    assert Money.normalize(%{kind: :value, label: "Home"}) == %{kind: :value, label: "Home"}
  end
end

defmodule FindependenceApp.MoneyWebTest do
  @moduledoc "UX-001 R2 at the interface: unclear amounts are rejected with the input kept; old whole-unit amounts still read correctly."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}
  alias Findependence.Household

  setup do
    path = Path.join(System.tmp_dir!(), "fv-money-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
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

  test "62.40 out is stored exactly and shown as money", %{path: path} do
    ana =
      post_form(request(:get, "/"), "/login", %{
        "member" => "ana",
        "passphrase" => "ana passphrase 1"
      })

    assert post_form(ana, "/act/add_item", %{
             "note" => "Groceries",
             "amount" => "62.40",
             "direction" => "out"
           }).status == 303

    {:ok, s} = Session.open(Vault.read!(path), "ana", "ana passphrase 1")
    assert [%{attrs: %{amount: -6240, unit: :cents}}] = Map.values(s.household.items)
    assert request(:get, "/", %{}, ana).resp_body =~ "−$62.40"
  end

  test "an unclear amount saves nothing, shows why at the field, and keeps what was typed", %{
    path: path
  } do
    ana =
      post_form(request(:get, "/"), "/login", %{
        "member" => "ana",
        "passphrase" => "ana passphrase 1"
      })

    resp =
      post_form(ana, "/act/add_item", %{"note" => "Rent", "amount" => "1,20", "direction" => "in"})

    assert resp.status == 422
    assert resp.resp_body =~ ~s(id="amount-error")
    assert resp.resp_body =~ "Enter an amount like 62.40"
    assert resp.resp_body =~ ~s(value="Rent")
    assert resp.resp_body =~ ~s(value="1,20")
    assert resp.resp_body =~ ~s(value=in checked)
    assert Vault.read!(path).items == %{}
  end

  test "an item saved in the old whole-unit format reads as cents" do
    v = Vault.create([{"ana", "pw"}], iterations: 1_000, unsafe_test: true)
    {:ok, s} = Session.open(v, "ana", "pw")
    {:ok, h} = Household.add_item(s.household, "ana", "old", %{note: "Rent", amount: -1450})
    v = Session.save(%{s | household: h}).vault
    {:ok, s} = Session.open(v, "ana", "pw")
    assert %{amount: -145_000, unit: :cents} = s.household.items["old"].attrs
  end
end
