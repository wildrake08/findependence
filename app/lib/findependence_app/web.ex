defmodule FindependenceApp.Web do
  @moduledoc """
  MEC-015: a minimal browser interface, served only on 127.0.0.1 (REQ-123, REQ-124).

  - Listens on the loopback address only (`child_spec/1`).
  - `HostCheck` rejects any Host other than `127.0.0.1:<port>` or `localhost:<port>`, which
    defeats DNS rebinding.
  - Every POST needs a CSRF token (`Plug.CSRFProtection`), because pages on other sites can
    submit forms to localhost.
  - The cookie holds only a signed session token. Unlocked keys stay in `FindependenceApp.Sessions`.
  - Every response carries a Content-Security-Policy that forbids loading anything remote, plus
    no-store caching.

  Pages are server-rendered HTML with no JavaScript. Every user-supplied string is escaped.
  """

  use Plug.Router

  alias FindependenceApp.{Sessions, Store}
  alias FindependenceApp.Web.Html
  alias Findependence.{Alignment, Exit, Household}

  @csp "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"

  @doc "Bandit child spec. Always binds 127.0.0.1."
  def child_spec(opts) do
    port = Keyword.get(opts, :port, 4848)
    Bandit.child_spec(plug: {__MODULE__, port: port}, ip: {127, 0, 0, 1}, port: port)
  end

  @doc "The address the server binds, for inspection and tests."
  def bind_ip, do: {127, 0, 0, 1}

  plug(:host_check)
  plug(:security_headers)
  plug(Plug.Parsers, parsers: [:urlencoded], pass: ["text/*"])

  plug(Plug.Session,
    store: :cookie,
    key: "_fv",
    signing_salt: "fv-session",
    same_site: "Strict",
    http_only: true
  )

  plug(:put_secret)
  plug(:fetch_session)
  plug(Plug.CSRFProtection)
  plug(:match)
  plug(:dispatch)

  # The secret is random per server start, so a restart invalidates every cookie.
  def put_secret(conn, _opts) do
    %{conn | secret_key_base: :persistent_term.get({__MODULE__, :secret}, nil) || new_secret()}
  end

  defp new_secret do
    secret = Base.encode64(:crypto.strong_rand_bytes(48))
    :persistent_term.put({__MODULE__, :secret}, secret)
    secret
  end

  # conn.host and conn.port come from the request's Host header.
  def host_check(conn, _opts) do
    port = conn.private[:fv_port] || conn.port

    if conn.host in ["127.0.0.1", "localhost"] and conn.port == port,
      do: conn,
      else: conn |> send_resp(421, "Misdirected request") |> halt()
  end

  def init(opts), do: opts

  def call(conn, opts) do
    conn |> put_private(:fv_port, Keyword.get(opts, :port)) |> super(opts)
  end

  defp security_headers(conn, _opts) do
    conn
    |> put_resp_header("content-security-policy", @csp)
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
  end

  # ---------------------------------------------------------------------------
  # Routes

  get "/" do
    case current(conn) do
      {:ok, _token, s} ->
        s = Store.refresh(s)
        {conn, flash} = pop_flash(conn)

        page(
          conn,
          s.member,
          Html.integrity_banner(FindependenceApp.Session.integrity_issues(s)) <>
            Html.home(s.household, s.member, csrf(), flash),
          200,
          Html.waiting_count(s.household, s.member)
        )

      {:locked, :expired} ->
        conn
        |> configure_session(drop: true)
        |> page(nil, Html.login(members(), csrf(), nil, :idle))

      :locked ->
        notice =
          case conn |> fetch_query_params() |> Map.get(:query_params) |> Map.get("locked") do
            "action" -> :idle_action
            "idle" -> :idle
            "replaced" -> :replaced
            _ -> nil
          end

        page(conn, nil, Html.login(members(), csrf(), nil, notice))
    end
  end

  # UX-001 R1: one page per thing.
  get "/items/:id" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      {conn, flash} = pop_flash(conn)
      waiting = Html.waiting_count(s.household, s.member)

      case Html.item_page(s.household, s.member, id, csrf(), flash) do
        nil ->
          page(
            conn,
            s.member,
            ~s(<section class=card><h2>Not available</h2><p>That isn't available to you. It may have been deleted, or it isn't shared with you.</p><p><a href="/">Back to everything</a></p></section>),
            404,
            waiting
          )

        body ->
          page(
            conn,
            s.member,
            Html.integrity_banner(FindependenceApp.Session.integrity_issues(s)) <> body,
            200,
            waiting
          )
      end
    end)
  end

  # CAP-011: the next sixty days, day by day, and set-asides (REQ-139, REQ-140).
  get "/next-60-days" do
    with_session(conn, fn s ->
      s = Store.refresh(s)

      page(
        conn,
        s.member,
        Html.next_60_page(s.household, s.member, today()),
        200,
        Html.waiting_count(s.household, s.member)
      )
    end)
  end

  # CAP-010: adding an account or a debt.
  get "/balances/new" do
    with_session(conn, fn s ->
      s = Store.refresh(s)

      page(
        conn,
        s.member,
        Html.new_balance_page(csrf()),
        200,
        Html.waiting_count(s.household, s.member)
      )
    end)
  end

  post "/act/add_account" do
    add_balance(conn, "account", &Findependence.Balances.add_account/5, %{
      "checking" => :checking,
      "savings" => :savings,
      "other" => :other
    })
  end

  post "/act/add_debt" do
    add_balance(conn, "debt", &Findependence.Balances.add_debt/5, %{
      "card" => :card,
      "heloc" => :heloc,
      "loan" => :loan,
      "other" => :other
    })
  end

  # REQ-131: a reading, validated here so errors appear at the field with what was typed kept.
  post "/act/add_reading" do
    with_session(conn, fn s ->
      p = conn.body_params
      s = Store.refresh(s)
      item = s.household.items[p["item"]]
      debt? = item != nil and item.attrs[:kind] == :debt
      owner? = item != nil and s.member in item.owners

      parsed =
        with {:ok, balance} <- parse_balance(p["balance"], debt?),
             {:ok, on} <- parse_date(p["on"]),
             {:ok, extra} <- parse_debt_fields(p, debt?) do
          {:ok, Map.merge(%{on: on, balance: balance}, extra)}
        end

      case parsed do
        # someone who can't update it is told so, whatever they typed (the core checks who first)
        _ when not owner? ->
          act(
            conn,
            s,
            "add_reading",
            &Findependence.Balances.add_reading(&1, s.member, p["item"], %{})
          )

        {:ok, reading} ->
          act(
            conn,
            s,
            "add_reading",
            &Findependence.Balances.add_reading(&1, s.member, p["item"], reading)
          )

        {:error, field, message} ->
          form = %{
            balance: p["balance"],
            rate: p["rate"],
            min_payment: p["min_payment"],
            on: p["on"],
            error: message,
            error_field: field
          }

          body =
            Html.item_page(s.household, s.member, p["item"], csrf(), nil, form) ||
              Html.home(s.household, s.member, csrf(), {:error, Html.error_text(:not_found)})

          page(conn, s.member, body, 422, Html.waiting_count(s.household, s.member))
      end
    end)
  end

  # UX-001 R8: a checklist for leaving; it is also the confirmation.
  get "/leave" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      {conn, flash} = pop_flash(conn)

      page(
        conn,
        s.member,
        Html.leave_page(s.household, s.member, csrf(), flash),
        200,
        Html.waiting_count(s.household, s.member)
      )
    end)
  end

  post "/login" do
    %{"member" => m, "passphrase" => p} = conn.body_params

    case Store.open(m, p) do
      {:ok, s} ->
        token = Sessions.put(s)
        conn |> configure_session(renew: true) |> put_session(:token, token) |> redirect("/")

      {:error, :bad_credentials} ->
        page(
          conn,
          nil,
          Html.login(members(), csrf(), "That name and passphrase don't match."),
          401
        )
    end
  end

  post "/logout" do
    with {:ok, token, _} <- current(conn), do: Sessions.drop(token)
    conn |> configure_session(drop: true) |> redirect("/")
  end

  get "/export" do
    with_session(conn, fn s ->
      s = Store.refresh(s)

      page(
        conn,
        s.member,
        Html.export_page(Exit.export(s.household, s.member), Html.names(s.household, s.member))
      )
    end)
  end

  get "/export.json" do
    with_session(conn, fn s ->
      s = Store.refresh(s)

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="findependence-export.json")
      )
      |> send_resp(200, Html.export_json(Exit.export(s.household, s.member)))
    end)
  end

  # Irreversible actions go through a confirmation page first.
  post "/confirm/:action" when action in ["delete", "relinquish"] do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      fields = Map.take(conn.body_params, ["item"])
      what = Html.names(s.household, s.member)[fields["item"]] || ""

      keepers =
        case s.household.items[fields["item"]] do
          %{owners: owners} -> owners |> MapSet.delete(s.member) |> Enum.sort()
          nil -> []
        end

      page(conn, s.member, Html.confirm_page(action, fields, what, csrf(), keepers))
    end)
  end

  # REQ-129 (CP-012): form values and what is stored for them.
  @frequencies %{
    "one_off" => :one_off,
    "weekly" => {:every, 1, :week},
    "biweekly" => {:every, 2, :week},
    "monthly" => {:every, 1, :month},
    "every_2_months" => {:every, 2, :month},
    "every_3_months" => {:every, 3, :month},
    "twice_a_year" => {:every, 6, :month},
    "yearly" => {:every, 1, :year},
    "irregular" => :irregular
  }

  # UX-001 R2: an unclear amount is rejected before anything is saved, with the input kept.
  post "/act/add_item" do
    with_session(conn, fn s ->
      p = conn.body_params

      # REQ-127: how often it happens is the member's choice; there is no default.
      frequency = Map.get(@frequencies, p["frequency"])

      # REQ-136: the date is optional; irregular items have no dates
      on = String.trim(p["on"] || "")

      parsed =
        case FindependenceApp.Money.parse(p["amount"], p["direction"] || "out") do
          {:ok, _} when frequency == nil ->
            {:error, :frequency, "Choose how often this happens."}

          {:ok, cents} ->
            cond do
              on == "" or frequency == :irregular -> {:ok, cents, nil}
              match?({:ok, _}, Date.from_iso8601(on)) -> {:ok, cents, on}
              true -> {:error, :on, "Enter the date, like 2026-10-01, or leave it empty."}
            end

          {:error, message} ->
            {:error, :amount, message}
        end

      case parsed do
        {:ok, cents, on} ->
          attrs = %{note: p["note"], unit: :cents, frequency: frequency}
          attrs = if cents, do: Map.put(attrs, :amount, cents), else: attrs
          attrs = if on, do: Map.put(attrs, :on, on), else: attrs

          act(conn, s, "add_item", &Household.add_item(&1, s.member, new_id(), attrs))

        {:error, field, message} ->
          s = Store.refresh(s)

          form = %{
            note: p["note"],
            amount: p["amount"],
            direction: p["direction"],
            frequency: p["frequency"],
            on: p["on"],
            error: message,
            error_field: field
          }

          page(conn, s.member, Html.home(s.household, s.member, csrf(), nil, form), 422)
      end
    end)
  end

  post "/act/:action" do
    with_session(conn, fn s ->
      m = s.member
      p = conn.body_params

      op =
        case action do
          "add_value" ->
            &Alignment.add_value(&1, m, new_id(), p["label"])

          "grant" ->
            &Household.propose_grant(&1, m, p["item"], p["member"])

          "revoke" ->
            &Household.revoke_grant(&1, m, p["item"], p["member"])

          "owners" ->
            &Household.propose_owners(
              &1,
              m,
              p["item"],
              List.wrap(p["owners"])
            )

          "consent" ->
            &Household.consent(&1, m, to_int(p["proposal"]))

          "relinquish" ->
            &Household.relinquish(&1, m, p["item"])

          "delete" ->
            &Exit.delete(&1, m, p["item"])

          # UX-001 R8: a sole owner's one choice on the leave checklist.
          "let_go" ->
            case p["to"] do
              "delete" -> &Exit.delete(&1, m, p["item"])
              "give:" <> to -> &Household.propose_owners(&1, m, p["item"], [to])
              _ -> fn _ -> {:error, :no_choice} end
            end

          "link" ->
            &Alignment.link(&1, m, p["item"], p["value"])

          "unlink" ->
            &Alignment.unlink(&1, m, p["item"], p["value"])

          "withdraw" ->
            &Household.withdraw(&1, m, to_int(p["proposal"]))

          "leave" ->
            &Exit.leave(&1, m)

          _ ->
            fn _ -> {:error, :unknown_action} end
        end

      act(conn, s, action, op)
    end)
  end

  # Applies one core operation for the session's member, then shows the result.
  # UX-001 R6: return to where the action was taken, with a message stating the actual outcome.
  defp act(conn, s, action, op) do
    {:ok, token, _} = current(conn)
    before = Store.refresh(s).household
    params = conn.body_params

    case Store.apply(s, op) do
      {:ok, s2} ->
        if action == "leave" do
          Sessions.drop(token)
          conn |> configure_session(drop: true) |> redirect("/")
        else
          Sessions.update(token, s2)
          message = Html.outcome(action, params, before, s2.household, s.member)

          conn
          |> put_session(:flash, message)
          |> redirect(return_to(params["return"], s2.household, s.member))
        end

      {:error, reason, s2} ->
        Sessions.update(token, s2)
        error = {:error, Html.error_text(reason)}
        waiting = Html.waiting_count(s2.household, s.member)

        body =
          case return_to(params["return"], s2.household, s.member) do
            "/items/" <> id -> Html.item_page(s2.household, s.member, id, csrf(), error)
            "/leave" -> Html.leave_page(s2.household, s.member, csrf(), error)
            _ -> Html.home(s2.household, s.member, csrf(), error)
          end

        page(conn, s.member, body, 422, waiting)
    end
  end

  # Only an item page the member can still see, the leave checklist, or home: never an arbitrary URL (no open redirect).
  defp return_to("/items/" <> id = path, h, m) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, id) and Findependence.View.visible?(h, m, id),
      do: path,
      else: "/"
  end

  defp return_to("/leave", _h, _m), do: "/leave"
  defp return_to(_, _h, _m), do: "/"

  defp pop_flash(conn) do
    case get_session(conn, :flash) do
      nil -> {conn, nil}
      text -> {delete_session(conn, :flash), {:ok, text}}
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # ---------------------------------------------------------------------------
  # Pages

  defp members, do: Store.vault() |> FindependenceApp.Vault.members()

  @css """
  :root{--ink:#1d2330;--muted:#5b6475;--line:#d9dde5;--bg:#f6f7f9;--card:#fff;--accent:#1f5fbf;--ok:#1b6b3a;--err:#a4262c}
  *{box-sizing:border-box}
  body{margin:0;font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif;color:var(--ink);background:var(--bg)}
  header{display:flex;justify-content:space-between;align-items:center;gap:1rem;padding:.75rem 1rem;background:var(--card);border-bottom:1px solid var(--line)}
  header h1{font-size:1.25rem;margin:0}header h1 a{color:inherit;text-decoration:none}.who{font-weight:600;margin-right:.5rem}
  main,footer{max-width:56rem;margin:0 auto;padding:1rem}
  .card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:1rem 1.25rem;margin:0 0 1rem}
  .card.warn{border-color:var(--err)}
  h2{font-size:1.15rem;margin:.25rem 0 .5rem}h3{font-size:1rem;margin:1rem 0 .25rem}
  .hint,.muted td{color:var(--muted)}.hint{font-size:.9rem}.empty{color:var(--muted);font-style:italic}
  .scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;margin:.5rem 0}
  th,td{border-bottom:1px solid var(--line);padding:.4rem .5rem;text-align:left;vertical-align:top}
  th{font-size:.85rem;color:var(--muted);font-weight:600}
  .num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
  form{margin:.5rem 0}form.row{display:flex;flex-wrap:wrap;gap:.5rem 1rem;align-items:flex-end}form.row p{margin:0}
  .inline{display:inline;margin:0 .25rem 0 0}
  label{display:block;font-size:.9rem;color:var(--muted)}label.check{display:inline-block;margin-right:1rem;color:var(--ink)}
  input,select{font:inherit;padding:.4rem .5rem;border:1px solid #7b8494;border-radius:6px;min-width:10rem;max-width:100%}
  input[type=checkbox],input[type=radio]{min-width:0;padding:0}
  button{font:inherit;padding:.4rem .8rem;border-radius:6px;border:1px solid var(--accent);background:var(--accent);color:#fff;cursor:pointer}
  a.button-link{display:inline-block;padding:.2rem .6rem;font-size:.9rem;border:1px solid var(--accent);border-radius:6px;color:var(--accent);text-decoration:none;margin-right:.25rem}
  .inline button,td button{background:#fff;color:var(--accent);padding:.2rem .6rem;font-size:.9rem}
  button.danger{border-color:var(--err);background:#fff;color:var(--err)}.card.warn button.danger{background:var(--err);color:#fff}
  .badge{display:inline-block;font-size:.8rem;font-weight:600;padding:.1rem .5rem;border-radius:999px;background:#fff6dc;color:#6b4e00;text-decoration:none;margin-right:.5rem}
  .card.attention{border-color:#c79a1e}
  .amount-big{font-size:1.4rem;font-variant-numeric:tabular-nums;margin:.25rem 0}
  .field-error{flex:1 1 100%;margin:.25rem 0 0;color:var(--err);font-size:.9rem}
  fieldset.direction{border:0;margin:0;padding:0;display:flex;gap:.25rem 1rem;align-items:center}fieldset.direction legend{float:left;margin-right:.5rem;font-size:.9rem;color:var(--muted)}
  input[aria-invalid=true],select[aria-invalid=true]{border-color:var(--err)}
  :focus-visible{outline:3px solid #f0b400;outline-offset:2px}
  input[type=date]:focus,input[type=date]:focus-within{outline:3px solid #f0b400;outline-offset:2px}
  fieldset{border:1px solid var(--line);border-radius:6px;margin:.5rem 0}
  ul.plain{list-style:none;padding:0}ul.plain li{padding:.35rem 0;border-bottom:1px solid var(--line)}
  details{margin-top:.25rem}summary{cursor:pointer;color:var(--accent)}
  .msg{padding:.6rem .9rem;border-radius:8px;margin:0 0 1rem}.msg.ok{background:#e6f4ea;color:var(--ok)}.msg.err{background:#fde8e8;color:var(--err)}.msg.info{background:#e8eef9;color:#1d3f7a}
  .below{display:inline-block;font-size:.8rem;font-weight:600;padding:0 .4rem;border-radius:4px;background:#fde8e8;color:var(--err)}
  .nowrap{white-space:nowrap}
  .phone-only{display:none}
  @media (max-width:40rem){
  main{padding:.5rem}.card{padding:.75rem}
  input:not([type=checkbox]):not([type=radio]),select{min-width:0;width:100%}form.row p{flex:1 1 100%}
  table.stack thead{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
  table.stack tbody tr{display:block;border-bottom:1px solid var(--line);padding:.5rem 0}
  table.stack td{display:flex;gap:.75rem;border:0;padding:.15rem 0}
  table.stack td[data-label]::before{content:attr(data-label);content:attr(data-label) / "";flex:0 0 7.5rem;white-space:normal;color:var(--muted);font-size:.85rem}
  table.stack td.num{text-align:left;white-space:normal}
  table.stack td{min-width:0;overflow-wrap:anywhere}
  .phone-only{display:inline}
  table.stack.compact tbody tr{display:grid;grid-template-columns:auto minmax(0,1fr) auto;column-gap:.5rem;row-gap:.1rem;padding:.45rem 0}
  table.stack.compact td{display:block;padding:0}
  table.stack.compact td[data-label]::before{content:none}
  table.stack.compact td:first-child{grid-column:1 / 3;grid-row:1}
  table.stack.compact td.num{grid-column:3;grid-row:1;text-align:right}
  table.stack.compact td.meta{grid-row:2;font-size:.85rem;color:var(--muted)}
  table.stack.compact td.owner{grid-column:1}
  table.stack.compact td.owner::before{content:"Owned by ";content:"Owned by " / ""}
  table.stack.compact td.vis{grid-column:2 / 4}
  table.stack.compact td.vis::before{content:"· ";content:"· " / ""}
  }
  """

  defp page(conn, member, body, status \\ 200, waiting \\ 0) do
    # UX-001 R7: how many changes are waiting for this member, from any page.
    badge =
      if waiting > 0,
        do: ~s(<a class=badge href="/#waiting">#{waiting} waiting for you</a> ),
        else: ""

    who =
      if member,
        do:
          ~s(<form class=inline method=post action="/logout">#{badge}<span class=who>#{Html.esc(member)}</span> #{csrf()}<button>Lock</button></form>),
        else: ""

    html = """
    <!doctype html><html lang=en><head><meta charset=utf-8>
    <meta name=viewport content="width=device-width, initial-scale=1">
    <title>Findependence</title><style>#{@css}</style></head>
    <body><header><h1><a href="/">Findependence</a></h1>#{who}</header>
    <main>#{body}</main>
    <footer class=hint><b>Alpha: use made-up data only.</b> Everything stays on this device. Nothing is sent anywhere.</footer></body></html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(status, html)
  end

  # ---------------------------------------------------------------------------

  defp current(conn) do
    case get_session(conn, :token) do
      nil -> :locked
      token -> with {:ok, s} <- Sessions.fetch(token), do: {:ok, token, s}
    end
  end

  # UX-001 R4: a timed-out session says so on the unlock screen. A discarded action is never
  # replayed after unlocking, but the member is told it was not saved.
  defp with_session(conn, fun) do
    case current(conn) do
      {:ok, _token, s} ->
        fun.(s)

      {:locked, :expired} ->
        why = if conn.method == "POST", do: "action", else: "idle"
        conn |> configure_session(drop: true) |> redirect("/?locked=" <> why)

      # WI-032: the session is gone (someone else unlocked, or the app restarted). A form sent now is
      # lost, so say so; the notice doesn't say why, which could reveal that someone else used the device.
      :locked ->
        to = if conn.method == "POST", do: "/?locked=replaced", else: "/"
        conn |> configure_session(drop: true) |> redirect(to)
    end
  end

  @doc """
  The release stage's rule for testers (REV-034, REV-035): the alpha is internal testing with made-up
  data only. Shown on the unlock page and in every footer, and printed by setup and serve.
  """
  def release_notice,
    do:
      "Alpha: use made-up data only. Don't enter real financial or personal information, or a passphrase you use anywhere else."

  @doc """
  Today's date on this device, for dates in forms and the cash-flow view. Tests may fix it with
  `Application.put_env(:findependence_app, :today, ~D[...])`.
  """
  def today,
    do:
      Application.get_env(:findependence_app, :today) ||
        NaiveDateTime.to_date(NaiveDateTime.local_now())

  defp redirect(conn, to), do: conn |> put_resp_header("location", to) |> send_resp(303, "")

  defp csrf,
    do: "<input type=hidden name=_csrf_token value=\"#{Plug.CSRFProtection.get_csrf_token()}\">"

  defp new_id, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  defp add_balance(conn, which, add, types) do
    with_session(conn, fn s ->
      p = conn.body_params
      label = String.trim(p["label"] || "")

      case Map.get(types, p["type"]) do
        type when type != nil and label != "" ->
          id = new_id()
          conn = %{conn | body_params: Map.merge(p, %{"return" => "/items/" <> id, "item" => id})}
          act(conn, s, "add_" <> which, &add.(&1, s.member, id, label, type))

        _ ->
          s = Store.refresh(s)
          message = if label == "", do: "Give it a name.", else: "Choose what kind it is."
          form = %{which: which, label: p["label"], type: p["type"], error: message}

          page(
            conn,
            s.member,
            Html.new_balance_page(csrf(), form),
            422,
            Html.waiting_count(s.household, s.member)
          )
      end
    end)
  end

  # A balance: an account may be overdrawn (a leading − or -); a debt's amount owed may not.
  defp parse_balance(text, debt?) do
    raw = String.trim(text || "")
    negative? = not debt? and String.starts_with?(raw, ["-", "−"])

    unsigned =
      if negative?,
        do: raw |> String.replace_prefix("-", "") |> String.replace_prefix("−", ""),
        else: raw

    case FindependenceApp.Money.parse(unsigned, "in") do
      {:ok, nil} ->
        {:error, :balance, "Enter the balance."}

      {:ok, cents} ->
        {:ok, if(negative?, do: -cents, else: cents)}

      {:error, _} when debt? ->
        {:error, :balance, "Enter the amount owed, like 5,200 or 5200.00."}

      {:error, _} ->
        {:error, :balance, "Enter the balance, like 1,240.50, or −50 if overdrawn."}
    end
  end

  defp parse_date(text) do
    case Date.from_iso8601(String.trim(text || "")) do
      {:ok, d} -> {:ok, Date.to_iso8601(d)}
      _ -> {:error, :on, "Enter the date, like 2026-09-27."}
    end
  end

  defp parse_debt_fields(_p, false), do: {:ok, %{}}

  defp parse_debt_fields(p, true) do
    rate = String.trim(p["rate"] || "") |> String.replace_suffix("%", "") |> String.trim()

    # "22", "21.9", and "21.99" are all rates; an unmatched decimal group is simply absent
    with {:rate, [_, whole | frac]} <-
           {:rate, Regex.run(~r/^(\d{1,3})(?:\.(\d{1,2}))?$/, rate)},
         bp =
           String.to_integer(whole) * 100 +
             String.to_integer(String.pad_trailing(List.first(frac, ""), 2, "0")),
         {:rate, true} <- {:rate, bp <= 10_000},
         {:min, {:ok, min}} when is_integer(min) <-
           {:min, FindependenceApp.Money.parse(p["min_payment"] || "", "in")} do
      {:ok, %{rate_bp: bp, min_payment: min}}
    else
      {:rate, _} -> {:error, :rate, "Enter the interest rate as a percentage, like 21.99."}
      {:min, _} -> {:error, :min_payment, "Enter the minimum payment, like 150."}
    end
  end

  defp to_int(nil), do: 0
  defp to_int(""), do: 0

  # Request numbers must be whole numbers ("5abc" is refused, WI-032); 0 matches no request.
  defp to_int(s) do
    case Integer.parse(s) do
      {n, ""} when n > 0 -> n
      _ -> 0
    end
  end
end
