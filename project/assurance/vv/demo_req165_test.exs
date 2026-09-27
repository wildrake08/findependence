# VV-001 demonstration for REQ-165 (not part of the suite). Copy into app/test/ and run:
#   mix test test/demo_req165_test.exs
# Setup and helpers are copied from app/test/ux004_test.exs at 9e84fa8.
defmodule FindependenceApp.VVReq165Demo do
  @moduledoc "UX-004's corrections (P1-P4, H2, H3) against their acceptance criteria."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}
  alias FindependenceApp.Web.Html
  alias Mix.Tasks.Findependence.Demo

  @today ~D[2026-09-27]

  setup do
    Application.put_env(:findependence_app, :today, @today)
    on_exit(fn -> Application.delete_env(:findependence_app, :today) end)
    path = Path.join(System.tmp_dir!(), "fv-ux004-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}, {"ben", "ben passphrase 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    first = request(:get, "/")

    ana =
      request(
        :post,
        "/login",
        %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => csrf(first)},
        first
      )

    %{path: path, ana: ana}
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp csrf(page),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last()

  defp form_token(page),
    do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp loc(resp), do: resp |> Plug.Conn.get_resp_header("location") |> List.first()
  defp follow(resp), do: request(:get, loc(resp), %{}, resp).resp_body

  # the same form, sent twice from one page
  defp twice(prev, page_path, action, params) do
    page = request(:get, page_path, %{}, prev)
    params = Map.merge(params, %{"_csrf_token" => csrf(page), "_form" => form_token(page)})
    first = request(:post, action, params, page)
    second = request(:post, action, params, first)
    {first, second}
  end

  defp household(path) do
    {:ok, s} = Session.open(Vault.read!(path), "ana", "ana passphrase 1")
    s.household
  end

  defp demo do
    path =
      Path.join(System.tmp_dir!(), "fv-ux004-demo-#{System.unique_integer([:positive])}.vault")

    :ok = Demo.build(path, iterations: 1_000, unsafe_test: true, today: @today)
    on_exit(fn -> File.rm(path) end)

    Map.new(Demo.members(), fn {m, p} ->
      {:ok, s} = Session.open(Vault.read!(path), m, p)
      {m, s.household}
    end)
  end


  test "V&V demo: resend after 64 later forms; and a form without its one-time token", %{path: path, ana: ana} do
    rent = %{"note" => "Rent", "amount" => "1,450", "direction" => "out", "frequency" => "monthly"}
    page = request(:get, "/", %{}, ana)
    params = Map.merge(rent, %{"_csrf_token" => csrf(page), "_form" => form_token(page)})
    first = request(:post, "/act/add_item", params, page)

    last =
      Enum.reduce(1..64, first, fn i, prev ->
        p = request(:get, "/", %{}, prev)
        request(:post, "/act/add_value", %{"label" => "V#{i}", "_csrf_token" => csrf(p), "_form" => form_token(p)}, p)
      end)

    again = request(:post, "/act/add_item", params, last)
    rents = household(path).items |> Map.values() |> Enum.count(&(&1.attrs[:note] == "Rent"))
    IO.puts("VV-DEMO resend-after-64: status #{again.status}, Rent items now #{rents}")

    p2 = request(:get, "/", %{}, again)
    gym = %{"note" => "Gym", "amount" => "45", "direction" => "out", "frequency" => "monthly", "_csrf_token" => csrf(p2)}
    a = request(:post, "/act/add_item", gym, p2)
    b = request(:post, "/act/add_item", gym, a)
    gyms = household(path).items |> Map.values() |> Enum.count(&(&1.attrs[:note] == "Gym"))
    IO.puts("VV-DEMO without _form: statuses #{a.status}/#{b.status}, Gym items #{gyms}")
  end
end
