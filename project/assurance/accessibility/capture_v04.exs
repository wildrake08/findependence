# v0.4 pages with the demo family, for the UX contract's release gates (ROADMAP-ALPHA §3).
# Usage, from app/: mix run ../project/assurance/accessibility/capture_v04.exs <existing dir>
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
save.("v4-home-dad", req.(:get, "/", %{}, dad))
save.("v4-retirement-dad", req.(:get, "/retirement", %{}, dad))
save.("v4-401k-dad", req.(:get, "/items/dad_401k", %{}, dad))
save.("v4-new-balance", req.(:get, "/balances/new", %{}, dad))
save.("v4-ahead-dad", req.(:get, "/ahead", %{}, dad))

save.(
  "v4-retirement-error",
  post.(dad, "/act/retirement", %{
    "birth_year" => "1976",
    "retire_age" => "sixty-seven",
    "return" => "20",
    "contribution_dad_401k" => "400",
    "contribution_mom_ira" => "",
    "ss" => "2,300",
    "target" => "5,500"
  })
)

post.(dad, "/logout", %{})
mom = login.("Mom")
save.("v4-retirement-mom", req.(:get, "/retirement", %{}, mom))
save.("v4-ira-mom", req.(:get, "/items/mom_ira", %{}, mom))
IO.puts("captured")
