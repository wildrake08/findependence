defmodule FindependenceApp.DEF035Test do
  @moduledoc "DEF-035 (WI-049): stale forms on one shared browser are refused with a page that says so."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-def035-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}, {"ben", "ben passphrase 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  # one browser: every request carries the cookies the previous response set
  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp tokens(page) do
    %{
      "_csrf_token" =>
        Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last(),
      "_form" => Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()
    }
  end

  defp unlock(prev, member, pass) do
    page = request(:get, "/", %{}, prev)

    request(
      :post,
      "/login",
      Map.merge(tokens(page), %{"member" => member, "passphrase" => pass}),
      page
    )
  end

  defp labels(path) do
    {:ok, s} = Session.open(Vault.read!(path), "ana", "ana passphrase 1")
    s.household.items |> Map.values() |> Enum.map(& &1.attrs[:label])
  end

  test "Ana's old tab, after Ana locks and Ben unlocks in the same browser, says nothing was saved",
       %{path: path} do
    ana = unlock(nil, "ana", "ana passphrase 1")
    tab = request(:get, "/", %{}, ana)
    locked = request(:post, "/logout", tokens(tab), tab)
    ben = unlock(locked, "ben", "ben passphrase 2")

    stale =
      request(:post, "/act/add_value", Map.put(tokens(tab), "label", "From Ana's old tab"), ben)

    assert stale.status == 403
    assert stale.resp_body =~ "<h2>That wasn't saved</h2>"
    assert stale.resp_body =~ "This page was out of date, so nothing was saved."
    assert stale.resp_body =~ ~s(<a href="/">Go to the home page</a>)
    # it doesn't say why (WI-032): nothing about who else unlocked
    refute stale.resp_body =~ "someone"
    refute "From Ana's old tab" in labels(path)
    # Ben's session is untouched
    assert request(:get, "/", %{}, stale).resp_body =~ "<span class=who>ben</span>"
  end

  test "Ana's old tab after her own Lock, and a form from before a restart, are refused the same way",
       %{path: path} do
    ana = unlock(nil, "ana", "ana passphrase 1")
    tab = request(:get, "/", %{}, ana)
    locked = request(:post, "/logout", tokens(tab), tab)

    after_lock =
      request(:post, "/act/add_value", Map.put(tokens(tab), "label", "After Lock"), locked)

    assert after_lock.status == 403
    assert after_lock.resp_body =~ "This page was out of date, so nothing was saved."

    # a restart invalidates the cookie: the form arrives with no session at all
    restarted = request(:post, "/act/add_value", Map.put(tokens(tab), "label", "After restart"))
    assert restarted.status == 403
    assert restarted.resp_body =~ "This page was out of date, so nothing was saved."

    assert labels(path) |> Enum.filter(&(&1 in ["After Lock", "After restart"])) == []
  end
end
