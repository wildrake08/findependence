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
  require Logger

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

  plug(:log_refusals)
  plug(:host_check)
  plug(:security_headers)
  plug(:parse_body)

  plug(Plug.Session,
    store: :cookie,
    key: "_fv",
    signing_salt: "fv-session",
    same_site: "Strict",
    http_only: true
  )

  plug(:put_secret)
  plug(:fetch_session)
  plug(:csrf_protection)
  plug(:once_only)
  plug(:leave_bring_in)
  plug(:match)
  plug(:dispatch)

  # Forms are urlencoded. Only bringing in a record accepts a file (MEC-022), up to 1 MB of export
  # plus the form's own overhead; anything larger is refused before it is read.
  @form_parsers Plug.Parsers.init(parsers: [:urlencoded], pass: ["text/*"])
  @upload_parsers Plug.Parsers.init(
                    parsers: [:urlencoded, :multipart],
                    pass: ["text/*"],
                    length: 1_100_000
                  )
  @max_upload 1_048_576

  def parse_body(%{method: "POST", path_info: ["act", "bring-in"]} = conn, _opts) do
    Plug.Parsers.call(conn, @upload_parsers)
  rescue
    Plug.Parsers.RequestTooLargeError ->
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(
        413,
        ~s(<!doctype html><html lang=en><head><meta charset=utf-8><title>Findependence</title></head><body><main><h1>That file is too large</h1><p>An export file is at most 1 MB, so this one wasn't read. Nothing was brought in.</p><p><a href="/bring-in">Back</a></p></main></body></html>)
      )
      |> halt()
  end

  def parse_body(conn, _opts), do: Plug.Parsers.call(conn, @form_parsers)

  # The secret is random per server start, so a restart invalidates every cookie.
  def put_secret(conn, _opts) do
    %{conn | secret_key_base: :persistent_term.get({__MODULE__, :secret}, nil) || new_secret()}
  end

  defp new_secret do
    secret = Base.encode64(:crypto.strong_rand_bytes(48))
    :persistent_term.put({__MODULE__, :secret}, secret)
    secret
  end

  # C2 (WI-050): every refusal and error is logged, so a tester's report can be matched to what the server
  # did. Only the method, the path (item ids are random), the status, and the app's reason code: never a
  # query string, a form field, or anything the member typed or can read.
  def log_refusals(conn, _opts) do
    register_before_send(conn, fn conn ->
      # a 4xx or 5xx, or an action the app refused while redirecting (a lost session)
      if conn.status >= 400 or conn.private[:fv_refused] != nil do
        reason =
          case conn.private[:fv_refused] do
            nil -> ""
            r when is_atom(r) -> " (" <> Atom.to_string(r) <> ")"
            {r, _} when is_atom(r) -> " (" <> Atom.to_string(r) <> ")"
            _ -> ""
          end

        Logger.warning("refused #{conn.method} #{conn.request_path} #{conn.status}#{reason}")
      end

      conn
    end)
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

  @csrf_opts Plug.CSRFProtection.init([])

  # DEF-035 (WI-049): on a shared browser, a form on a page opened before a Lock, before another
  # member unlocked, or before a restart carries a CSRF token that no longer matches. It is refused as
  # before (403, nothing saved), but with a page that says so and offers a way on, instead of an empty
  # response. Like WI-032's notice, it doesn't say why, which could reveal that someone else used the device.
  defp csrf_protection(conn, _opts) do
    Plug.CSRFProtection.call(conn, @csrf_opts)
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError -> stale_form(conn)
  end

  defp stale_form(conn) do
    member =
      case current(conn) do
        {:ok, _token, s} -> s.member
        _ -> nil
      end

    body =
      ~s(<section class="card warn" role="alert"><h2>That wasn't saved</h2><p>This page was out of date, so nothing was saved. Go to the home page and do it again.</p><p><a href="/">Go to the home page</a></p></section>)

    conn |> page(member, body, 403) |> halt()
  end

  # REQ-165 (UX-004 P1): every form carries a one-time token (see csrf/0). A form that already changed
  # the household is not applied again: the repeat goes where the first one went, and says so. A
  # sending that changed nothing (refused, or the session had ended) frees its token. A request from an
  # unlocked session without a form token can't be checked, so it is refused like a stale form (DEF-041).
  defp once_only(%{method: "POST", request_path: "/act/" <> _} = conn, _opts) do
    with token when is_binary(token) <- get_session(conn, :token),
         {:form, _, form} when is_binary(form) and form != "" <-
           {:form, token, conn.body_params["_form"]} do
      case Sessions.claim_form(token, form) do
        :fresh ->
          register_before_send(conn, &settle_form(&1, token, form))

        {:repeat, where} ->
          conn |> put_session(:flash, "That was already saved.") |> redirect(where) |> halt()

        :busy ->
          conn
          |> put_session(:flash, "That was already sent. Check below that it was saved.")
          |> redirect("/")
          |> halt()
      end
    else
      {:form, token, _} ->
        if Sessions.live?(token),
          do: conn |> put_private(:fv_refused, :no_form_token) |> stale_form(),
          else: conn

      _ ->
        conn
    end
  end

  defp once_only(conn, _opts), do: conn

  # REQ-158 (DEF-044): a checked file waits only while the member is on its preview. Any other request
  # means they left the page, so the file is dropped; confirming after that brings nothing in.
  defp leave_bring_in(%{method: "POST", request_path: "/act/bring-in" <> _} = conn, _opts),
    do: conn

  defp leave_bring_in(conn, _opts) do
    with token when is_binary(token) <- get_session(conn, :token),
         do: Sessions.take_pending(token)

    conn
  end

  defp settle_form(conn, token, form) do
    where =
      if conn.private[:fv_changed], do: conn |> get_resp_header("location") |> List.first()

    Sessions.settle_form(token, form, where)
    conn
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

      conn = fetch_query_params(conn)

      case Html.item_page(s.household, s.member, id, csrf(), flash, %{query: conn.query_params}) do
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

  # v0.3: the next twelve months, plans, and goals (REQ-141..148).
  get "/ahead" do
    with_session(conn, fn s ->
      s = Store.refresh(s)

      page(
        conn,
        s.member,
        Html.ahead_page(s.household, s.member, today()),
        200,
        Html.waiting_count(s.household, s.member)
      )
    end)
  end

  get "/plans" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      {conn, flash} = pop_flash(conn)

      page(
        conn,
        s.member,
        Html.plans_page(s.household, s.member, csrf(), flash),
        200,
        Html.waiting_count(s.household, s.member)
      )
    end)
  end

  get "/plans/:id" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      {conn, flash} = pop_flash(conn)
      waiting = Html.waiting_count(s.household, s.member)

      case Html.plan_page(s.household, s.member, id, csrf(), today(), flash) do
        nil ->
          page(
            conn,
            s.member,
            ~s(<section class=card><h2>Not available</h2><p>That plan isn't available to you.</p><p><a href="/plans">Back to plans</a></p></section>),
            404,
            waiting
          )

        body ->
          page(conn, s.member, body, 200, waiting)
      end
    end)
  end

  get "/requests/:id" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      waiting = Html.waiting_count(s.household, s.member)

      case Html.request_page(s.household, s.member, id, csrf(), today()) do
        nil ->
          page(
            conn,
            s.member,
            ~s(<section class=card><h2>Not available</h2><p>That request isn't waiting for you. It may have been withdrawn or already agreed.</p><p><a href="/">Back to everything</a></p></section>),
            404,
            waiting
          )

        body ->
          page(conn, s.member, body, 200, waiting)
      end
    end)
  end

  get "/retirement" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      {conn, flash} = pop_flash(conn)

      page(
        conn,
        s.member,
        Html.retirement_page(s.household, s.member, csrf(), today(), flash),
        200,
        Html.waiting_count(s.household, s.member)
      )
    end)
  end

  # REQ-150: every assumption in one form, checked here so errors appear at the field with what was
  # typed kept; saved together, and an empty field clears its assumption.
  post "/act/retirement" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      p = conn.body_params
      h = s.household

      accounts =
        for i <- Findependence.View.visible_items(h, s.member),
            Findependence.Balances.retirement?(i),
            do: i.id

      parsed =
        [
          {"birth_year", :birth_year, &parse_year/1},
          {"retire_age", :retire_age, &parse_age/1},
          {"return", :return_bp, &parse_return/1},
          {"ss", :ss_monthly, &parse_money/1},
          {"target", :target_monthly, &parse_money/1}
        ]
        |> Enum.map(fn {name, field, parse} -> {name, field, parse.(p[name])} end)

      contributions =
        for id <- accounts,
            do: {"contribution_" <> id, id, parse_money(p["contribution_" <> id])}

      errors =
        for {name, _, {:error, msg}} <- parsed ++ contributions, into: %{}, do: {name, msg}

      if errors != %{} do
        page(
          conn,
          s.member,
          Html.retirement_page(h, s.member, csrf(), today(), nil, %{values: p, errors: errors}),
          422,
          Html.waiting_count(h, s.member)
        )
      else
        conn = %{conn | body_params: Map.put(p, "return", "/retirement")}

        act(conn, s, "retirement", fn h ->
          with {:ok, h} <-
                 Enum.reduce_while(parsed, {:ok, h}, fn {_, f, {:ok, v}}, {:ok, h} ->
                   step(Findependence.Retirement.set(h, s.member, f, v))
                 end) do
            Enum.reduce_while(contributions, {:ok, h}, fn {_, id, {:ok, v}}, {:ok, h} ->
              step(Findependence.Retirement.set_contribution(h, s.member, id, v))
            end)
          end
        end)
      end
    end)
  end

  # CAP-009 (REQ-156..159): bring a saved export in, checked, previewed, then confirmed.
  get "/bring-in" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      {conn, flash} = pop_flash(conn)

      page(
        conn,
        s.member,
        Html.bring_in_page(csrf(), flash),
        200,
        Html.waiting_count(s.household, s.member)
      )
    end)
  end

  post "/act/bring-in" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      {:ok, token, _} = current(conn)
      waiting = Html.waiting_count(s.household, s.member)

      refuse = fn problem ->
        page(conn, s.member, Html.bring_in_page(csrf(), nil, problem), 422, waiting)
      end

      with {:file, %Plug.Upload{path: path, filename: name}} <- {:file, conn.body_params["file"]},
           {:size, size} when size <= @max_upload <- {:size, File.stat!(path).size},
           bytes = File.read!(path),
           fingerprint = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower),
           {:new, nil} <-
             {:new, Findependence.Import.imported_on(s.household, s.member, fingerprint)},
           {:json, {:ok, data}} <- {:json, decode_json(bytes)},
           {:checked, {:ok, bundle}} <- {:checked, Findependence.Import.check(data)} do
        Sessions.put_pending(token, %{bundle: bundle, fingerprint: fingerprint, name: name})

        page(
          conn,
          s.member,
          Html.bring_in_preview(Findependence.Import.summary(bundle), name, csrf()),
          200,
          waiting
        )
      else
        {:file, _} -> refuse.(:no_file)
        {:size, _} -> refuse.(:too_large)
        {:new, on} -> refuse.({:already_imported, on})
        {:json, _} -> refuse.(:not_json)
        {:checked, {:error, problems}} -> refuse.({:problems, problems})
      end
    end)
  end

  post "/act/bring-in/confirm" do
    with_session(conn, fn s ->
      {:ok, token, _} = current(conn)

      case Sessions.take_pending(token) do
        nil ->
          conn
          |> put_session(:flash, "Nothing is waiting to be brought in. Choose the file again.")
          |> redirect("/bring-in")

        %{bundle: bundle, fingerprint: fingerprint} ->
          conn = %{conn | body_params: Map.put(conn.body_params, "return", "/")}

          act(conn, s, "bring_in", fn h ->
            Findependence.Import.apply(h, s.member, bundle, &new_id/0, fingerprint, today())
          end)
      end
    end)
  end

  post "/act/bring-in/cancel" do
    with_session(conn, fn _s ->
      {:ok, token, _} = current(conn)
      Sessions.take_pending(token)

      conn
      |> put_session(:flash, "Nothing was brought in.")
      |> redirect("/bring-in")
    end)
  end

  get "/goals" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      {conn, flash} = pop_flash(conn)

      page(
        conn,
        s.member,
        Html.goals_page(s.household, s.member, csrf(), flash),
        200,
        Html.waiting_count(s.household, s.member)
      )
    end)
  end

  post "/act/new_plan" do
    with_session(conn, fn s ->
      id = new_id()
      conn = %{conn | body_params: Map.put(conn.body_params, "return", "/plans/" <> id)}

      act(
        conn,
        s,
        "new_plan",
        &Findependence.Plans.new_plan(&1, s.member, id, conn.body_params["name"] || "")
      )
    end)
  end

  post "/act/share_plan" do
    with_session(conn, fn s ->
      p = conn.body_params
      conn = %{conn | body_params: Map.put(p, "return", "/plans/" <> to_string(p["plan"]))}
      others = List.wrap(p["members"])

      act(
        conn,
        s,
        "share_plan",
        &Findependence.Plans.propose_shared(&1, s.member, p["plan"], new_id(), others)
      )
    end)
  end

  # REQ-142: a plan step, checked here so mistakes are named plainly
  post "/act/plan_step" do
    with_session(conn, fn s ->
      p = conn.body_params
      conn = %{conn | body_params: Map.put(p, "return", "/plans/" <> to_string(p["plan"]))}
      from = p["from"]

      step =
        case p["kind"] do
          "switch_off" ->
            case List.wrap(p["items"]) do
              [] -> {:error, "Tick at least one item to switch off."}
              ids -> {:ok, {:switch_off, ids, from}}
            end

          "add" ->
            f = Map.get(@frequencies, p["frequency"])
            note = String.trim(p["note"] || "")

            case FindependenceApp.Money.parse(p["amount"], p["direction"] || "out") do
              _ when note == "" ->
                {:error, "Name the planned item."}

              _ when f == nil ->
                {:error, "Choose how often the planned item happens."}

              {:ok, cents} when is_integer(cents) and cents != 0 ->
                {:ok, {:add, %{note: note, amount: cents, frequency: f}, from}}

              {:error, message} ->
                {:error, message}

              _ ->
                {:error, "Enter the planned amount."}
            end

          "borrow" ->
            with {:ok, amount} when is_integer(amount) and amount > 0 <-
                   FindependenceApp.Money.parse(p["amount"], "in"),
                 {:ok, %{rate_bp: bp}} <-
                   parse_debt_fields(%{"rate" => p["rate"], "min_payment" => "1"}, true),
                 {:ok, pay} when is_integer(pay) and pay > 0 <-
                   FindependenceApp.Money.parse(p["payment"], "in") do
              {:ok, {:borrow, %{amount: amount, rate_bp: bp, payment: pay}, from}}
            else
              _ ->
                {:error, "Enter how much to borrow, the interest rate, and the monthly payment."}
            end

          _ ->
            {:error, "Choose a kind of step."}
        end

      case step do
        {:ok, st} ->
          act(conn, s, "plan_step", &Findependence.Plans.add_step(&1, s.member, p["plan"], st))

        {:error, message} ->
          s = Store.refresh(s)

          body =
            Html.plan_page(s.household, s.member, p["plan"], csrf(), today(), {:error, message}) ||
              Html.plans_page(s.household, s.member, csrf(), {:error, message})

          page(conn, s.member, body, 422, Html.waiting_count(s.household, s.member))
      end
    end)
  end

  post "/act/fund_goal" do
    with_session(conn, fn s ->
      p = conn.body_params
      conn = %{conn | body_params: Map.put(p, "return", "/goals")}
      raw = String.trim(p["months"] || "")

      months =
        case Integer.parse(raw) do
          {n, ""} -> n
          _ when raw == "" -> nil
          _ -> :invalid
        end

      act(conn, s, "fund_goal", &Findependence.Plans.set_fund_goal(&1, s.member, months))
    end)
  end

  post "/act/set_aside" do
    with_session(conn, fn s ->
      p = conn.body_params
      conn = %{conn | body_params: Map.put(p, "return", "/goals")}
      raw = String.trim(p["rate"] || "")

      bp =
        cond do
          raw == "" ->
            nil

          true ->
            case parse_debt_fields(%{"rate" => raw, "min_payment" => "1"}, true) do
              {:ok, %{rate_bp: bp}} when bp > 0 -> bp
              _ -> :invalid
            end
        end

      act(conn, s, "set_aside", &Findependence.Plans.set_aside(&1, s.member, p["value"], bp))
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
      "other" => :other,
      "retirement_401k" => :retirement_401k,
      "ira" => :ira
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

  # The file is untrusted: any failure to decode is "not an export", never a crash.
  defp decode_json(bytes) do
    {:ok, :json.decode(bytes)}
  rescue
    _ -> :error
  end

  defp step({:ok, _} = ok), do: {:cont, ok}
  defp step(error), do: {:halt, error}

  defp parse_year(raw) do
    case String.trim(raw || "") do
      "" -> {:ok, nil}
      t -> parse_int(t, 1900..2100, "Enter the year you were born, like 1968.")
    end
  end

  defp parse_age(raw) do
    case String.trim(raw || "") do
      "" -> {:ok, nil}
      t -> parse_int(t, 40..90, "Enter an age from 40 to 90.")
    end
  end

  defp parse_int(t, range, msg) do
    case Integer.parse(t) do
      {n, ""} -> if n in range, do: {:ok, n}, else: {:error, msg}
      _ -> {:error, msg}
    end
  end

  # a yearly return in percent, after inflation, as basis points: "5" is 500, "-1.5" is -150
  defp parse_return(raw) do
    msg = "Enter a yearly return from −5 to 15, like 5 or 4.5."

    case Regex.run(~r/\A([-−])?(\d{1,2})(?:\.(\d{1,2}))?\z/u, String.trim(raw || "")) do
      nil ->
        if String.trim(raw || "") == "", do: {:ok, nil}, else: {:error, msg}

      [_, sign, whole | frac] ->
        f = frac |> List.first("") |> String.pad_trailing(2, "0")
        bp = String.to_integer(whole) * 100 + String.to_integer(f)
        bp = if sign in ["-", "−"], do: -bp, else: bp
        if bp in -500..1500, do: {:ok, bp}, else: {:error, msg}
    end
  end

  # a monthly amount in today's dollars; zero clears it
  defp parse_money(raw) do
    case FindependenceApp.Money.parse(raw || "", "in") do
      {:ok, 0} -> {:ok, nil}
      {:ok, c} -> {:ok, c}
      {:error, msg} -> {:error, msg}
    end
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
  # REQ-166: a plan is deleted only after the member sees its name and how many steps go with it
  post "/confirm/delete_plan" do
    with_session(conn, fn s ->
      s = Store.refresh(s)
      id = conn.body_params["plan"] || ""

      case Findependence.Plans.plans(s.household, s.member)[id] do
        nil ->
          conn |> put_session(:flash, "That plan no longer exists.") |> redirect("/plans")

        plan ->
          fields = %{"plan" => id, "return" => "/plans"}

          page(
            conn,
            s.member,
            Html.confirm_page("delete_plan", fields, plan.name, csrf(), length(plan.steps))
          )
      end
    end)
  end

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

          # REQ-160 (CP-014 A): which account an item goes through; empty clears it
          "attach" ->
            &Findependence.Attach.attach(
              &1,
              m,
              p["item"],
              if(p["account"] in [nil, ""], do: nil, else: p["account"])
            )

          "unlink" ->
            &Alignment.unlink(&1, m, p["item"], p["value"])

          "withdraw" ->
            &Household.withdraw(&1, m, to_int(p["proposal"]))

          # v0.3 (REQ-142, REQ-144)
          "remove_step" ->
            &Findependence.Plans.remove_step(&1, m, p["plan"], to_int(p["n"]))

          "delete_plan" ->
            &Findependence.Plans.delete_plan(&1, m, p["plan"])

          "mark" ->
            &Findependence.Plans.mark(&1, m, p["item"], p["job"])

          "unmark" ->
            &Findependence.Plans.unmark(&1, m, p["item"], p["job"])

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
          |> put_private(:fv_changed, true)
          |> put_session(:flash, message)
          |> redirect(return_to(params["return"], s2.household, s.member))
        end

      {:error, reason, s2} ->
        Sessions.update(token, s2)
        conn = put_private(conn, :fv_refused, reason)
        error = {:error, Html.error_text(reason)}
        waiting = Html.waiting_count(s2.household, s.member)

        body =
          case return_to(params["return"], s2.household, s.member) do
            "/items/" <> id -> Html.item_page(s2.household, s.member, id, csrf(), error)
            "/leave" -> Html.leave_page(s2.household, s.member, csrf(), error)
            "/plans" -> Html.plans_page(s2.household, s.member, csrf(), error)
            "/goals" -> Html.goals_page(s2.household, s.member, csrf(), error)
            "/bring-in" -> Html.bring_in_page(csrf(), error)
            "/retirement" -> Html.retirement_page(s2.household, s.member, csrf(), today(), error)
            "/plans/" <> id -> Html.plan_page(s2.household, s.member, id, csrf(), today(), error)
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
  defp return_to("/plans", _h, _m), do: "/plans"
  defp return_to("/goals", _h, _m), do: "/goals"
  defp return_to("/retirement", _h, _m), do: "/retirement"

  # a plan page only for a plan this member has (plans are private, so this can't reveal anything)
  defp return_to("/plans/" <> id = path, h, m) do
    if Map.has_key?(Findependence.Plans.plans(h, m), id), do: path, else: "/plans"
  end

  defp return_to(_, _h, _m), do: "/"

  defp pop_flash(conn) do
    case get_session(conn, :flash) do
      nil -> {conn, nil}
      text -> {delete_session(conn, :flash), {:ok, text}}
    end
  end

  # UX-004 H3: an unknown address still gets the page, with a way home (and the 404 status)
  match _ do
    member =
      case current(conn) do
        {:ok, _token, s} -> s.member
        _ -> nil
      end

    body =
      ~s(<section class=card><h2>That page doesn't exist</h2><p><a href="/">Go to the home page</a></p></section>)

    page(conn, member, body, 404)
  end

  # ---------------------------------------------------------------------------
  # Pages

  defp members, do: Store.vault() |> FindependenceApp.Vault.members()

  # UX-003: colours, focus, control heights, radii, and type sizes are tokens; nothing animates
  # (state changes are new pages that say what happened, so no transitions or animations are used).
  # UX-005: forced colours drop fills and shadows but keep borders, so each state also has a border there.
  @css """
  :root{--ink:#1d2330;--muted:#5b6475;--line:#d9dde5;--bg:#f6f7f9;--card:#fff;--accent:#1f5fbf;--ok:#1b6b3a;--err:#a4262c
  ;--focus:#1d2330;--control-border:#7b8494;--attention:#9a7300;--attention-bg:#fff6dc;--attention-ink:#6b4e00
  ;--err-bg:#fde8e8;--ok-bg:#e6f4ea;--info-bg:#e8eef9;--info-ink:#1d3f7a
  ;--fs-xs:.8rem;--fs-sm:.875rem;--fs-body:1rem;--fs-h2:1.15rem;--fs-lg:1.25rem;--fs-title:1.4rem
  ;--control-h:2.5rem;--control-h-sm:2rem;--r-surface:10px;--r-message:8px;--r-control:6px;--r-pill:999px;--column:56rem}
  *{box-sizing:border-box}
  body{margin:0;font:var(--fs-body)/1.5 system-ui,-apple-system,"Segoe UI",sans-serif;color:var(--ink);background:var(--bg)}
  :where(a:link,a:visited){color:var(--accent)}a{text-underline-offset:.15em}
  header{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:.5rem 1rem;padding:.75rem max(1rem,calc((100% - var(--column))/2 + 1rem));background:var(--card);border-bottom:1px solid var(--line)}
  header h1{font-size:var(--fs-lg);margin:0}header h1 a{color:inherit;text-decoration:none}.who{font-weight:600}
  header form.inline{display:flex;flex-wrap:wrap;justify-content:flex-end;align-items:center;gap:.25rem .5rem;margin:0 0 0 auto}
  main,footer{max-width:var(--column);margin:0 auto;padding:1rem}
  .card{background:var(--card);border:1px solid var(--line);border-radius:var(--r-surface);padding:1rem 1.25rem;margin:0 0 1rem}
  .card>:first-child{margin-top:0}.card>:last-child{margin-bottom:0}.scroll:last-child>table{margin-bottom:0}
  .card.warn{border-color:var(--err)}
  h2{font-size:var(--fs-h2);margin:.25rem 0 .5rem}h3{font-size:var(--fs-body);margin:1rem 0 .25rem}
  .back~section:first-of-type>h2{font-size:var(--fs-title)}
  .hint,.muted td{color:var(--muted)}.hint{font-size:var(--fs-sm)}.empty{color:var(--muted);font-style:italic}
  .scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;margin:.5rem 0}
  th,td{border-bottom:1px solid var(--line);padding:.4rem .5rem;text-align:left;vertical-align:top}
  th{font-size:var(--fs-sm);color:var(--muted);font-weight:600}
  .num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}th.num{white-space:normal}
  form{margin:.5rem 0}form.row{display:flex;flex-wrap:wrap;gap:.5rem 1rem;align-items:flex-start}form.row p{margin:0}
  .inline{display:inline;margin:0 .25rem 0 0}
  label{display:block;font-size:var(--fs-sm);color:var(--muted)}label.check{display:inline-block;margin-right:1rem;color:var(--ink)}
  input,select{font:inherit;height:var(--control-h);padding:.4rem .5rem;border:1px solid var(--control-border);border-radius:var(--r-control);background-color:var(--card);color:var(--ink);min-width:10rem;max-width:100%}
  input[type=checkbox],input[type=radio]{min-width:0;height:auto;padding:0}
  button{font:inherit;min-height:var(--control-h);padding:.4rem .8rem;border-radius:var(--r-control);border:1px solid var(--accent);background:var(--accent);color:#fff;cursor:pointer}
  a.button-link{display:inline-flex;align-items:center;min-height:var(--control-h-sm);padding:.2rem .6rem;font-size:var(--fs-sm);border:1px solid var(--accent);border-radius:var(--r-control);color:var(--accent);text-decoration:none;margin-right:.25rem}
  .inline button,td button{min-height:var(--control-h-sm);background:var(--card);color:var(--accent);padding:.2rem .6rem;font-size:var(--fs-sm)}
  button.danger{border-color:var(--err);background:var(--card);color:var(--err)}.card.warn button.danger{background:var(--err);color:#fff}
  .badge{display:inline-block;font-size:var(--fs-xs);font-weight:600;padding:.1rem .5rem;border-radius:var(--r-pill);background:var(--attention-bg);color:var(--attention-ink);text-decoration:none;margin-right:.5rem}
  header .badge{margin-right:0}
  .card.attention{border-color:var(--attention);border-inline-start-width:4px;padding-inline-start:calc(1.25rem - 3px)}
  .amount-big{font-size:var(--fs-lg);font-variant-numeric:tabular-nums;margin:.25rem 0}
  .field-error{display:block;margin:.25rem 0 0;color:var(--err);font-size:var(--fs-sm)}
  fieldset.direction{border:0;margin:0;padding:0;display:flex;gap:.25rem 1rem;align-items:center}fieldset.direction>*{line-height:var(--control-h)}fieldset.direction legend{float:left;margin-right:.5rem;font-size:var(--fs-sm);color:var(--muted)}
  input[aria-invalid=true],select[aria-invalid=true]{border-color:var(--err);box-shadow:0 0 0 1px var(--err)}
  :focus-visible{outline:3px solid var(--focus);outline-offset:2px}
  input[type=date]:focus,input[type=date]:focus-within{outline:3px solid var(--focus);outline-offset:2px}
  fieldset{border:1px solid var(--line);border-radius:var(--r-control);margin:.5rem 0}
  .checks{display:grid;grid-template-columns:repeat(auto-fill,9rem);gap:.35rem 1rem}.checks label.check{display:flex;gap:.35rem;align-items:baseline;margin-right:0}.checks input{flex:none}
  ul.plain{list-style:none;padding:0}ul.plain li{padding:.35rem 0;border-bottom:1px solid var(--line)}ul.plain li:last-child{border-bottom:0}
  details{margin-top:.25rem}summary{cursor:pointer;color:var(--accent)}
  .msg{padding:.6rem .9rem;border-radius:var(--r-message);margin:0 0 1rem}.msg.ok{background:var(--ok-bg);color:var(--ok)}.msg.err{background:var(--err-bg);color:var(--err)}.msg.info{background:var(--info-bg);color:var(--info-ink)}
  .below{display:inline-block;font-size:var(--fs-xs);font-weight:600;padding:0 .4rem;border-radius:var(--r-pill);background:var(--err-bg);color:var(--err)}
  .neg{display:inline-flex;flex-direction:row-reverse;align-items:baseline;gap:.5rem;white-space:nowrap}
  .nowrap{white-space:nowrap}
  .field-hint{display:block;margin-top:.15rem}
  .inline button.primary{background:var(--accent);color:#fff;min-height:var(--control-h);padding:.4rem .8rem;font-size:var(--fs-body)}
  .phone-only{display:none}
  @media (min-width:40.01rem){form.row>button,form.row>fieldset.direction{margin-top:calc(var(--fs-sm)*1.5)}}
  @media (max-width:40rem){
  header{padding-inline:.5rem}
  main{padding:.5rem}.card{padding:.75rem}.card.attention{padding-inline-start:calc(.75rem - 3px)}
  input:not([type=checkbox]):not([type=radio]),select{min-width:0;width:100%}form.row p{flex:1 1 100%}
  table.stack thead{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
  table.stack tbody tr{display:block;border-bottom:1px solid var(--line);padding:.5rem 0}
  table.stack td{display:flex;gap:.75rem;border:0;padding:.15rem 0}
  table.stack td[data-label]::before{content:attr(data-label);content:attr(data-label) / "";flex:0 0 7.5rem;white-space:normal;color:var(--muted);font-size:var(--fs-sm)}
  table.stack td.num{text-align:left;white-space:normal}
  table.stack td{min-width:0;overflow-wrap:anywhere}
  .phone-only{display:inline}
  .checks{grid-template-columns:repeat(2,minmax(0,1fr))}
  table.stack.compact tbody tr{display:grid;grid-template-columns:auto minmax(0,1fr) auto;column-gap:.5rem;row-gap:.1rem;padding:.45rem 0}
  table.stack.compact td{display:block;padding:0}
  table.stack.compact td[data-label]::before{content:none}
  table.stack.compact td:first-child{grid-column:1 / 3;grid-row:1}
  table.stack.compact td.num{grid-column:3;grid-row:1;text-align:right}
  table.stack.compact td.freq{display:none}
  table.stack.compact td.meta{grid-row:2;font-size:var(--fs-sm);color:var(--muted)}
  table.stack.compact td.owner{grid-column:1}
  table.stack.compact td.owner::before{content:"Owned by ";content:"Owned by " / ""}
  table.stack.compact td.vis{grid-column:2 / 4}
  table.stack.compact td.vis::before{content:"· ";content:"· " / ""}
  table.dist tbody tr{display:grid;grid-template-columns:1fr 1fr;column-gap:.75rem;row-gap:.1rem;padding:.45rem 0}
  table.dist td{display:block;padding:0;font-size:var(--fs-sm)}
  table.dist td:first-child{grid-column:1 / -1;font-size:var(--fs-body)}
  table.dist td:first-child::before{content:none}
  table.dist td[data-short]::before{content:attr(data-short) " ";content:attr(data-short) " " / "";color:var(--muted)}
  table.dist td.num{white-space:nowrap;overflow-wrap:normal}
  table.dist td.num::before{white-space:normal}
  table.stack td.num .neg{display:inline;white-space:normal}
  table.dist td.num .below{display:table;margin-top:.1rem}
  table.flow tbody tr{display:grid;grid-template-columns:auto 1fr;column-gap:.75rem;row-gap:.15rem;padding:.45rem 0}
  table.flow td{display:block;padding:0}
  table.flow td.fdate,table.flow td.fwhat{grid-column:1 / -1}
  table.flow td.fdate::before,table.flow td.fwhat::before{content:none}
  table.flow td.fnet,table.flow td.fbal{font-size:var(--fs-sm)}
  table.flow td.fnet::before{content:"Net ";content:"Net " / "";color:var(--muted)}
  table.flow td.fbal::before{content:"· Balance after ";content:"· Balance after " / "";color:var(--muted)}
  table.flow.partial td.fbal::before{content:"· Your part after ";content:"· Your part after " / ""}
  table.flow td.fbal .below{display:table;margin:.1rem 0 0 auto}
  }
  @media (forced-colors:active){
  input[aria-invalid=true],select[aria-invalid=true]{border-width:3px}
  .msg,.below,.badge{border:1px solid CanvasText}
  .card.attention,.card.warn{border-width:3px}
  button,.card.warn button.danger{border-width:2px}.inline button:not(.primary),td button,button.danger{border-width:1px}
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

        conn =
          if conn.method == "POST", do: put_private(conn, :fv_refused, :idle_lock), else: conn

        conn |> configure_session(drop: true) |> redirect("/?locked=" <> why)

      # WI-032: the session is gone (someone else unlocked, or the app restarted). A form sent now is
      # lost, so say so; the notice doesn't say why, which could reveal that someone else used the device.
      :locked ->
        to = if conn.method == "POST", do: "/?locked=replaced", else: "/"

        conn =
          if conn.method == "POST", do: put_private(conn, :fv_refused, :no_session), else: conn

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
  UX-004 P4 (CP-010 A: say so): the two things that can't be recovered, stated where they matter,
  on the unlock page and at setup.
  """
  def limits_notice,
    do:
      "A forgotten passphrase can't be recovered. There's no backup: if this device is lost or breaks, what's here is gone. Each person can save their own record from Leaving, on the home page."

  @doc """
  Today's date on this device, for dates in forms and the cash-flow view. Tests may fix it with
  `Application.put_env(:findependence_app, :today, ~D[...])`.
  """
  def today,
    do:
      Application.get_env(:findependence_app, :today) ||
        NaiveDateTime.to_date(NaiveDateTime.local_now())

  defp redirect(conn, to), do: conn |> put_resp_header("location", to) |> send_resp(303, "")

  # Every form gets the session's CSRF token and a one-time form token (REQ-165).
  defp csrf,
    do:
      "<input type=hidden name=_csrf_token value=\"#{Plug.CSRFProtection.get_csrf_token()}\"><input type=hidden name=_form value=\"#{new_id()}\">"

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
