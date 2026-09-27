# UX-004 states (WI-046): the plan deletion confirmation, the not-found page (locked and unlocked),
# an empty household's home, and a repeated form's message, for the UX contract's release gates.
# Usage, from app/: mix run ../project/assurance/accessibility/capture_v07.exs <existing dir>
import Plug.Test
alias FindependenceApp.{Sessions, Store, Vault, Web}

out = hd(System.argv())
path = Path.join(out, "demo.vault")
File.rm(path)
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
form = fn c -> Regex.run(~r/name=_form value="([^"]+)"/, c.resp_body) |> List.last() end
pw = Map.new(Mix.Tasks.Findependence.Demo.members())
save = fn name, conn -> File.write!(Path.join(out, name <> ".html"), conn.resp_body) end

first = req.(:get, "/", %{}, nil)
save.("v7-unlock", first)
save.("v7-not-found-locked", req.(:get, "/nowhere", %{}, nil))
dad = req.(:post, "/login", %{"member" => "Dad", "passphrase" => pw["Dad"], "_csrf_token" => tok.(first)}, first)
save.("v7-not-found-dad", req.(:get, "/nowhere", %{}, dad))
plan = req.(:get, "/plans/job_stops", %{}, dad)
save.("v7-confirm-delete-plan", req.(:post, "/confirm/delete_plan", %{"plan" => "job_stops", "_csrf_token" => tok.(plan)}, plan))

home = req.(:get, "/", %{}, dad)
p = %{"label" => "Twice", "_csrf_token" => tok.(home), "_form" => form.(home)}
a = req.(:post, "/act/add_value", p, home)
b = req.(:post, "/act/add_value", p, a)
save.("v7-already-saved-dad", req.(:get, "/", %{}, b))

# an empty household, as its first member sees it
empty = Path.join(out, "empty.vault")
File.rm(empty)
Vault.create([{"Ana", "ana passphrase 1"}, {"Ben", "ben passphrase 2"}], iterations: 1_000, unsafe_test: true) |> Vault.write!(empty)
GenServer.stop(Store)
{:ok, _} = Store.start_link(path: empty)
e0 = req.(:get, "/", %{}, nil)
ana = req.(:post, "/login", %{"member" => "Ana", "passphrase" => "ana passphrase 1", "_csrf_token" => tok.(e0)}, e0)
save.("v7-empty-home-ana", req.(:get, "/", %{}, ana))
IO.puts("captured")
