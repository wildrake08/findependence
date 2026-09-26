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
  alias Findependence.{Alignment, Exit, Household, Ledger, View}

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
      {:ok, _token, s} -> page(conn, s.member, home(Store.refresh(s)))
      :locked -> page(conn, nil, login_form())
    end
  end

  post "/login" do
    %{"member" => m, "passphrase" => p} = conn.body_params

    case Store.open(m, p) do
      {:ok, s} ->
        token = Sessions.put(s)
        conn |> configure_session(renew: true) |> put_session(:token, token) |> redirect("/")

      {:error, :bad_credentials} ->
        page(conn, nil, "<p class=err>Wrong name or passphrase.</p>" <> login_form(), 401)
    end
  end

  post "/logout" do
    with {:ok, token, _} <- current(conn), do: Sessions.drop(token)
    conn |> configure_session(drop: true) |> redirect("/")
  end

  get "/export" do
    with_session(conn, fn s ->
      s = Store.refresh(s)

      body =
        "<h2>Your export</h2><pre>" <>
          esc(inspect(Exit.export(s.household, s.member), pretty: true, limit: :infinity)) <>
          "</pre>"

      page(conn, s.member, body)
    end)
  end

  post "/act/:action" do
    with_session(conn, fn s ->
      m = s.member
      p = conn.body_params

      op =
        case action do
          "add_item" ->
            &Household.add_item(&1, m, new_id(), %{note: p["note"], amount: to_int(p["amount"])})

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
              String.split(p["owners"] || "", ~r/[\s,]+/, trim: true)
            )

          "consent" ->
            &Household.consent(&1, m, to_int(p["proposal"]))

          "relinquish" ->
            &Household.relinquish(&1, m, p["item"])

          "delete" ->
            &Exit.delete(&1, m, p["item"])

          "link" ->
            &Alignment.link(&1, m, p["item"], p["value"])

          "unlink" ->
            &Alignment.unlink(&1, m, p["item"], p["value"])

          "leave" ->
            &Exit.leave(&1, m)

          _ ->
            fn _ -> {:error, :unknown_action} end
        end

      {:ok, token, _} = current(conn)

      case Store.apply(s, op) do
        {:ok, s2} ->
          if action == "leave" do
            Sessions.drop(token)
            conn |> configure_session(drop: true) |> redirect("/")
          else
            Sessions.update(token, s2)
            redirect(conn, "/")
          end

        {:error, reason, s2} ->
          Sessions.update(token, s2)
          page(conn, m, "<p class=err>Not done: #{esc(inspect(reason))}</p>" <> home(s2), 422)
      end
    end)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # ---------------------------------------------------------------------------
  # Pages

  defp login_form do
    members = Store.vault() |> FindependenceApp.Vault.members()
    options = Enum.map_join(members, "", &"<option>#{esc(&1)}</option>")

    """
    <h2>Unlock</h2>
    <form method=post action="/login">#{csrf()}
    <label>Who are you? <select name=member>#{options}</select></label>
    <label>Passphrase <input type=password name=passphrase autocomplete=off required></label>
    <button>Unlock</button></form>
    <p class=hint>Only one person uses this device at a time. Lock it when you are done.</p>
    """
  end

  defp home(s) do
    h = s.household
    m = s.member
    visible = View.visible_items(h, m)
    {values, items} = Enum.split_with(visible, &(Map.get(&1.attrs, :kind) == :value))
    others = h.members |> MapSet.delete(m) |> Enum.sort()
    dist = Alignment.distribution(h, m)

    """
    <section><h2>Your items and items shared with you</h2>#{table_items(items, m, h)}
    <form method=post action="/act/add_item">#{csrf()}<input name=note placeholder="What is it?" required>
    <input name=amount type=number placeholder="Amount (+ in, - out)"><button>Add item</button></form></section>

    <section><h2>What you value</h2><p class=hint>In your own words. Nothing here is judged.</p>
    #{table_values(values, m)}
    <form method=post action="/act/add_value">#{csrf()}<input name=label placeholder="Something you value" required><button>Add value</button></form></section>

    <section><h2>How your visible activity relates to your values</h2>
    <p class=hint>Sums and counts only. An item linked to two values counts toward both.</p>
    #{table_distribution(dist, values)}
    #{link_form(items, values)}
    #{links_list(Alignment.links(h, m))}</section>

    <section><h2>Waiting for your consent</h2>#{pending_list(Household.pending(h, m))}</section>

    <section><h2>Sharing</h2>#{share_forms(items ++ values, m, others)}</section>

    <section><h2>Leaving</h2><p><a href="/export">See your export</a>: everything you own, with its history.</p>
    #{if Enum.any?(visible, &(m in &1.owners)), do: "<p class=hint>To leave the household, first relinquish, transfer, or delete what you own.</p>", else: action_button("leave", %{}, "Leave the household")}</section>
    """
  end

  defp table_items([], _m, _h), do: "<p class=hint>Nothing yet.</p>"

  defp table_items(items, m, h) do
    rows =
      Enum.map_join(items, "", fn i ->
        owner? = m in i.owners
        ledger = if owner?, do: ledger_text(h, m, i.id), else: ""

        "<tr><td>#{esc(i.attrs[:note])}</td><td>#{esc(i.attrs[:amount])}</td><td>#{esc(Enum.join(i.owners, ", "))}</td>" <>
          "<td>#{if owner?, do: esc(Enum.join(Map.get(i, :grantees, []), ", ")), else: "(shared with you)"}</td>" <>
          "<td>#{item_actions(i, owner?)}#{ledger}</td></tr>"
      end)

    "<table><tr><th>Item</th><th>Amount</th><th>Owners</th><th>Also visible to</th><th></th></tr>#{rows}</table>"
  end

  defp table_values([], _m), do: "<p class=hint>No values yet.</p>"

  defp table_values(values, m) do
    rows =
      Enum.map_join(values, "", fn v ->
        "<tr><td>#{esc(v.attrs[:label])}</td><td>#{esc(Enum.join(v.owners, ", "))}</td><td>#{item_actions(v, m in v.owners)}</td></tr>"
      end)

    "<table><tr><th>Value</th><th>Held by</th><th></th></tr>#{rows}</table>"
  end

  defp table_distribution(%{by_value: bv, unlinked: u}, values) do
    label = Map.new(values, &{&1.id, &1.attrs[:label]})

    rows =
      Enum.map_join(Enum.sort_by(bv, fn {id, _} -> label[id] end), "", fn {id,
                                                                           %{sum: s, count: c}} ->
        "<tr><td>#{esc(label[id])}</td><td>#{s}</td><td>#{c}</td></tr>"
      end)

    "<table><tr><th>Value</th><th>Sum</th><th>Items</th></tr>#{rows}<tr><td><em>Not linked to a value</em></td><td>#{u.sum}</td><td>#{u.count}</td></tr></table>"
  end

  defp link_form([], _), do: ""
  defp link_form(_, []), do: ""

  defp link_form(items, values) do
    """
    <form method=post action="/act/link">#{csrf()}Link <select name=item>#{opts(items, :note)}</select>
    to <select name=value>#{opts(values, :label)}</select><button>Link</button></form>
    """
  end

  defp links_list([]), do: ""

  defp links_list(links) do
    "<p class=hint>Your links are visible only to you.</p><ul>" <>
      Enum.map_join(links, "", fn {i, v} ->
        "<li>#{esc(i)} → #{esc(v)} #{action_button("unlink", %{"item" => i, "value" => v}, "Unlink")}</li>"
      end) <>
      "</ul>"
  end

  defp pending_list([]), do: "<p class=hint>Nothing waiting.</p>"

  defp pending_list(pending) do
    "<ul>" <>
      Enum.map_join(pending, "", fn p ->
        what = if a = p[:attrs], do: " (#{esc(a[:label] || a[:note])})", else: ""

        "<li>#{esc(inspect(p.change))} on #{esc(p.item_id)}#{what}, agreed by #{esc(Enum.join(p.consents, ", "))} #{action_button("consent", %{"proposal" => p.id}, "Agree")}</li>"
      end) <> "</ul>"
  end

  defp share_forms([], _m, _others), do: "<p class=hint>Nothing to share yet.</p>"

  defp share_forms(entries, m, others) do
    owned = Enum.filter(entries, &(m in &1.owners))
    who = Enum.map_join(others, "", &"<option>#{esc(&1)}</option>")

    if owned == [] or others == [] do
      "<p class=hint>Nothing you own to share.</p>"
    else
      """
      <form method=post action="/act/grant">#{csrf()}Let <select name=member>#{who}</select> see
      <select name=item>#{opts(owned, :note, :label)}</select><button>Propose</button></form>
      <form method=post action="/act/revoke">#{csrf()}Stop <select name=member>#{who}</select> seeing
      <select name=item>#{opts(owned, :note, :label)}</select><button>Revoke</button></form>
      <form method=post action="/act/owners">#{csrf()}Set owners of <select name=item>#{opts(owned, :note, :label)}</select>
      to <input name=owners placeholder="names, comma-separated"><button>Propose</button></form>
      """
    end
  end

  defp item_actions(i, true) do
    action_button("relinquish", %{"item" => i.id}, "Stop owning") <>
      action_button("delete", %{"item" => i.id}, "Delete")
  end

  defp item_actions(_i, false), do: ""

  defp ledger_text(h, m, id) do
    case Ledger.read(h, m, id) do
      {:ok, entries} ->
        "<details><summary>History</summary><ol>" <>
          Enum.map_join(
            entries,
            "",
            &"<li>#{esc(&1.event)} by #{esc(Enum.join(&1.by, ", "))}</li>"
          ) <> "</ol></details>"

      _ ->
        ""
    end
  end

  defp action_button(action, fields, label) do
    hidden =
      Enum.map_join(fields, "", fn {k, v} ->
        "<input type=hidden name=#{k} value=\"#{esc(v)}\">"
      end)

    "<form class=inline method=post action=\"/act/#{action}\">#{csrf()}#{hidden}<button>#{esc(label)}</button></form>"
  end

  defp opts(entries, key, alt \\ nil) do
    Enum.map_join(entries, "", fn e ->
      text = e.attrs[key] || (alt && e.attrs[alt]) || e.id
      "<option value=\"#{esc(e.id)}\">#{esc(text)}</option>"
    end)
  end

  defp page(conn, member, body, status \\ 200) do
    who =
      if member,
        do:
          "<form class=inline method=post action=\"/logout\">#{csrf()}<span>#{esc(member)}</span> <button>Lock</button></form>",
        else: ""

    html = """
    <!doctype html><html lang=en><head><meta charset=utf-8><title>Findependence (local)</title>
    <style>body{font:15px/1.5 system-ui,sans-serif;max-width:60rem;margin:1rem auto;padding:0 1rem}
    table{border-collapse:collapse;margin:.5rem 0}td,th{border-bottom:1px solid #ccc;padding:.25rem .5rem;text-align:left}
    .hint{color:#555}.err{color:#a00}.inline{display:inline}section{margin:1.5rem 0}header{display:flex;justify-content:space-between}</style>
    </head><body><header><h1>Findependence</h1>#{who}</header>
    <p class=hint>Everything stays on this device. Nothing is sent anywhere.</p>#{body}</body></html>
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

  defp with_session(conn, fun) do
    case current(conn) do
      {:ok, _token, s} -> fun.(s)
      :locked -> conn |> configure_session(drop: true) |> redirect("/")
    end
  end

  defp redirect(conn, to), do: conn |> put_resp_header("location", to) |> send_resp(303, "")

  defp csrf,
    do: "<input type=hidden name=_csrf_token value=\"#{Plug.CSRFProtection.get_csrf_token()}\">"

  defp esc(nil), do: ""
  defp esc(v) when is_binary(v), do: v |> Plug.HTML.html_escape()
  defp esc(v), do: v |> to_string() |> Plug.HTML.html_escape()
  defp new_id, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  defp to_int(nil), do: 0
  defp to_int(""), do: 0

  defp to_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end
end
