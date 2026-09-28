# v0.5 pages: Alex moves out, saves their record from the demo family, and brings it into a new
# household of their own, for the UX contract's release gates (ROADMAP-ALPHA §3).
# Usage, from app/: mix run ../project/assurance/accessibility/capture_v05.exs <existing dir>
import Plug.Test
alias FindependenceApp.{Session, Sessions, Store, Vault, Web}

out = hd(System.argv())
Application.put_env(:findependence_app, :today, ~D[2026-09-27])
demo = Path.join(out, "demo.vault")
:ok = Mix.Tasks.Findependence.Demo.build(demo, iterations: 1_000, unsafe_test: true, today: ~D[2026-09-27])
pw = Map.new(Mix.Tasks.Findependence.Demo.members())
{:ok, s} = Session.open(Vault.read!(demo), "Alex", pw["Alex"])
saved = FindependenceApp.Web.Html.export_json(Findependence.Exit.export(s.household, "Alex"))
file = Path.join(out, "alex-export.json")
File.write!(file, saved)

path = Path.join(out, "alex.vault")
Vault.create([{"Alex", pw["Alex"]}], iterations: 1_000, unsafe_test: true) |> Vault.write!(path)
{:ok, _} = Store.start_link(path: path)
{:ok, _} = Sessions.start_link([])

req = fn method, p, params, prev ->
  conn = %{conn(method, p, params) | host: "127.0.0.1", port: 4848}
  conn = if prev, do: recycle_cookies(conn, prev), else: conn
  Web.call(conn, Web.init(port: 4848))
end

tok = fn c -> Regex.run(~r/name=_csrf_token value="([^"]+)"/, c.resp_body) |> List.last() end
# the page's one-time form token, sent with the form as a browser does (REQ-165; WI-052 refuses a form without one)
form_id = fn c -> Regex.run(~r/name=_form value="([^"]+)"/, c.resp_body) |> List.last() end
post = fn prev, p, params -> page = req.(:get, "/", %{}, prev); req.(:post, p, Map.merge(params, %{"_csrf_token" => tok.(page), "_form" => form_id.(page)}), page) end
save = fn name, conn -> File.write!(Path.join(out, name <> ".html"), conn.resp_body) end
upload = fn prev, f -> post.(prev, "/act/bring-in", %{"file" => %Plug.Upload{path: f, filename: "findependence-export.json", content_type: "application/json"}}) end

alex = post.(req.(:get, "/", %{}, nil), "/login", %{"member" => "Alex", "passphrase" => pw["Alex"]})
save.("v5-home-new", req.(:get, "/", %{}, alex))
save.("v5-bring-in", req.(:get, "/bring-in", %{}, alex))

# a copy changed by hand: an amount with cents after the point, and a field the app never writes
bad = Path.join(out, "alex-changed.json")
data = :json.decode(saved)
data = put_in(data, ["items", Access.at(0), "attrs", "amount"], 12.5) |> Map.put("notes", "mine")
File.write!(bad, IO.iodata_to_binary(:json.encode(data)))
save.("v5-refused", upload.(alex, bad))

save.("v5-preview", upload.(alex, file))
done = post.(alex, "/act/bring-in/confirm", %{})
# the next page shows the outcome once; later pages carry the cookies on from it
home = req.(:get, "/", %{}, done)
save.("v5-home-after", home)
save.("v5-already", upload.(home, file))
{:ok, s} = Session.open(Vault.read!(path), "Alex", pw["Alex"])
item = s.household.items |> Enum.find(fn {_, i} -> i.attrs[:note] end) |> elem(0)
save.("v5-item-brought", req.(:get, "/items/" <> item, %{}, home))
IO.puts("captured")
