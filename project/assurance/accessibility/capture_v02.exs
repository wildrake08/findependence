# v0.2 pages with the demo family, for the UX contract's release gates (ROADMAP-ALPHA §3).
# Usage, from app/: mix run ../project/assurance/accessibility/capture_v02.exs <existing dir>
import Plug.Test
alias FindependenceApp.{Sessions, Store, Web}

out = hd(System.argv())
path = Path.join(out, "demo.vault")
Application.put_env(:findependence_app, :today, ~D[2026-09-27])
:ok = Mix.Tasks.Findependence.Demo.build(path, iterations: 1_000, unsafe_test: true, today: ~D[2026-09-27])
{:ok, _} = Store.start_link(path: path)
{:ok, _} = Sessions.start_link([])

req = fn method, p, params, prev ->
  conn = %{conn(method, p, params) | host: "127.0.0.1", port: 4848}
  conn = if prev, do: recycle_cookies(conn, prev), else: conn
  Web.call(conn, Web.init(port: 4848))
end

tok = fn c -> Regex.run(~r/name=_csrf_token value="([^"]+)"/, c.resp_body) |> List.last() end
post = fn prev, p, params -> page = req.(:get, "/", %{}, prev); req.(:post, p, Map.put(params, "_csrf_token", tok.(page)), page) end
pw = Map.new(Mix.Tasks.Findependence.Demo.members())
login = fn m -> post.(req.(:get, "/", %{}, nil), "/login", %{"member" => m, "passphrase" => pw[m]}) end
save = fn name, conn -> File.write!(Path.join(out, name <> ".html"), conn.resp_body) end

dad = login.("Dad")
save.("v2-home-dad", req.(:get, "/", %{}, dad))
save.("v2-next-60-dad", req.(:get, "/next-60-days", %{}, dad))
save.("v2-checking-dad", req.(:get, "/items/checking", %{}, dad))
save.("v2-heloc-dad", req.(:get, "/items/heloc_debt", %{}, dad))
save.("v2-visa-dad", req.(:get, "/items/dad_visa", %{}, dad))
save.("v2-mortgage-dad", req.(:get, "/items/mortgage", %{}, dad))
save.("v2-new-balance", req.(:get, "/balances/new", %{}, dad))
save.("v2-reading-error", post.(dad, "/act/add_reading", %{"item" => "dad_visa", "balance" => "6,1OO", "rate" => "24.99", "min_payment" => "190", "on" => "2026-09-27", "return" => "/items/dad_visa"}))
save.("v2-date-error", post.(dad, "/act/add_item", %{"note" => "Water", "amount" => "90", "direction" => "out", "frequency" => "every_2_months", "on" => "2026-02-30"}))
save.("v2-export-dad", req.(:get, "/export", %{}, dad))
post.(dad, "/act/grant", %{"item" => "dad_visa", "member" => "Mom"})
post.(dad, "/logout", %{})
mom = login.("Mom")
save.("v2-home-mom", req.(:get, "/", %{}, mom))
save.("v2-visa-mom-shared", req.(:get, "/items/dad_visa", %{}, mom))
post.(mom, "/logout", %{})
casey = login.("Casey")
save.("v2-home-casey", req.(:get, "/", %{}, casey))
save.("v2-next-60-casey", req.(:get, "/next-60-days", %{}, casey))
IO.puts("captured")
