defmodule FindependenceApp.ReleaseNoticeTest do
  @moduledoc "REV-034/REV-035: the alpha's rule is where testers see it."
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-alpha-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    :ok
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  test "the unlock page states the rule above the form, and every page's footer repeats it" do
    page = request(:get, "/")
    unlock = page.resp_body

    assert unlock =~
             "Alpha: use made-up data only. Don&#39;t enter real financial or personal information, or a passphrase you use anywhere else."

    assert :binary.match(unlock, "Alpha: use made-up data only.") <
             :binary.match(unlock, "<form method=post action=\"/login\">")

    token = Regex.run(~r/name=_csrf_token value="([^"]+)"/, unlock) |> List.last()

    ana =
      request(
        :post,
        "/login",
        %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => token},
        page
      )

    for path <- ["/", "/leave", "/export"] do
      assert request(:get, path, %{}, ana).resp_body =~
               "<footer class=hint><b>Alpha: use made-up data only.</b>",
             path
    end
  end
end
