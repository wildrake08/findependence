import Plug.Test
alias FindependenceApp.{Sessions, Store, Vault, Web}
out = System.argv() |> hd
path = Path.join(out, "demo.vault")
Vault.create([{"Ana", "ana passphrase 1"}, {"Ben", "ben passphrase 2"}, {"Cy", "cy passphrase 3"}], iterations: 1_000, unsafe_test: true) |> Vault.write!(path)
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
login = fn m, pw -> post.(req.(:get, "/", %{}, nil), "/login", %{"member" => m, "passphrase" => pw}) end
save = fn name, conn -> File.write!(Path.join(out, name <> ".html"), conn.resp_body) end
follow = fn resp -> [loc] = Plug.Conn.get_resp_header(resp, "location"); req.(:get, loc, %{}, resp) end
id_of = fn note -> {:ok, s} = FindependenceApp.Session.open(Vault.read!(path), "Ana", "ana passphrase 1"); Enum.find_value(FindependenceApp.Web.Html.names(s.household, "Ana"), fn {id, n} -> n == note && id end) end

save.("01-login", req.(:get, "/", %{}, nil))
save.("02-login-error", login.("Ana", "wrong"))
save.("02b-locked", req.(:get, "/?locked=idle", %{}, nil))
ana = login.("Ana", "ana passphrase 1")
for {n, a, d} <- [{"Rent", "1,450", "out"}, {"Wages", "3,200", "in"}, {"Groceries", "62.40", "out"}, {"Car loan", "310", "out"}, {"Climbing gym", "45.99", "out"}], do: post.(ana, "/act/add_item", %{"note" => n, "amount" => a, "direction" => d, "frequency" => "monthly"})
for l <- ["A safe home", "Time outdoors", "Not owing anyone"], do: post.(ana, "/act/add_value", %{"label" => l})
post.(ana, "/act/link", %{"item" => id_of.("Rent"), "value" => id_of.("A safe home")})
post.(ana, "/act/link", %{"item" => id_of.("Climbing gym"), "value" => id_of.("Time outdoors")})
post.(ana, "/act/link", %{"item" => id_of.("Car loan"), "value" => id_of.("Not owing anyone")})
post.(ana, "/act/owners", %{"item" => id_of.("Rent"), "owners" => ["Ana", "Ben"]})
post.(ana, "/act/add_value", %{"label" => "Our family holiday"})
post.(ana, "/act/owners", %{"item" => id_of.("Our family holiday"), "owners" => ["Ana", "Ben"]})
g = post.(ana, "/act/grant", %{"item" => id_of.("Groceries"), "member" => "Ben", "return" => "/items/" <> id_of.("Groceries")})
save.("03-home-ana", req.(:get, "/", %{}, ana))
if System.get_env("ITEM_PAGES") do
  save.("08-item-flash", follow.(g))
  save.("09-item-rent", req.(:get, "/items/" <> id_of.("Rent"), %{}, ana))
  save.("10-item-value", req.(:get, "/items/" <> id_of.("A safe home"), %{}, ana))
end
save.("04-field-error", post.(ana, "/act/add_item", %{"note" => "Phone", "amount" => "55,5", "direction" => "out", "frequency" => "monthly"}))
save.("05-confirm-delete", post.(ana, "/confirm/delete", %{"item" => id_of.("Climbing gym")}))
save.("05b-confirm-relinquish", post.(ana, "/confirm/relinquish", %{"item" => id_of.("Rent")}))
save.("06-export", req.(:get, "/export", %{}, ana))
save.("14-not-available", req.(:get, "/items/nope", %{}, ana))
save.("12-leave", req.(:get, "/leave", %{}, ana))
r = post.(ana, "/act/let_go", %{"item" => id_of.("Wages"), "to" => "", "return" => "/leave"})
save.("13-leave-error", r)
post.(ana, "/logout", %{})
ben = login.("Ben", "ben passphrase 2")
save.("07-home-ben", req.(:get, "/", %{}, ben))
if System.get_env("ITEM_PAGES"), do: save.("11-item-ben-rent", req.(:get, "/items/" <> id_of.("Rent"), %{}, ben))
IO.puts("captured")
