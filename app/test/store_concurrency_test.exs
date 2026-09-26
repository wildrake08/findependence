defmodule FindependenceApp.StoreConcurrencyTest do
  @moduledoc "Security self-review F-16 (WI-026): two copies of the app on one file never silently overwrite each other."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}
  alias Findependence.{Alignment, Household}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-two-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    a = start_supervised!({Store, path: path, name: :store_a}, id: :a)
    b = start_supervised!({Store, path: path, name: :store_b}, id: :b)
    on_exit(fn -> File.rm(path) end)
    %{path: path, a: a, b: b}
  end

  defp open(m, server) do
    {:ok, s} = Store.open(m, "pw-" <> m, server)
    s
  end

  defp notes(path) do
    {:ok, s} = FindependenceApp.Session.open(Vault.read!(path), "ana", "pw-ana")
    s.household.items |> Map.values() |> Enum.map(& &1.attrs[:note]) |> Enum.sort()
  end

  test "a change through the second copy after the first wrote is refused, nothing is lost, and a retry keeps both",
       %{path: path, a: a, b: b} do
    ana_b = open("ana", b)
    ana_a = open("ana", a)

    assert {:ok, _} =
             Store.apply(ana_a, &Household.add_item(&1, "ana", "rent", %{note: "Rent"}), a)

    assert notes(path) == ["Rent"]

    add_car = &Household.add_item(&1, "ana", "car", %{note: "Car"})
    assert {:error, :file_changed, refreshed} = Store.apply(ana_b, add_car, b)
    # nothing was overwritten, and the refused session already shows the other copy's change
    assert notes(path) == ["Rent"]
    assert Map.has_key?(refreshed.household.items, "rent")

    assert {:ok, _} = Store.apply(refreshed, add_car, b)
    assert notes(path) == ["Car", "Rent"]

    # and the first copy, in turn, sees the second's change instead of overwriting it
    assert {:error, :file_changed, again} =
             Store.apply(ana_a, &Alignment.add_value(&1, "ana", "home", "Home"), a)

    assert {:ok, _} = Store.apply(again, &Alignment.add_value(&1, "ana", "home", "Home"), a)
    assert notes(path) == ["Car", "Rent", nil] |> Enum.sort()
  end

  test "reads pick up a change another copy wrote", %{a: a, b: b} do
    before = Store.vault(b)

    {:ok, _} =
      Store.apply(open("ana", a), &Household.add_item(&1, "ana", "rent", %{note: "Rent"}), a)

    refute Store.vault(b) == before
    assert Map.has_key?(Store.refresh(open("ana", b), b).household.items, "rent")
  end

  test "consecutive changes through the same copy never look like another copy's", %{a: a} do
    s = open("ana", a)
    assert {:ok, s} = Store.apply(s, &Household.add_item(&1, "ana", "x", %{note: "X"}), a)
    assert {:ok, s} = Store.apply(s, &Household.add_item(&1, "ana", "y", %{note: "Y"}), a)
    assert {:ok, _} = Store.apply(s, &Household.add_item(&1, "ana", "z", %{note: "Z"}), a)
  end

  test "simultaneous writers never collide on a temporary file", %{path: path} do
    v = Vault.read!(path)

    results =
      1..20
      |> Enum.map(fn _ -> Task.async(fn -> Vault.write!(v, path) end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == :ok))
    assert Vault.read!(path) == v
    assert Path.wildcard(path <> ".tmp*") == []
  end

  test "a failed core operation doesn't count as a change", %{a: a} do
    s = open("ana", a)

    assert {:error, :not_found, _} =
             Store.apply(s, &Household.revoke_grant(&1, "ana", "nope", "ben"), a)

    assert {:ok, _} = Store.apply(s, &Household.add_item(&1, "ana", "x", %{note: "X"}), a)
  end

  test "the file stays owner-only and no temporary files are left behind", %{path: path, a: a} do
    {:ok, _} = Store.apply(open("ana", a), &Household.add_item(&1, "ana", "x", %{note: "X"}), a)
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert Path.wildcard(path <> ".tmp*") == []
  end
end

defmodule FindependenceApp.StoreConcurrencyWebTest do
  @moduledoc "F-16 at the interface: the member is told plainly, and sees the latest version."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}
  alias Findependence.Household

  setup do
    path = Path.join(System.tmp_dir!(), "fv-two-web-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!({Store, path: path, name: :other_copy}, id: :other)
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp token(conn),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, conn.resp_body) |> List.last()

  test "after another copy writes, the next page shows its change" do
    page = request(:get, "/")

    ana =
      request(
        :post,
        "/login",
        %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => token(page)},
        page
      )

    {:ok, s} = Store.open("ana", "ana passphrase 1", :other_copy)

    {:ok, _} =
      Store.apply(
        s,
        &Household.add_item(&1, "ana", "rent", %{note: "Rent from the other copy"}),
        :other_copy
      )

    assert request(:get, "/", %{}, ana).resp_body =~ "Rent from the other copy"
  end

  test "a refused change is explained plainly" do
    text = FindependenceApp.Web.Html.error_text(:file_changed)
    assert text =~ "changed by another copy of Findependence"
    assert text =~ "Nothing was saved, so nothing was lost."
  end
end
