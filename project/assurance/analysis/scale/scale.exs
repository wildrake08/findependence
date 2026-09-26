# Scale check (WI-027). Usage, from app/: mix run ../project/assurance/analysis/scale/scale.exs <existing dir> <number of items>
# Seeds a two-member household with N items (mixed frequencies), 8 values, and links for two thirds
# of the items, then prints the file size and the mean server time of 20 home and 20 item-page requests,
# and saves both pages as HTML for measuring in a browser.
import Plug.Test
alias FindependenceApp.{Sessions, Store, Vault, Web}
[out, n_str] = System.argv(); n = String.to_integer(n_str)
path = Path.join(out, "scale-#{n}.vault")
Vault.create([{"Maya", "maya pw 1"}, {"Jordan", "jordan pw 2"}], iterations: 1_000, unsafe_test: true) |> Vault.write!(path)
{:ok, _} = Store.start_link(path: path)
{:ok, _} = Sessions.start_link([])
req = fn method, p, params, prev ->
  conn = %{conn(method, p, params) | host: "127.0.0.1", port: 4848}
  conn = if prev, do: recycle_cookies(conn, prev), else: conn
  Web.call(conn, Web.init(port: 4848))
end
tok = fn c -> Regex.run(~r/name=_csrf_token value="([^"]+)"/, c.resp_body) |> List.last() end
post = fn prev, p, params -> page = req.(:get, "/", %{}, prev); req.(:post, p, Map.put(params, "_csrf_token", tok.(page)), page) end
maya = post.(req.(:get, "/", %{}, nil), "/login", %{"member" => "Maya", "passphrase" => "maya pw 1"})
names = ["Rent", "Groceries", "Electric", "Water", "Internet", "Phone", "Car payment", "Gas", "Insurance", "Childcare", "Daycare snacks", "Pharmacy", "Dentist", "Gym", "Streaming", "Books", "School fees", "Haircut", "Gifts", "Coffee", "Lunches", "Bus pass", "Parking", "Pet food", "Vet", "Clothes", "Shoes", "Laptop repair", "Charity", "Savings transfer", "Paycheck", "Side job", "Tax refund", "Student loan", "Credit card", "Hobby supplies", "Garden", "Home repair", "Furniture", "Trip fund", "Concert", "Takeout", "Toiletries", "Cleaning", "Subscriptions", "Bank fee", "Allowance", "Birthday", "Tuition", "Music lessons"]
freqs = ~w(monthly weekly biweekly yearly one_off)
for i <- 0..(n - 1) do
  name = Enum.at(names, rem(i, length(names))) <> if(i >= length(names), do: " #{div(i, length(names)) + 1}", else: "")
  dir = if rem(i, 7) == 3, do: "in", else: "out"
  post.(maya, "/act/add_item", %{"note" => name, "amount" => "#{rem(i * 37, 900) + 5}.#{rem(i * 13, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}", "direction" => dir, "frequency" => Enum.at(freqs, rem(i, 5))})
end
for l <- ["A safe home", "Kids' future", "Getting out of debt", "Health", "Time outdoors", "Learning", "Giving back", "Rest"], do: post.(maya, "/act/add_value", %{"label" => l})
{:ok, s} = FindependenceApp.Session.open(Vault.read!(path), "Maya", "maya pw 1")
ids = FindependenceApp.Web.Html.names(s.household, "Maya")
items = for {id, _} <- ids, not Findependence.Alignment.value?(s.household.items[id]), do: id
vals = for {id, _} <- ids, Findependence.Alignment.value?(s.household.items[id]), do: id
for {it, k} <- Enum.with_index(items), rem(k, 3) != 0, do: post.(maya, "/act/link", %{"item" => it, "value" => Enum.at(vals, rem(k, length(vals)))})
# timing: 20 home GETs, 20 item page GETs
t = fn f -> {us, _} = :timer.tc(fn -> for _ <- 1..20, do: f.() end); us / 20 / 1000 end
home_ms = t.(fn -> req.(:get, "/", %{}, maya) end)
item_ms = t.(fn -> req.(:get, "/items/" <> hd(items), %{}, maya) end)
File.write!(Path.join(out, "home-#{n}.html"), req.(:get, "/", %{}, maya).resp_body)
File.write!(Path.join(out, "item-#{n}.html"), req.(:get, "/items/" <> hd(items), %{}, maya).resp_body)
IO.puts("n=#{n} file=#{File.stat!(path).size} bytes home=#{Float.round(home_ms, 1)} ms item=#{Float.round(item_ms, 1)} ms")
