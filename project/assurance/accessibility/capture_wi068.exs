# WI-068: every field-level refusal the router's parsers produce today (retirement, readings, set-asides,
# fund goal, borrowing steps), saved so the pages can be compared before and after the rules move.
# Usage, from app/: mix run ../project/assurance/accessibility/capture_wi068.exs <existing dir>
import Plug.Test
alias FindependenceApp.{Sessions, Store, Vault, Web}

out = hd(System.argv())
path = Path.join(out, "wi068.vault")
File.rm(path)
Application.put_env(:findependence_app, :today, ~D[2026-09-27])
Vault.create([{"Ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true) |> Vault.write!(path)
{:ok, _} = Store.start_link(path: path)
{:ok, _} = Sessions.start_link([])

req = fn method, p, params, prev ->
  conn = %{conn(method, p, params) | host: "127.0.0.1", port: 4848}
  conn = if prev, do: recycle_cookies(conn, prev), else: conn
  Web.call(conn, Web.init(port: 4848))
end

tok = fn c -> Regex.run(~r/name=_csrf_token value="([^"]+)"/, c.resp_body) |> List.last() end
form = fn c -> Regex.run(~r/name=_form value="([^"]+)"/, c.resp_body) |> List.last() end

post = fn prev, p, params ->
  page = req.(:get, "/", %{}, prev)
  req.(:post, p, Map.merge(params, %{"_csrf_token" => tok.(page), "_form" => form.(page)}), page)
end

location = fn resp -> resp |> Plug.Conn.get_resp_header("location") |> List.first() end
save = fn name, conn -> File.write!(Path.join(out, name <> ".html"), "#{conn.status}\n" <> conn.resp_body) end

first = req.(:get, "/", %{}, nil)
ana = post.(first, "/login", %{"member" => "Ana", "passphrase" => "ana passphrase 1"})

"/items/" <> account =
  location.(post.(ana, "/act/add_account", %{"type" => "savings", "label" => "Savings"}))

"/items/" <> debt = location.(post.(ana, "/act/add_debt", %{"type" => "card", "label" => "Card"}))

"/items/" <> ira = location.(post.(ana, "/act/add_account", %{"type" => "ira", "label" => "IRA"}))
_ = post.(ana, "/act/add_value", %{"label" => "Side business"})
"/plans/" <> plan = location.(post.(ana, "/act/new_plan", %{"name" => "A plan"}))

goals = req.(:get, "/goals", %{}, ana).resp_body
[_, value] = Regex.run(~r/action="\/act\/set_aside".*?<option value="?([A-Za-z0-9_-]{12})/s, goals)

retirement = fn name, fields -> save.("ret-" <> name, post.(ana, "/act/retirement", fields)) end
retirement.("year-low", %{"birth_year" => "1800"})
retirement.("year-text", %{"birth_year" => "nineteen"})
retirement.("age-low", %{"retire_age" => "30"})
retirement.("age-high", %{"retire_age" => "95"})
retirement.("return-high", %{"return" => "20"})
retirement.("return-low", %{"return" => "-6"})
retirement.("return-text", %{"return" => "five"})
retirement.("several", %{"birth_year" => "1800", "retire_age" => "30", "return" => "20"})
retirement.("contribution-text", %{"contribution_" <> ira => "lots"})
retirement.("ok", %{"birth_year" => "1968", "retire_age" => "67", "return" => "4.5"})

reading = fn name, item, fields ->
  save.("reading-" <> name, post.(ana, "/act/add_reading", Map.put(fields, "item", item)))
end

reading.("account-empty", account, %{"balance" => "", "on" => "2026-09-27"})
reading.("account-text", account, %{"balance" => "lots", "on" => "2026-09-27"})
reading.("account-date", account, %{"balance" => "100", "on" => "yesterday"})
reading.("account-overdrawn", account, %{"balance" => "−50", "on" => "2026-09-27"})
reading.("debt-negative", debt, %{"balance" => "−50", "on" => "2026-09-27", "rate" => "20", "min_payment" => "10"})
reading.("debt-negative-dollar", debt, %{"balance" => "-$50", "on" => "2026-09-27", "rate" => "20", "min_payment" => "10"})
reading.("debt-rate-high", debt, %{"balance" => "500", "on" => "2026-09-27", "rate" => "150", "min_payment" => "10"})
reading.("debt-rate-text", debt, %{"balance" => "500", "on" => "2026-09-27", "rate" => "high", "min_payment" => "10"})
reading.("debt-min-empty", debt, %{"balance" => "500", "on" => "2026-09-27", "rate" => "20", "min_payment" => ""})
reading.("debt-all-bad", debt, %{"balance" => "x", "on" => "x", "rate" => "x", "min_payment" => "x"})
reading.("debt-ok", debt, %{"balance" => "500", "on" => "2026-09-27", "rate" => "21.99", "min_payment" => "25"})

aside = fn name, rate -> save.("aside-" <> name, post.(ana, "/act/set_aside", %{"value" => value, "rate" => rate})) end
aside.("zero", "0")
aside.("high", "150")
aside.("text", "some")
aside.("ok", "10")

goal = fn name, months -> save.("goal-" <> name, post.(ana, "/act/fund_goal", %{"months" => months})) end
goal.("text", "six")
goal.("negative", "-1")
goal.("ok", "6")

borrow = fn name, fields ->
  save.("borrow-" <> name, post.(ana, "/act/plan_step", Map.merge(%{"plan" => plan, "kind" => "borrow", "from" => "2026-11"}, fields)))
end

borrow.("zero", %{"amount" => "0", "rate" => "5", "payment" => "100"})
borrow.("rate-high", %{"amount" => "1000", "rate" => "200", "payment" => "100"})
borrow.("payment-empty", %{"amount" => "1000", "rate" => "5", "payment" => ""})
borrow.("ok", %{"amount" => "1000", "rate" => "5", "payment" => "100"})
IO.puts("captured")
