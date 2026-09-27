# v0.6 pages (UX-002 fixes, CP-014 A) with the demo family, for the UX contract's release gates (ROADMAP-ALPHA §3).
# Usage, from app/: mix run ../project/assurance/accessibility/capture_v06.exs <existing dir>
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
save.("v6-home-dad", req.(:get, "/", %{}, dad))
save.("v6-pay-dad", req.(:get, "/items/dad_pay", %{}, dad))
save.("v6-tuition-dad", req.(:get, "/items/alex_tuition", %{}, dad))
save.("v6-visa-dad", req.(:get, "/items/dad_visa", %{}, dad))
save.("v6-plan-dad", req.(:get, "/plans/job_stops", %{}, dad))
save.("v6-retirement-dad", req.(:get, "/retirement", %{}, dad))
save.("v6-next-60-dad", req.(:get, "/next-60-days", %{}, dad))
IO.puts("captured")
