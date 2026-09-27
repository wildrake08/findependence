# v0.3 pages with the demo family, for the UX contract's release gates (ROADMAP-ALPHA §3).
# Usage, from app/: mix run ../project/assurance/accessibility/capture_v03.exs <existing dir>
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
save.("v3-home-dad", req.(:get, "/", %{}, dad))
save.("v3-ahead-dad", req.(:get, "/ahead", %{}, dad))
save.("v3-plans-dad", req.(:get, "/plans", %{}, dad))
save.("v3-plan-job-dad", req.(:get, "/plans/job_stops", %{}, dad))
save.("v3-plan-error", post.(dad, "/act/plan_step", %{"plan" => "job_stops", "kind" => "switch_off", "from" => "2026-11"}))
save.("v3-health-dad", req.(:get, "/items/dad_health", %{}, dad))
save.("v3-visa-whatif", req.(:get, "/items/dad_visa", %{"extra" => "100", "rate" => "18"}, dad))
save.("v3-goals-dad", req.(:get, "/goals", %{}, dad))
post.(dad, "/logout", %{})
mom = login.("Mom")
save.("v3-home-mom", req.(:get, "/", %{}, mom))
save.("v3-goals-mom", req.(:get, "/goals", %{}, mom))
# REQ-148: Mom sees Dad's plan request before agreeing, then the shared plan once she agrees
[pid] = Regex.run(~r{href="/requests/(\d+)"}, req.(:get, "/", %{}, mom).resp_body, capture: :all_but_first)
save.("v3-plan-request-mom", req.(:get, "/requests/" <> pid, %{}, mom))
post.(mom, "/act/consent", %{"proposal" => pid, "return" => "/plans"})
save.("v3-shared-plan-mom", req.(:get, "/items/shared_side_plan", %{}, mom))
IO.puts("captured")
