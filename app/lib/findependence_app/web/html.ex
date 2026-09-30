defmodule FindependenceApp.Web.Html do
  @moduledoc """
  Page rendering for the local interface (WI-013). Pure functions of a member's own view of the
  household; nothing here reads data the member cannot see. Every user-supplied string passes
  through `esc/1`.
  """

  # WI-066 (REV-087): every domain read goes through a context, with a read scope over the member's view.
  alias FindependenceShared.{
    GoalWords,
    PlanWords,
    PortabilityWords,
    Words,
    Balances,
    CashFlow,
    Households,
    Items,
    Planning,
    Scope,
    Values
  }

  defp sc(h, m), do: Scope.read(h, m)

  # ---------------------------------------------------------------------------
  # Plain-language text

  # The failure messages are defined once, in shared/, for both forms (WI-075, REV-100 H3).

  @doc """
  WI-020: a warning when the household file shows signs of being changed outside the app. Plain
  language, with no item names, since an altered file can't be trusted to name things.
  """
  def integrity_banner([]), do: ""

  def integrity_banner(issues) do
    # WI-079: worded once, in shared/, for both forms; signature problems add a line
    {heading, lines} = Words.integrity_notice(issues, :file)

    ~s(<section class="card warn" role="alert"><h2>#{esc(heading)}</h2>) <>
      Enum.map_join(lines, "", &"<p>#{esc(&1)}</p>") <> "</section>\n"
  end

  @doc """
  WI-079: on an item's page, a neutral note when parts of it were saved before Findependence began signing
  changes (`parts` from `Identity.written_before_signing/2`); nothing otherwise.
  """
  def signing_note(parts) do
    case Words.before_signing_note(parts) do
      nil -> ""
      text -> ~s(<p class="msg info" role="note">#{esc(text)}</p>\n)
    end
  end

  defdelegate error_text(reason), to: FindependenceShared.Messages
  @doc false
  defdelegate error_reasons, to: FindependenceShared.Messages

  # ---------------------------------------------------------------------------
  # Pages

  def login(members, csrf, error \\ nil, notice \\ nil) do
    options = Enum.map_join(members, "", &"<option>#{esc(&1)}</option>")

    """
    <p class="msg info" role="note">#{esc(FindependenceApp.Web.release_notice())}</p>
    #{lock_notice(notice)}
    #{if error, do: ~s(<p class="msg err" role="alert">#{esc(error)}</p>), else: ""}
    <section class=card><h2>Unlock</h2>
    <form method=post action="/login">#{csrf}
    <p><label for=member>Who are you?</label><select id=member name=member>#{options}</select></p>
    <p><label for=pass>Your passphrase</label><input id=pass type=password name=passphrase autocomplete=off required></p>
    <button>Unlock</button></form>
    <p class=hint>One person at a time. Press <b>Lock</b> when you're done; it also locks itself after 15 minutes.</p>
    <p class=hint>#{esc(FindependenceApp.Web.limits_notice())}</p></section>
    """
  end

  # UX-001 R4
  defp lock_notice(:idle),
    do:
      ~s(<p class="msg info" role="status">Locked after 15 minutes without use. Unlock to carry on.</p>)

  defp lock_notice(:idle_action),
    do:
      ~s(<p class="msg info" role="status">Locked after 15 minutes without use. Your last action was not saved. Unlock and do it again.</p>)

  defp lock_notice(:idle_saved),
    do:
      ~s(<p class="msg info" role="status">Locked after 15 minutes without use. That was already saved. Unlock to carry on.</p>)

  defp lock_notice(:left),
    do:
      ~s(<p class="msg info" role="status">You have left the household. That was already done.</p>)

  defp lock_notice(:replaced),
    do:
      ~s(<p class="msg info" role="status">You were locked out, so your last action was not saved. Unlock and do it again.</p>)

  defp lock_notice(_), do: ""

  # UX-001 R1: the home page lists items and values compactly, each linking to its own page; no
  # per-item action forms here. R7: anything waiting for the member comes first. R9: the words used
  @totals_hint "Totals of what you can see, by what you've linked it to. Items that repeat are shown per month (weekly, every-two-weeks, and yearly amounts are converted); one-off items are shown apart. To link an item, open it. Only you can see your links, and an item linked to two values counts toward both."

  # here follow the glossary in `FindependenceApp.Web.Glossary`.
  def home(h, m, csrf, message \\ nil, form \\ %{}) do
    visible = Items.visible(sc(h, m))
    # CAP-010: accounts and debts have their own list
    # CAP-010: accounts and debts have their own list; shared plans live on the plans page
    {balances, visible_rest} =
      visible
      |> Enum.reject(&Planning.plan?/1)
      |> Enum.split_with(&Balances.balance?/1)

    {values, items} = Enum.split_with(visible_rest, &value?/1)
    names = names(h, m)
    owners_of = owners_of(visible)
    {mine, theirs} = Items.pending(sc(h, m)) |> Enum.split_with(&(m not in &1.consents))

    """
    #{message(message)}
    #{if mine != [], do: ~s(<section class="card attention" id=waiting><h2>Waiting for you</h2>#{pending_list(mine, names, owners_of, m, csrf, :respond)}</section>), else: ""}
    #{coming_up_card(h, m, FindependenceApp.Web.today())}
    <section class=card><h2>Your items</h2>
    <p class=hint>Money in and out: items you own, and items others share with you. Open one to share it, change who owns it, or link it to a value.</p>
    #{thing_list(items, m, mine ++ theirs, :item)}
    #{add_item_form(csrf, form)}</section>

    <section class=card><h2>What matters to you</h2>
    <p class=hint>Your values, in your own words. Nothing here is scored or judged, and only you decide who can see them.</p>
    #{thing_list(values, m, mine ++ theirs, :value)}
    <form method=post action="/act/add_value" class=row>#{csrf}
    <p><label for=label>A value</label><input id=label name=label required placeholder="e.g. Time with the kids"></p>
    <button>Add value</button></form></section>

    #{balances_card(h, m, balances)}

    <section class=card><h2>Your money and what matters to you</h2>
    #{if items == [], do: ~s(<p class=empty>Totals appear once you add items.</p>), else: ~s(<p class=hint>#{@totals_hint}</p>) <> distribution(Values.distribution(sc(h, m)), values)}</section>

    #{if theirs != [], do: ~s(<section class=card><h2>Waiting for others</h2>#{pending_list(theirs, names, owners_of, m, csrf, :waiting)}</section>), else: ""}

    <section class=card><h2>Leaving</h2>
    <p><a href="/export">See everything you'd take with you</a>, and save it as a file. <a href="/bring-in">Bring in a file you saved</a> from another household.</p>
    <p><a class="button-link" href="/leave">Leave the household…</a></p></section>
    """
  end

  @doc "How many changes are waiting for this member's answer (UX-001 R7: shown in the header)."
  def waiting_count(h, m), do: Items.pending(sc(h, m)) |> Enum.count(&(m not in &1.consents))

  # A compact, action-free list: each item or value links to its own page.
  defp thing_list([], _m, _pending, :item), do: "<p class=empty>No items yet.</p>"
  defp thing_list([], _m, _pending, :value), do: "<p class=empty>No values yet.</p>"

  defp thing_list(things, m, pending, kind) do
    rows =
      things
      |> Enum.sort_by(&String.downcase(title(&1)))
      |> Enum.map_join("", fn i ->
        waiting = Enum.count(pending, &(&1.item_id == i.id))
        badge = if waiting > 0, do: ~s( <span class=badge>#{waiting} waiting</span>), else: ""

        # UX-003 C10: the figure and how often it happens in their own cells, so figures line up;
        # phones keep them together in one cell, as before (only one copy is ever displayed)
        amount =
          if kind == :item,
            do:
              ~s(<td role=cell class=num data-label="Amount">#{esc(figure_text(i.attrs))}<span class=phone-only> #{esc(frequency_text(i.attrs))}</span></td><td role=cell class=freq data-label="How often">#{esc(frequency_text(i.attrs))}</td>),
            else: ""

        """
        <tr role=row><td role=cell data-label="#{if kind == :item, do: "Item", else: "Value"}"><a href="/items/#{esc(i.id)}"><b>#{esc(title(i))}</b></a>#{badge}</td>#{amount}
        <td role=cell class="meta owner" data-label="Owned by">#{esc(people(i.owners, m))}</td>
        <td role=cell class="meta vis" data-label="Who else can see it">#{visibility_summary(i, m)}</td></tr>
        """
      end)

    head =
      if kind == :item,
        do: ["Item", {"Amount", :num}, "How often", "Owned by", "Who else can see it"],
        else: ["Value", "Owned by", "Who else can see it"]

    # UX-001 R10: explicit roles, because the phone layout restyles the table with display:block,
    # which can remove its table semantics in some browsers; the header row stays readable to
    # screen readers while hidden on screen.
    head = Enum.map_join(head, "", &th/1)
    caption = if kind == :item, do: "Your items", else: "Your values"

    ~s(<div class=scroll><table class="stack compact" role=table aria-label="#{caption}"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div>)
  end

  defp visibility_summary(i, m) do
    cond do
      m not in i.owners -> "Shared with you"
      Map.get(i, :grantees, []) == [] -> "Only the owners"
      # On phones there is no column header on screen, so the names say what they mean (WI-027).
      true -> esc(people(i.grantees, m)) <> "<span class=phone-only> can see it</span>"
    end
  end

  @doc """
  UX-001 R1: everything about one item or value on one page. Owners see who can see it, sharing, owners,
  what is waiting, links, history, and how to let go. Someone it is shared with sees it, who shared
  it, and their own links. Returns `nil` if the member can't see it.
  """
  def item_page(h, m, id, csrf, message \\ nil, form \\ %{}) do
    case Items.get(sc(h, m), id) do
      {:ok, i} ->
        cond do
          Balances.balance?(i) -> balance_page(h, m, i, csrf, message, form)
          Planning.plan?(i) -> shared_plan_page(h, m, i, csrf, message)
          true -> money_item_page(h, m, i, id, csrf, message)
        end

      _ ->
        nil
    end
  end

  # CP-015 (REV-047): until amounts can change, say how to record a new one and what is lost
  @change_amount ~s(<p class=hint>Amounts can't be changed yet. For a new amount, add a new item with it and remove this one; its links and history don't carry over.</p>)

  # REQ-160 (CP-014 A): which cash account a money item goes through, for this member only
  defp account_section(h, m, i, fields) do
    accounts =
      Items.visible(sc(h, m))
      |> Enum.filter(&Balances.cash_account?/1)
      |> Enum.sort_by(&String.downcase(title(&1)))

    if value?(i) or accounts == [] do
      ""
    else
      current = Balances.attached(sc(h, m))[i.id]

      options =
        [~s(<option value=""#{if current == nil, do: " selected", else: ""}>Not said</option>)] ++
          Enum.map(accounts, fn a ->
            sel = if a.id == current, do: " selected", else: ""
            ~s(<option value="#{esc(a.id)}"#{sel}>#{esc(title(a))}</option>)
          end)

      owned? = m in i.owners

      rule =
        if owned?,
          do: "Until you choose, an item you own counts toward all your accounts.",
          else:
            "Shared with you, it counts in your Coming up and the next 12 months only once you choose its account."

      """
      <section class=card><h2>Which account does it go through?</h2>
      <p class=hint>Only you see this. #{rule}</p>
      <form method=post action="/act/attach" class=row>#{fields}<input type=hidden name=item value="#{esc(i.id)}">
      <p><label for=through>Account</label><select id=through name=account>#{Enum.join(options)}</select></p>
      <button>Save</button></form></section>
      """
    end
  end

  defp money_item_page(h, m, i, id, csrf, message) do
    # Every form on this page returns here (UX-001 R6).
    fields = csrf <> ~s(<input type=hidden name=return value="/items/#{esc(id)}">)
    owner? = m in i.owners
    visible = Items.visible(sc(h, m))
    names = names(h, m)
    owners_of = owners_of(visible)
    pending = Items.pending(sc(h, m)) |> Enum.filter(&(&1.item_id == id))
    others = Households.members(sc(h, m)) |> MapSet.delete(m) |> Enum.sort()

    """
    <p class=back><a href="/">← Everything</a></p>
    #{message(message)}
    <section class=card><h2>#{esc(title(i))}</h2>
    #{if value?(i), do: ~s(<p class=hint>A value.</p>), else: ~s(<p class="amount-big">#{esc(money_line(i.attrs))}</p>#{next_date_line(i)}#{per_month_hint(i.attrs)}#{if owner?, do: @change_amount, else: ""})}
    #{if owner?, do: owner_sections(i, m, others, pending, owners_of, names, fields), else: shared_with_me(i, m)}
    </section>
    #{links_section(h, i, m, visible, fields)}
    #{account_section(h, m, i, fields)}
    #{if owner?, do: depends_section(h, m, i, fields), else: ""}
    #{if owner?, do: history_section(h, m, i) <> let_go_section(i, fields), else: ""}
    """
  end

  # ---------------------------------------------------------------------------
  # v0.3: CAP-007 projection and plans, CAP-013 goals, CAP-005 shared plans (REQ-141..148)

  defp month_options(today, chosen) do
    CashFlow.months(today)
    |> Enum.map_join("", fn mo ->
      sel = if mo == chosen, do: " selected", else: ""
      ~s(<option value="#{mo}"#{sel}>#{month_text(mo)}</option>)
    end)
  end

  defp cash_cell(nil), do: ""

  # DEF-034 (WI-047): a figure and its pill are one unit, so the pill never wraps under the figure
  defp cash_cell(c) when c < 0, do: below_zero(c)

  defp cash_cell(c), do: esc(plain_amount(c))

  # REQ-139's mark, read after the figure; on wide screens drawn to its left (see .neg in the stylesheet)
  defp below_zero(c),
    do: ~s(<span class=neg>#{esc(plain_amount(c))} <span class=below>Below zero</span></span>)

  # UX-003 C2: a numeric column's header aligns with its figures. The explicit role is UX-001 R10's.
  defp th({label, :num}), do: ~s(<th role=columnheader scope=col class=num>#{label}</th>)
  defp th(label), do: ~s(<th role=columnheader scope=col>#{label}</th>)

  # UX-003 C6: a field's error, placed inside the field's own <p> right after its control
  defp field_error(field, message),
    do: ~s(<span class="field-error" id="#{field}-error" role="alert">#{esc(message)}</span>)

  # REQ-162 (DEF-048): says what the months count, including shared items attached to your accounts
  @assumptions """
  <p class=hint>How this is worked out: repeating items count at their per-month amount; one-off
  items count in their month when they have a date; cash starts from the latest balances of the
  accounts you can see; each debt grows by a month's interest and falls by its minimum payment. It
  counts items you own, and items shared with you that you've said go through your accounts, and
  nothing is advice.</p>
  """

  @doc "REQ-141: the next twelve months."
  def ahead_page(h, m, today) do
    p = CashFlow.project(sc(h, m), today)
    # UX-004 P2
    cash_label =
      if p.start && partial?(h, m, p.start.accounts),
        do: "Your part at the end",
        else: "Cash at the end"

    rows =
      Enum.map_join(p.months, "", fn r ->
        """
        <tr role=row><td role=cell class=fdate data-label="Month"><b>#{esc(month_text(r.month))}</b></td><td role=cell class=num data-label="In" data-short="In">#{esc(format_amount(r.in))}</td><td role=cell class=num data-label="Out" data-short="Out">#{esc(format_amount(r.out))}</td><td role=cell class=num data-label="Net" data-short="Net">#{esc(format_amount(r.net))}</td><td role=cell class=num data-label="#{cash_label}" data-short="#{cash_label}">#{cash_cell(r.cash)}</td></tr>
        """
      end)

    head =
      ["Month", {"In", :num}, {"Out", :num}, {"Net", :num}, {cash_label, :num}]
      |> Enum.map_join("", &th/1)

    start =
      case p.start do
        nil ->
          ~s(<p class=hint>To see cash month by month, <a href="/balances/new">add an account</a> and its balance.</p>)

        s ->
          ~s(<p class=hint>Cash starts from #{esc(people(Enum.map(s.accounts, &title(Items.lookup(sc(h, m), &1)))))}: #{esc(plain_amount(s.cash))}. #{esc(counted_note(h, m, s.accounts))}</p>)
      end

    """
    <p class=back><a href="/">← Everything</a></p>
    <section class=card><h2>The next 12 months</h2>
    #{start}
    <div class=scroll><table class="stack dist" role=table aria-label="The next 12 months"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div>
    #{@assumptions}
    <p class=links-row><a href="/plans">Compare with a plan</a> · <a href="/goals">Goals</a></p></section>
    #{debts_card(p.debts)}
    """
  end

  defp debts_card([]), do: ""

  defp debts_card(debts) do
    rows =
      Enum.map_join(debts, "", fn d ->
        name = if d.planned, do: "#{d.name} (plan, from #{month_text(d.from)})", else: d.name
        paid = if d.paid_off, do: month_text(d.paid_off), else: "Not within 12 months"

        """
        <tr role=row><td role=cell data-label="Debt">#{if d.id, do: ~s(<a href="/items/#{esc(d.id)}">#{esc(name)}</a>), else: esc(name)}</td><td role=cell class=num data-label="Now" data-short="Now">#{esc(plain_amount(d.balance))}</td><td role=cell class=num data-label="In 12 months" data-short="In 12 months">#{esc(plain_amount(List.last(d.months)))}</td><td role=cell class=num data-label="Interest over 12 months" data-short="Interest">#{esc(plain_amount(d.interest))}</td><td role=cell data-label="Paid off" data-short="Paid off">#{esc(paid)}</td></tr>
        """
      end)

    head =
      [
        "Debt",
        {"Now", :num},
        {"In 12 months", :num},
        {"Interest over 12 months", :num},
        "Paid off"
      ]
      |> Enum.map_join("", &th/1)

    """
    <section class=card><h2>Debts over the next 12 months</h2>
    <p class=hint>Paying each debt's minimum payment, at its latest rate.</p>
    <div class=scroll><table class="stack dist" role=table aria-label="Debts over the next 12 months"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div></section>
    """
  end

  @doc "REQ-142: the member's plans, and shared plans they own or are asked to join."
  def plans_page(h, m, csrf, message \\ nil) do
    mine =
      Planning.plans(sc(h, m))
      |> Enum.sort_by(fn {_, p} -> String.downcase(p.name) end)
      |> Enum.map_join("", fn {id, p} ->
        ~s(<li><a href="/plans/#{esc(id)}"><b>#{esc(p.name)}</b></a> <span class=hint>#{length(p.steps)} #{if length(p.steps) == 1, do: "step", else: "steps"}, private to you</span></li>)
      end)

    shared =
      Items.visible(sc(h, m))
      |> Enum.filter(&Planning.plan?/1)
      |> Enum.sort_by(&String.downcase(title(&1)))
      |> Enum.map_join("", fn i ->
        ~s(<li><a href="/items/#{esc(i.id)}"><b>#{esc(title(i))}</b></a> <span class=hint>shared plan, owned by #{esc(people(i.owners, m))}</span></li>)
      end)

    """
    <p class=back><a href="/">← Everything</a></p>
    #{message(message)}
    <section class=card><h2>Plans</h2>
    <p class=hint>A plan is a “what if”: switch off an income or a bill from a month, add a planned cost or income, or borrow. Plans are kept apart from what's real and never change your totals. Only you can see your plans unless you ask others to share one.</p>
    #{if mine == "", do: ~s(<p class=empty>No plans yet.</p>), else: "<ul class=plain>#{mine}</ul>"}
    <form method=post action="/act/new_plan" class=row>#{csrf}
    <p><label for=plan-name>New plan</label><input id=plan-name name=name required placeholder="e.g. If Dad's job stops"></p>
    <button>Start plan</button></form></section>
    #{if shared != "", do: ~s(<section class=card><h2>Shared plans</h2><ul class=plain>#{shared}</ul></section>), else: ""}
    """
  end

  # UX-002 R5: the answer in one or two sentences, before the months it comes from
  # an amount in running text never splits between its sign and its digits
  defp whole(cents), do: ~s(<span class=nowrap>#{esc(plain_amount(cents))}</span>)

  defp plan_summary(%{start: nil}, _with_plan), do: ""

  defp plan_summary(base, with_plan) do
    describe = fn months ->
      low = Enum.min_by(months, & &1.cash)

      case Enum.find(months, &(&1.cash < 0)) do
        nil ->
          "cash doesn't go below zero in these 12 months; it is lowest in #{esc(month_text(low.month))}, at #{whole(low.cash)}"

        first ->
          "cash first goes below zero in #{esc(month_text(first.month))} and is lowest in #{esc(month_text(low.month))}, at #{whole(low.cash)}"
      end
    end

    ~s(<p>With this plan, #{describe.(with_plan.months)}. Without it, #{describe.(base.months)}.</p>)
  end

  defp comparison(h, m, plan, today) do
    base = CashFlow.project(sc(h, m), today)
    with_plan = CashFlow.project(sc(h, m), today, plan)
    loans = Enum.filter(with_plan.debts, & &1.planned)

    rows =
      Enum.zip(base.months, with_plan.months)
      |> Enum.map_join("", fn {a, b} ->
        diff =
          if a.cash && b.cash,
            do: esc(format_amount(b.cash - a.cash)),
            else: esc(format_amount(b.net - a.net))

        """
        <tr role=row><td role=cell class=fdate data-label="Month"><b>#{esc(month_text(a.month))}</b></td><td role=cell class=num data-label="Without this plan" data-short="Without this plan">#{if a.cash, do: cash_cell(a.cash), else: esc(format_amount(a.net))}</td><td role=cell class=num data-label="With this plan" data-short="With this plan">#{if b.cash, do: cash_cell(b.cash), else: esc(format_amount(b.net))}</td><td role=cell class=num data-label="Difference" data-short="Difference">#{diff}</td></tr>
        """
      end)

    what =
      if base.start,
        do: "cash at the end of each month",
        else: "net money in and out each month (add an account's balance to see cash)"

    head =
      ["Month", {"Without this plan", :num}, {"With this plan", :num}, {"Difference", :num}]
      |> Enum.map_join("", &th/1)

    interest =
      case loans do
        [] ->
          ""

        ls ->
          ~s(<p>Interest on the planned borrowing over these months: #{esc(plain_amount(Enum.sum(Enum.map(ls, & &1.interest))))}.</p>)
      end

    """
    <h3>With and without this plan</h3>
    #{plan_summary(base, with_plan)}
    <p class=hint>Showing #{what}. This is a plan, not what's real.</p>
    <details><summary>Month by month</summary><div class=scroll><table class="stack dist" role=table aria-label="With this plan"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div></details>
    #{interest}
    """
  end

  @doc """
  REQ-148: a plan someone asks this member to share, before they agree: its steps, and the same
  comparison worked out from their own items. nil unless it's a plan request they can see.
  """
  def request_page(h, m, pid, csrf, today) do
    case Enum.find(
           Items.pending(sc(h, m)),
           &(to_string(&1.id) == pid and is_map(&1[:attrs]) and &1.attrs[:kind] == :plan)
         ) do
      nil ->
        nil

      p ->
        fields = csrf <> ~s(<input type=hidden name=return value="/plans">)
        steps = Map.get(p.attrs, :steps, [])
        name = p.attrs[:label] || ""

        agree =
          if m in p.consents,
            do: ~s(<p class=hint>You've agreed. Waiting for the others.</p>),
            else:
              ~s(<form method=post action="/act/consent">#{fields}<input type=hidden name=proposal value="#{p.id}"><button>Agree to share it</button></form>)

        """
        <p class=back><a href="/">← Everything</a></p>
        <section class="card attention"><h2>#{esc(name)}</h2>
        <p class=hint>#{esc(people(p.consents, m))} asked you to share this plan. Nothing changes until you agree, and a shared plan never changes your real totals.</p>
        <ol>#{Enum.map_join(steps, "", &"<li>#{esc(step_text(h, m, &1.step))}</li>")}</ol>
        #{comparison(h, m, %{steps: steps}, today)}
        #{agree}
        </section>
        """
    end
  end

  @doc "REQ-142/143/148: one of the member's plans."
  def plan_page(h, m, id, csrf, today, message \\ nil) do
    case Planning.plans(sc(h, m))[id] do
      nil ->
        nil

      plan ->
        fields = csrf <> ~s(<input type=hidden name=plan value="#{esc(id)}">)

        owned =
          Items.visible(sc(h, m))
          |> Enum.filter(&(m in &1.owners and Items.money?(&1)))
          |> Enum.sort_by(&String.downcase(title(&1)))

        others = Households.members(sc(h, m)) |> MapSet.delete(m) |> Enum.sort()

        steps =
          case plan.steps do
            [] ->
              ~s(<p class=empty>No steps yet. Add one below.</p>)

            ss ->
              "<ol>" <>
                Enum.map_join(ss, "", fn %{n: n, step: st} ->
                  "<li>#{esc(step_text(h, m, st))} " <>
                    button(
                      "remove_step",
                      %{"plan" => id, "n" => n},
                      "Remove",
                      "Remove step #{n}",
                      csrf
                    ) <> "</li>"
                end) <> "</ol>"
          end

        switch_boxes =
          Enum.map_join(owned, "", fn i ->
            ~s(<label class=check><input type=checkbox name="items[]" value="#{esc(i.id)}"> #{esc(title(i))}</label>)
          end)

        share_boxes =
          Enum.map_join(others, "", fn o ->
            ~s(<label class=check><input type=checkbox name="members[]" value="#{esc(o)}"> #{esc(o)}</label>)
          end)

        """
        <p class=back><a href="/plans">← Plans</a></p>
        #{message(message)}
        <section class=card><h2>#{esc(plan.name)}</h2>
        <p class=hint>A plan, private to you. It never changes your real totals.</p>
        #{steps}
        #{comparison(h, m, plan, today)}
        </section>
        <section class=card><h2>Add a step</h2>
        <h3>Switch items off</h3>
        <form method=post action="/act/plan_step" id=step-switch>#{fields}<input type=hidden name=kind value=switch_off>
        <fieldset><legend>Which items?</legend>#{if switch_boxes == "", do: ~s(<p class=empty>You don't own any items yet.</p>), else: ~s(<div class=checks>#{switch_boxes}</div>)}</fieldset>
        <p class=hint>Anything you've marked as depending on a job switches off with it.</p>
        <p><label for=switch-from>From</label><select id=switch-from name=from>#{month_options(today, nil)}</select></p>
        <button>Add switching off</button></form>
        <h3>Add planned money in or out</h3>
        <form method=post action="/act/plan_step" class=row id=step-add>#{fields}<input type=hidden name=kind value=add>
        <p><label for=add-note>Planned item</label><input id=add-note name=note placeholder="e.g. Marketplace health premium"></p>
        <p><label for=add-amount>Amount</label><input id=add-amount name=amount inputmode=decimal autocomplete=off placeholder="e.g. 600"></p>
        <p><label for=add-frequency>How often?</label><select id=add-frequency name=frequency>#{frequency_options(nil)}</select></p>
        <fieldset class=direction><legend>Money</legend>
        <label class=check><input type=radio name=direction value=out checked> Money out</label>
        <label class=check><input type=radio name=direction value=in> Money in</label></fieldset>
        <p><label for=add-from>From</label><select id=add-from name=from>#{month_options(today, nil)}</select></p>
        <button>Add planned item</button></form>
        <h3>Borrow</h3>
        <form method=post action="/act/plan_step" class=row id=step-borrow>#{fields}<input type=hidden name=kind value=borrow>
        <p><label for=borrow-amount>Amount to borrow</label><input id=borrow-amount name=amount inputmode=decimal autocomplete=off placeholder="e.g. 5,000"></p>
        <p><label for=borrow-rate>Interest rate (%)</label><input id=borrow-rate name=rate inputmode=decimal autocomplete=off placeholder="e.g. 9"></p>
        <p><label for=borrow-payment>Monthly payment</label><input id=borrow-payment name=payment inputmode=decimal autocomplete=off placeholder="e.g. 200"></p>
        <p><label for=borrow-from>From</label><select id=borrow-from name=from>#{month_options(today, nil)}</select></p>
        <button>Add borrowing</button></form></section>
        <section class=card><h2>Ask others to share it</h2>
        <p class=hint>They'll see this plan as a request and share it only if they agree. What they see is worked out from their own items. Your plan here stays yours.</p>
        <form method=post action="/act/share_plan">#{fields}
        <fieldset><legend>Ask</legend><div class=checks>#{share_boxes}</div></fieldset>
        <button>Send request</button></form></section>
        <section class=card><h2>Delete this plan</h2>
        <form class=inline method=post action="/confirm/delete_plan">#{csrf}<input type=hidden name=plan value="#{esc(id)}"><button class=danger aria-label="Delete the plan #{esc(plan.name)}">Delete plan…</button></form></section>
        """
    end
  end

  defp frequency_options(chosen) do
    [{"", "Choose…"} | Words.frequency_choices()]
    |> Enum.map_join("", fn {v, t} ->
      sel = if v != "" and v == chosen, do: " selected", else: ""
      ~s(<option value="#{v}"#{sel}>#{t}</option>)
    end)
  end

  defp shared_plan_page(h, m, i, csrf, message) do
    fields = csrf <> ~s(<input type=hidden name=return value="/items/#{esc(i.id)}">)
    owner? = m in i.owners
    steps = Map.get(i.attrs, :steps, [])

    """
    <p class=back><a href="/plans">← Plans</a></p>
    #{message(message)}
    <section class=card><h2>#{esc(title(i))}</h2>
    <p class=hint>A shared plan, owned by #{esc(people(i.owners, m))}. Its steps don't change; a revised plan is a new request.</p>
    <ol>#{Enum.map_join(steps, "", &"<li>#{esc(step_text(h, m, &1.step))}</li>")}</ol>
    #{comparison(h, m, %{steps: steps}, FindependenceApp.Web.today())}
    </section>
    #{if owner?, do: history_section(h, m, i) <> let_go_section(i, fields), else: ""}
    """
  end

  # REQ-144: items the member owns can be marked as depending on a job (an income they own).
  defp depends_section(h, m, i, fields) do
    if Items.money?(i) and not (is_integer(i.attrs[:amount]) and i.attrs[:amount] > 0) do
      jobs =
        Items.visible(sc(h, m))
        |> Enum.filter(
          &(m in &1.owners and Items.money?(&1) and is_integer(&1.attrs[:amount]) and
              &1.attrs[:amount] > 0 and &1.id != i.id)
        )
        |> Enum.sort_by(&String.downcase(title(&1)))

      list =
        Enum.map_join(
          Enum.filter(Planning.depends(sc(h, m)), fn {x, _} -> x == i.id end),
          "",
          fn {_, j} ->
            "<li>Depends on #{esc(title(Items.lookup(sc(h, m), j)))} " <>
              button(
                "unmark",
                %{"item" => i.id, "job" => j},
                "Remove",
                "Stop marking it as depending on #{title(Items.lookup(sc(h, m), j))}",
                fields
              ) <> "</li>"
          end
        )

      form =
        if jobs == [],
          do:
            ~s(<p class=hint>Add a paycheck or other income you own to mark this as depending on it.</p>),
          else: """
          <form method=post action="/act/mark" class=row>#{fields}<input type=hidden name=item value="#{esc(i.id)}">
          <p><label for=job>Depends on</label><select id=job name=job>#{Enum.map_join(jobs, "", &~s(<option value="#{esc(&1.id)}">#{esc(title(&1))}</option>))}</select></p>
          <button>Mark</button></form>
          """

      """
      <section class=card><h2>Does it depend on a job?</h2>
      <p class=hint>If this stops when a job stops (like an employer's health plan or a commute), mark it. In a plan, switching off the job switches this off too. Only you see your marks.</p>
      #{if list == "", do: "", else: "<ul class=plain>#{list}</ul>"}
      #{form}</section>
      """
    else
      ""
    end
  end

  # ---------------------------------------------------------------------------
  # CAP-012 retirement (REQ-149..154)

  @doc """
  REQ-151..154: the retirement projection from the member's own assumptions, how sensitive it is,
  and the form to change them. `form` carries what was typed and field errors after a refused save.
  """
  def retirement_page(h, m, csrf, today, message \\ nil, form \\ %{}) do
    s = Planning.retirement_settings(sc(h, m))

    accounts =
      Items.visible(sc(h, m))
      |> Enum.filter(&Balances.retirement?/1)
      |> Enum.sort_by(&String.downcase(title(&1)))

    result =
      case Planning.retirement_projection(sc(h, m), today) do
        {:missing, _} ->
          ~s(<p class=hint>To see a projection, enter your birth year, a retirement age, and a yearly return below.</p>)

        p ->
          retirement_result(h, m, p, accounts, today)
      end

    # a refused save says so at the top, where the page opens, and links to the fields
    top =
      if (form[:errors] || %{}) != %{},
        do:
          ~s(<p class="msg err" role="alert">Nothing was saved. <a href="#assumptions">Check the fields marked in your assumptions.</a></p>),
        else: message(message)

    """
    <p class=back><a href="/">← Everything</a></p>
    #{top}
    <section class=card><h2>Retirement</h2>
    <p class=hint>Worked out in today's dollars from assumptions you set. Only you see them, and nothing here is advice or a suggestion.</p>
    #{result}
    </section>
    #{retirement_sensitivity(h, m, today)}
    #{retirement_form(s, accounts, csrf, form)}
    """
  end

  defp retirement_result(h, m, p, accounts, today) do
    rows =
      Enum.map_join(p.rows, "", fn r ->
        """
        <tr role=row><td role=cell class=fdate data-label="Year"><b>#{r.year}</b></td><td role=cell class=num data-label="Age" data-short="Age">#{r.age}</td><td role=cell class=num data-label="Added" data-short="Added">#{esc(plain_amount(r.contributed))}</td><td role=cell class=num data-label="Growth" data-short="Growth">#{esc(about_signed(r.growth))}</td><td role=cell class=num data-label="Balance at the end" data-short="Balance">#{esc(about(r.balance))}</td></tr>
        """
      end)

    head =
      ["Year", {"Age", :num}, {"Added", :num}, {"Growth", :num}, {"Balance at the end", :num}]
      |> Enum.map_join("", &th/1)

    table =
      if rows == "",
        do: "",
        else:
          ~s(<details><summary>Year by year, #{length(p.rows)} #{if length(p.rows) == 1, do: "year", else: "years"}</summary><div class=scroll><table class="stack dist" role=table aria-label="Retirement accounts year by year"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div></details>)

    starts =
      case accounts do
        [] ->
          ~s(no retirement account yet: <a href="/balances/new">add one</a> as a 401\(k\) or an IRA)

        list ->
          list
          |> Enum.map(fn i ->
            case Balances.latest(sc(h, m), i.id) do
              nil ->
                "#{esc(title(i))} (no balance yet, so $0.00)"

              r ->
                "#{esc(title(i))} (#{esc(plain_amount(r.balance))} as of #{esc(date_text(r.on))})"
            end
          end)
          |> people()
      end

    when_text =
      if p.retire_year > today.year,
        do: "In January #{p.retire_year}, the year you turn #{p.retire_age}",
        else: "Now"

    """
    <p>#{when_text}:</p>
    <p class="amount-big">#{esc(about(p.at_retirement))}</p>
    #{retirement_comparison(p)}
    #{table}
    <p class=hint>How this is worked out: starting from #{starts}; adding #{esc(plain_amount(p.monthly_contribution))} a month as you entered; growing each month at #{esc(pct_text(p.return_bp))} a year after inflation, the return you entered; until January of the year you turn #{p.retire_age}. Everything is in today's dollars, and estimates are rounded to the nearest $100.</p>
    """
  end

  defp retirement_comparison(%{gap: nil}),
    do: ~s(<p class=hint>Enter a target income below to compare with it.</p>)

  defp retirement_comparison(p) do
    ~s(<p>#{esc(lasts_sentence(p))}</p>)
  end

  # UX-002 R6: an estimate years ahead is shown to the nearest $100, and says it's an estimate;
  # what the member typed, and what follows from it exactly, stays to the cent.
  # UX-003 C10: an estimate rounded to the nearest $100 is shown in whole dollars, without cents

  # REQ-153: one assumption changed at a time; nothing saved
  defp retirement_sensitivity(h, m, today) do
    case Planning.retirement_sensitivity(sc(h, m), today) do
      {:missing, _} ->
        ""

      list ->
        rows =
          Enum.map_join(list, "", fn r ->
            label =
              case r.change do
                :as_entered -> "As you entered"
                {:return, d} when d < 0 -> "Return 2 points lower"
                {:return, _} -> "Return 2 points higher"
                {:retire_age, d} when d < 0 -> "Retiring 2 years earlier"
                {:retire_age, _} -> "Retiring 2 years later"
              end

            """
            <tr role=row><td role=cell data-label="If"><b>#{label}</b></td><td role=cell class=num data-label="Return" data-short="Return">#{esc(pct_text(r.return_bp))}</td><td role=cell class=num data-label="Retiring at" data-short="Retiring at">#{r.retire_age}</td><td role=cell class=num data-label="At retirement" data-short="At retirement">#{esc(about(r.at_retirement))}</td><td role=cell data-label="Paying the difference" data-short="Paying the difference">#{esc(lasts_short(r))}</td></tr>
            """
          end)

        head =
          [
            "If",
            {"Return", :num},
            {"Retiring at", :num},
            {"At retirement", :num},
            "Paying the difference"
          ]
          |> Enum.map_join("", &th/1)

        """
        <section class=card><h2>What changes the result</h2>
        <p class=hint>The same projection with one assumption changed at a time. Nothing here is saved.</p>
        <div class=scroll><table class="stack dist" role=table aria-label="What changes the result"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div>
        </section>
        """
    end
  end

  defp retirement_form(s, accounts, csrf, form) do
    values = form[:values] || %{}
    errors = form[:errors] || %{}

    shown = fn name, current ->
      if Map.has_key?(values, name), do: values[name], else: current
    end

    money = fn
      nil -> ""
      c -> c |> plain_amount() |> String.replace_prefix("$", "")
    end

    field = fn name, label, current, attrs, hint ->
      err = errors[name]

      invalid =
        if err, do: ~s( aria-invalid="true" aria-describedby="#{name}-error"), else: ""

      """
      <p><label for="#{name}">#{label}</label><input id="#{name}" name="#{name}" #{attrs} autocomplete=off value="#{esc(shown.(name, current))}"#{invalid}>#{if err, do: field_error(name, err), else: ""}#{if hint, do: ~s(<span class="hint field-hint">#{hint}</span>), else: ""}</p>
      """
    end

    contributions =
      case accounts do
        [] ->
          ~s(<p class=hint>Contributions go with a retirement account. <a href="/balances/new">Add one</a> as a 401\(k\) or an IRA.</p>)

        list ->
          Enum.map_join(list, "", fn i ->
            field.(
              "contribution_" <> i.id,
              "Each month into #{esc(title(i))}",
              money.(s.contributions[i.id]),
              "inputmode=decimal",
              nil
            )
          end)
      end

    """
    <section class=card id=assumptions><h2>Your assumptions</h2>
    <p class=hint>All yours to set; none is filled in for you. Leave a field empty and save to clear it. Amounts are a month, in today's dollars.</p>
    <form method=post action="/act/retirement">#{csrf}
    #{if errors != %{}, do: ~s(<p class="msg err">Nothing was saved. Check the fields marked below.</p>), else: ""}
    #{field.("birth_year", "Year you were born", (s.birth_year && Integer.to_string(s.birth_year)) || "", "inputmode=numeric", nil)}
    #{field.("retire_age", "Retirement age", (s.retire_age && Integer.to_string(s.retire_age)) || "", "inputmode=numeric", nil)}
    #{field.("return", "Yearly return after inflation (%)", (s.return_bp && s.return_bp |> rate_text() |> String.replace_suffix("%", "")) || "", "inputmode=decimal", nil)}
    #{contributions}
    #{field.("ss", "Social Security estimate, a month", money.(s.ss_monthly), "inputmode=decimal", "From your own Social Security statement, in today's dollars.")}
    #{field.("target", "Target income in retirement, a month", money.(s.target_monthly), "inputmode=decimal", nil)}
    <button>Save assumptions</button></form></section>
    """
  end

  # ---------------------------------------------------------------------------
  # CAP-009 bringing in a saved record (REQ-156..159)

  @doc "The page to choose a saved export; `problem` is why the last file was refused."
  def bring_in_page(csrf, message \\ nil, problem \\ nil) do
    """
    <p class=back><a href="/">← Everything</a></p>
    #{message(message)}
    #{if problem, do: bring_in_problem(problem), else: ""}
    <section class=card><h2>Bring in your record</h2>
    <p class=hint>If you saved your record from another household (Leaving, then “Save as a file”), you can bring it in here. Everything in it becomes yours alone: nobody here can see any of it until you share it. You'll see what's in the file before anything is saved.</p>
    <form method=post action="/act/bring-in" enctype="multipart/form-data">#{csrf}
    <p><label for=file>Your saved file</label><input type=file id=file name=file accept=".json,application/json" required></p>
    <button>Check the file</button></form></section>
    """
  end

  defp bring_in_problem({:problems, problems}) do
    list =
      Enum.map_join(problems, "", fn {where, what} ->
        "<li>#{esc(where_text(where))}: #{esc(what_text(what))}</li>"
      end)

    ~s(<section class="card warn" role="alert"><h2>Nothing was brought in</h2><p>The file doesn't pass the checks, so none of it was brought in. What was wrong:</p><ul>#{list}</ul><p class=hint>A file saved by the app passes. If you changed it by hand, save a fresh copy from the other household.</p></section>)
  end

  defp bring_in_problem(problem) do
    text =
      case problem do
        :no_file ->
          "Choose your saved file first."

        :too_large ->
          "An export file is at most 1 MB, so this one wasn't read."

        :not_json ->
          "This isn't a Findependence export file."

        {:already_imported, on} ->
          "You brought in this file on #{date_text(on)}, so it wasn't brought in again."
      end

    text =
      if match?({:already_imported, _}, problem),
        do: text,
        else: text <> " Nothing was brought in."

    ~s(<p class="msg err" role="alert">#{esc(text)}</p>)
  end

  @doc "REQ-158: what the file would bring in, to confirm or cancel."
  def bring_in_preview(summary, name, csrf) do
    names = fn list ->
      {shown, rest} = Enum.split(Enum.sort_by(list, &String.downcase/1), 12)
      more = if rest == [], do: "", else: ", and #{length(rest)} more"
      esc(Enum.join(shown, ", ")) <> more
    end

    count = fn n, one, many -> "#{n} #{if n == 1, do: one, else: many}" end

    lines =
      [
        {summary.items, "item", "items"},
        {summary.values, "value", "values"},
        {summary.accounts, "account", "accounts"},
        {summary.debts, "debt", "debts"}
      ]
      |> Enum.reject(fn {l, _, _} -> l == [] end)
      |> Enum.map(fn {l, one, many} ->
        "<li>#{count.(length(l), one, many)}: #{names.(l)}</li>"
      end)

    extra =
      [
        {summary.readings, "balance", "balances"},
        {summary.links, "link to a value", "links to values"},
        {summary.marks, "mark on what depends on a job", "marks on what depends on a job"},
        {Map.get(summary, :attached, 0), "choice of the account an item goes through",
         "choices of the account an item goes through"},
        {summary.goals, "goal", "goals"},
        {summary.retirement, "retirement assumption", "retirement assumptions"}
      ]
      |> Enum.reject(fn {n, _, _} -> n == 0 end)
      |> Enum.map(fn {n, one, many} -> "<li>#{count.(n, one, many)}</li>" end)

    plans =
      if summary.plans == [],
        do: [],
        else: [
          "<li>#{count.(length(summary.plans), "plan", "plans")}: #{names.(summary.plans)}</li>"
        ]

    shared =
      if summary.shared_plans > 0,
        do:
          "<p class=hint>#{count.(summary.shared_plans, "shared plan isn't", "shared plans aren't")} brought in: #{if summary.shared_plans == 1, do: "it was an agreement", else: "they were agreements"} with others in the other household.</p>",
        else: ""

    body =
      if lines ++ extra ++ plans == [],
        do: ~s(<p class=empty>The file has nothing to bring in.</p>),
        else: "<ul>#{Enum.join(lines ++ extra ++ plans)}</ul>"

    """
    <p class=back><a href="/bring-in">← Choose another file</a></p>
    <section class="card attention"><h2>What would be brought in</h2>
    <p>From <b>#{esc(name)}</b>, checked. Nothing is saved until you choose “Bring it in”.</p>
    #{body}
    <p class=hint>All of it becomes yours alone. Its history, owners, and who it was shared with in the other household stay in your file. Goals and retirement assumptions you've already set here are kept.</p>
    #{shared}
    <form method=post action="/act/bring-in/confirm" class=inline>#{csrf}<button class=primary>Bring it in</button></form>
    <form method=post action="/act/bring-in/cancel" class=inline>#{csrf}<button>Cancel</button></form>
    </section>
    """
  end

  @doc "REQ-146/147: goals."
  def goals_page(h, m, csrf, message \\ nil) do
    c = Planning.cover(sc(h, m))
    g = Planning.goals(sc(h, m))

    cover =
      case c.months do
        nil ->
          ~s(<p class=hint>To see how long savings would last, <a href="/balances/new">add a savings account</a> and its balance.</p>)

        months ->
          goal =
            case g.fund_months do
              nil ->
                ""

              gm ->
                ~s(<p>Your goal: #{gm} #{if gm == 1, do: "month", else: "months"} of money out. You're at #{:erlang.float_to_binary(months, decimals: 1)} of #{gm}.</p>)
            end

          """
          <p class="amount-big">About #{:erlang.float_to_binary(months, decimals: 1)} months</p>
          <p class=hint>Savings of #{esc(plain_amount(c.savings))} against #{esc(plain_amount(c.monthly_out))} a month of money out, if no money came in. Counts repeating money out of items you own.</p>
          #{goal}
          """
      end

    values =
      Items.visible(sc(h, m))
      |> Enum.filter(&Values.value?/1)
      |> Enum.sort_by(&String.downcase(title(&1)))

    asides = Planning.set_asides(sc(h, m))

    aside_list =
      Enum.map_join(asides, "", fn a ->
        "<li>#{esc(rate_text(a.rate_bp))} of money in for #{esc(title(Items.lookup(sc(h, m), a.value_id)))} (#{esc(plain_amount(a.monthly_in))} a month): set aside #{esc(plain_amount(a.set_aside))} a month " <>
          button(
            "set_aside",
            %{"value" => a.value_id, "rate" => ""},
            "Remove",
            "Remove the set-aside for #{title(Items.lookup(sc(h, m), a.value_id))}",
            csrf
          ) <> "</li>"
      end)

    """
    <p class=back><a href="/">← Everything</a></p>
    #{message(message)}
    <section class=card><h2>How long savings would last</h2>
    #{cover}
    <form method=post action="/act/fund_goal" class=row>#{csrf}
    <p><label for=fund-months>Emergency fund goal, in months of money out</label><input id=fund-months name=months inputmode=numeric autocomplete=off value="#{g.fund_months || ""}"></p>
    <button>Save goal</button></form>
    <p class=hint>The goal is yours; nothing here suggests one. Leave it empty and save to clear it.</p></section>
    <section class=card><h2>Setting aside from income</h2>
    <p class=hint>For money in linked to one of your values, such as a side business, choose a rate to set aside, for example for taxes. The rate is yours; this isn't tax advice.</p>
    #{if aside_list == "", do: "", else: "<ul class=plain>#{aside_list}</ul>"}
    #{if values == [], do: ~s(<p class=hint>Add a value, and link income to it, to set a rate here.</p>), else: """
      <form method=post action="/act/set_aside" class=row>#{csrf}
      <p><label for=aside-value>For money in linked to</label><select id=aside-value name=value>#{options(values)}</select></p>
      <p><label for=aside-rate>Rate (%)</label><input id=aside-rate name=rate inputmode=decimal autocomplete=off placeholder="e.g. 25"></p>
      <button>Save rate</button></form>
      """}</section>
    """
  end

  # REQ-145: a calculation on the debt's page, from a GET form; nothing is stored.
  defp debt_what_if(_i, nil, _q), do: ""

  defp debt_what_if(i, r, q) do
    w = Balances.what_if(r, q["extra"], q["rate"])

    %{base: base, with_extra: extra_line, at_rate: rate_line} = Words.what_if_lines(r, w)

    {extra, rate} = {w.extra, w.rate}

    with_extra = what_if_html(extra_line)
    at_rate = what_if_html(rate_line)

    # UX-003 C6: a refused figure is reported under its own field, not above the form
    {extra_result, extra_attrs, extra_error} = what_if_part(with_extra, "extra")
    {rate_result, rate_attrs, rate_error} = what_if_part(at_rate, "whatif-rate")

    """
    <section class=card><h2>What if</h2>
    <p>#{esc(base)}</p>
    #{extra_result}#{rate_result}
    <form method=get action="/items/#{esc(i.id)}" class=row>
    <p><label for=extra>Extra each month</label><input id=extra name=extra inputmode=decimal autocomplete=off placeholder="e.g. 100" value="#{esc(extra)}"#{extra_attrs}>#{extra_error}</p>
    <p><label for=whatif-rate>Or a different rate (%)</label><input id=whatif-rate name=rate inputmode=decimal autocomplete=off placeholder="e.g. 10.5" value="#{esc(rate)}"#{rate_attrs}>#{rate_error}</p>
    <button>Work it out</button></form>
    <p class=hint>Worked out from the latest balance. Nothing is saved, and no payment order is suggested.</p></section>
    """
  end

  defp what_if_part({:error, message}, field),
    do:
      {"", ~s( aria-invalid="true" aria-describedby="#{field}-error"),
       field_error(field, message)}

  defp what_if_part(html, _field), do: {html, "", ""}

  defp what_if_html(nil), do: ""
  defp what_if_html({:error, _} = error), do: error
  # fixed words and figures the app worked out, nothing the member typed, so written as they are
  defp what_if_html({lead, text}), do: ~s(<p><b>#{lead}</b> #{text}</p>)

  # ---------------------------------------------------------------------------
  # CAP-011 dated cash flow (REQ-136..140)

  defp next_date_line(i) do
    today = FindependenceApp.Web.today()

    case CashFlow.occurrences(i, today, Date.add(today, 800)) do
      [d | _] ->
        label = if Items.frequency(i) == :one_off, do: "On", else: "Next:"
        ~s(<p>#{label} #{esc(date_text(Date.to_iso8601(d)))}</p>)

      [] ->
        case CashFlow.date(i) do
          nil -> ""
          d -> ~s(<p class=hint>Happened on #{esc(date_text(Date.to_iso8601(d)))}.</p>)
        end
    end
  end

  # One row per day that has something on it: what, the day's net amount, and the balance after.
  defp flow_rows(days, limit \\ nil) do
    dated = Enum.filter(days, &(&1.entries != []))
    shown = if limit, do: Enum.take(dated, limit), else: dated

    shown
    |> Enum.map_join("", fn d ->
      what =
        Enum.map_join(d.entries, "<br>", fn {i, a} ->
          ~s(<a href="/items/#{esc(i.id)}">#{esc(title(i))}</a> <span class=nowrap>#{esc(format_amount(a))}</span>)
        end)

      net = d.entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()

      balance =
        cond do
          d.balance == nil -> ""
          d.balance < 0 -> below_zero(d.balance)
          true -> esc(plain_amount(d.balance))
        end

      """
      <tr role=row><td role=cell class=fdate data-label="Date"><b>#{esc(date_text(Date.to_iso8601(d.date)))}</b></td><td role=cell class=fwhat data-label="What">#{what}</td><td role=cell class="num fnet" data-label="Net">#{esc(format_amount(net))}</td><td role=cell class="num fbal" data-label="Balance after">#{balance}</td></tr>
      """
    end)
  end

  # UX-004 P2: when a co-owner's items may be missing, the figure is labelled as the member's part
  defp flow_table(rows, label, after_rows, partial?) do
    balance = if partial?, do: "Your part after", else: "Balance after"
    class = if partial?, do: "stack flow partial", else: "stack flow"

    head =
      ["Date", "What", {"Net", :num}, {balance, :num}]
      |> Enum.map_join("", &th/1)

    ~s(<div class=scroll><table class="#{class}" role=table aria-label="#{label}"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div>#{after_rows})
  end

  # REQ-106 applies to the running balance too; say so, so a gap isn't mistaken for a shortfall.
  defp start_line(nil, _h, _m),
    do:
      ~s(<p class=hint>To see a running balance, <a href="/balances/new">add your checking account</a> and its balance.</p>)

  defp start_line(start, h, m) do
    names = Enum.map(start.accounts, fn id -> title(Items.lookup(sc(h, m), id)) end) |> people()

    ~s(<p class=hint>Starting from #{esc(names)}: #{esc(plain_amount(start.balance))} as of #{esc(date_text(Date.to_iso8601(start.on)))}. #{esc(counted_note(h, m, start.accounts))}</p>)
  end

  # UX-002 R1a: on an account someone else also owns, the view is the member's part of the picture,
  # and says whose items it leaves out, by name. UX-004 P2: in one sentence, and the figure's own
  # label says "your part" (partial?/3), so the table doesn't read as the account's balance.

  @doc "REQ-138: the next fourteen days on home."
  def coming_up_card(h, m, today) do
    %{start: start, days: days} = CashFlow.cash_flow(sc(h, m), today, 14)
    # UX contract: home stays short, so at most four days here; the rest are one click away
    rows = flow_rows(days, 4)
    more = Enum.count(days, &(&1.entries != [])) - 4

    more_line =
      if more > 0,
        do:
          ~s(<p class=hint>And #{more} more #{if more == 1, do: "day", else: "days"} with something on them in the next 14.</p>),
        else: ""

    # UX-004 H2: with no account yet, say both things Coming up needs, with a way to each
    body =
      cond do
        rows == "" and start == nil ->
          ~s(<p class=empty>Coming up needs an account's balance and the date each bill or paycheck happens. <a href="/balances/new">Add an account and its balance</a>, and give items a date when you <a href="#add-item">add them</a>.</p>)

        rows == "" ->
          ~s(<p class=empty>Nothing dated in the next 14 days. Add the date a bill or paycheck happens to see it here.</p>)

        true ->
          flow_table(
            rows,
            "Coming up",
            more_line,
            start != nil and partial?(h, m, start.accounts)
          )
      end

    """
    <section class=card id=coming-up><h2>Coming up</h2>
    #{if rows != "", do: start_line(start, h, m), else: ""}
    #{body}
    <p class=links-row><a href="/next-60-days">The next 60 days</a> · <a href="/ahead">The next 12 months</a> · <a href="/plans">Plans</a> · <a href="/goals">Goals</a> · <a href="/retirement">Retirement</a></p></section>
    """
  end

  @doc "REQ-139, REQ-140: the next sixty days, stretches below zero, and set-asides."
  def next_60_page(h, m, today) do
    %{start: start, days: days} = CashFlow.cash_flow(sc(h, m), today, 60)
    rows = flow_rows(days)

    below =
      days
      |> Enum.chunk_by(&(&1.balance != nil and &1.balance < 0))
      |> Enum.filter(fn [d | _] -> d.balance != nil and d.balance < 0 end)
      |> Enum.map(fn chunk ->
        {a, b} = {hd(chunk).date, List.last(chunk).date}

        if a == b,
          do: date_text(Date.to_iso8601(a)),
          else: date_text(Date.to_iso8601(a)) <> " to " <> date_text(Date.to_iso8601(b))
      end)

    below_line =
      case below do
        [] -> ""
        ranges -> ~s(<p><b>Below zero:</b> #{esc(Enum.join(ranges, "; "))}.</p>)
      end

    %{total: total, items: lumpy} = CashFlow.set_asides(sc(h, m))

    set_asides =
      if lumpy == [],
        do: ~s(<p class=empty>No money-out items that happen less often than monthly.</p>),
        else: """
        <p>Setting aside <b>#{esc(plain_amount(total))} a month</b> covers these:</p>
        <ul class=plain>#{Enum.map_join(lumpy, "", fn {i, c} -> ~s(<li><a href="/items/#{esc(i.id)}">#{esc(title(i))}</a>: #{esc(money_line(i.attrs))}, #{esc(plain_amount(c))} a month</li>) end)}</ul>
        """

    """
    <p class=back><a href="/">← Everything</a></p>
    <section class=card><h2>The next 60 days</h2>
    <p class=hint>What's dated, day by day, from #{esc(date_text(Date.to_iso8601(today)))}. Only items with a date appear; irregular items have no dates.</p>
    #{if rows != "", do: start_line(start, h, m), else: ""}
    #{below_line}
    #{if rows == "", do: ~s(<p class=empty>Nothing dated in the next 60 days.</p>), else: flow_table(rows, "The next 60 days", "", start != nil and partial?(h, m, start.accounts))}
    </section>
    <section class=card><h2>Setting aside for bills that come a few times a year</h2>
    <p class=hint>Money-out items you own that happen less often than monthly, as a monthly amount.</p>
    #{set_asides}
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # CAP-010 balances and debts (REQ-130..135)

  # "$1,240.00", or "−$50.00" when overdrawn; a debt's balance reads "$5,200.00 owed"

  defp balances_card(_h, _m, []) do
    """
    <section class=card><h2>Balances and debts</h2>
    <p class=hint>What's in your accounts and what you owe. Private to you unless you share it.</p>
    <p class=empty>No accounts or debts yet.</p>
    <p><a class="button-link" href="/balances/new">Add an account or debt</a></p></section>
    """
  end

  defp balances_card(h, m, balances) do
    rows =
      balances
      |> Enum.sort_by(&{&1.attrs.kind, String.downcase(title(&1))})
      |> Enum.map_join("", fn i ->
        r = Balances.latest(sc(h, m), i.id)
        as_of = if r, do: "as of " <> date_text(r.on), else: ""

        """
        <tr role=row><td role=cell data-label="Account or debt"><a href="/items/#{esc(i.id)}"><b>#{esc(title(i))}</b></a></td><td role=cell class=num data-label="Balance">#{esc(balance_text(i, r))}</td>
        <td role=cell class="meta owner" data-label="Owned by">#{esc(people(i.owners, m))}</td>
        <td role=cell class="meta vis" data-label="As of">#{esc(kind_words(i))}#{if as_of != "", do: ", " <> esc(as_of), else: ""}</td></tr>
        """
      end)

    head =
      ["Account or debt", {"Balance", :num}, "Owned by", "Kind and date"]
      |> Enum.map_join("", &th/1)

    """
    <section class=card><h2>Balances and debts</h2>
    <p class=hint>What's in your accounts and what you owe, as last updated. Open one to update it or share it.</p>
    <div class=scroll><table class="stack compact" role=table aria-label="Balances and debts"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div>
    <p><a class="button-link" href="/balances/new">Add an account or debt</a></p></section>
    """
  end

  @doc "The page for adding an account or a debt (REQ-130)."
  def new_balance_page(csrf, form \\ %{}) do
    options = fn pairs, chosen ->
      [{"", "Choose…"} | pairs]
      |> Enum.map_join("", fn {v, t} ->
        sel = if v != "" and v == chosen, do: " selected", else: ""
        ~s(<option value="#{v}"#{sel}>#{t}</option>)
      end)
    end

    # UX-003 C6: the message goes under the field it's about: the name when it's empty, else the kind
    bad = fn which, f ->
      form[:which] == which and form[:error] != nil and
        f == if(String.trim(form[:label] || "") == "", do: "label", else: "type")
    end

    err = fn which, f ->
      if bad.(which, f), do: field_error("#{which}-#{f}", form[:error]), else: ""
    end

    invalid = fn which, f ->
      if bad.(which, f),
        do: ~s( aria-invalid="true" aria-describedby="#{which}-#{f}-error"),
        else: ""
    end

    val = fn which, k -> if form[:which] == which, do: esc(form[k]), else: "" end

    """
    <p class=back><a href="/">← Everything</a></p>
    <section class=card><h2>Add an account</h2>
    <p class=hint>Checking, savings, or another account. You'll add its balance next. Only you can see it unless you share it.</p>
    <form method=post action="/act/add_account" class=row>#{csrf}
    <p><label for=account-label>Name</label><input id=account-label name=label required placeholder="e.g. Joint checking" value="#{val.("account", :label)}"#{invalid.("account", "label")}>#{err.("account", "label")}</p>
    <p><label for=account-type>Kind</label><select id=account-type name=type required#{invalid.("account", "type")}>#{options.([{"checking", "Checking"}, {"savings", "Savings"}, {"retirement_401k", "401(k)"}, {"ira", "IRA"}, {"other", "Other"}], form[:which] == "account" && form[:type])}</select>#{err.("account", "type")}</p>
    <button>Add account</button></form></section>
    <section class=card><h2>Add a debt</h2>
    <p class=hint>A credit card, HELOC, loan, or anything else you owe. You'll add what's owed, the interest rate, and the minimum payment next.</p>
    <form method=post action="/act/add_debt" class=row>#{csrf}
    <p><label for=debt-label>Name</label><input id=debt-label name=label required placeholder="e.g. Visa card" value="#{val.("debt", :label)}"#{invalid.("debt", "label")}>#{err.("debt", "label")}</p>
    <p><label for=debt-type>Kind</label><select id=debt-type name=type required#{invalid.("debt", "type")}>#{options.([{"card", "Credit card"}, {"heloc", "HELOC"}, {"loan", "Loan"}, {"other", "Other"}], form[:which] == "debt" && form[:type])}</select>#{err.("debt", "type")}</p>
    <button>Add debt</button></form></section>
    """
  end

  # REQ-149
  defp retirement_note(i) do
    if Balances.retirement?(i),
      do:
        ~s(<p class=hint>A retirement account: it isn't counted as cash. See <a href="/retirement">Retirement</a>.</p>),
      else: ""
  end

  defp balance_page(h, m, i, csrf, message, form) do
    id = i.id
    fields = csrf <> ~s(<input type=hidden name=return value="/items/#{esc(id)}">)
    owner? = m in i.owners
    visible = Items.visible(sc(h, m))
    names = names(h, m)
    owners_of = owners_of(visible)
    pending = Items.pending(sc(h, m)) |> Enum.filter(&(&1.item_id == id))
    others = Households.members(sc(h, m)) |> MapSet.delete(m) |> Enum.sort()
    r = Balances.latest(sc(h, m), id)

    latest =
      case r do
        nil ->
          ~s(<p class=empty>No balance recorded yet.</p>)

        r ->
          debt =
            if i.attrs.kind == :debt,
              do: """
              <p>Interest rate #{esc(rate_text(r.rate_bp))} · Minimum payment #{esc(plain_amount(r.min_payment))}</p>
              <p class=hint>At #{esc(rate_text(r.rate_bp))}, a month's interest on #{esc(plain_amount(r.balance))} is #{esc(plain_amount(Balances.monthly_interest(r)))}.</p>
              """,
              else: ""

          ~s(<p class="amount-big">#{esc(balance_text(i, r))}</p><p class=hint>As of #{esc(date_text(r.on))}.</p>) <>
            debt <> retirement_note(i)
      end

    """
    <p class=back><a href="/">← Everything</a></p>
    #{message(message)}
    <section class=card><h2>#{esc(title(i))}</h2>
    <p class=hint>#{esc(kind_words(i))}</p>
    #{latest}
    #{if owner?, do: reading_form(i, fields, form, r), else: ""}
    #{if owner?, do: owner_sections(i, m, others, pending, owners_of, names, fields), else: shared_with_me(i, m)}
    </section>
    #{if i.attrs.kind == :debt, do: debt_what_if(i, r, form[:query] || %{}), else: ""}
    #{if owner?, do: earlier_readings(h, m, i) <> history_section(h, m, i) <> let_go_section(i, fields), else: ""}
    """
  end

  defp reading_form(i, fields, form, latest) do
    debt? = i.attrs.kind == :debt

    # UX-002 R2: a debt's rate and minimum rarely change, so they start from the latest balance;
    # after a refused save, what was typed is kept instead
    form =
      if debt? and latest != nil and not Map.has_key?(form, :rate),
        do:
          Map.merge(form, %{
            rate: latest.rate_bp |> rate_text() |> String.replace_suffix("%", ""),
            min_payment: latest.min_payment |> plain_amount() |> String.replace_prefix("$", "")
          }),
        else: form

    field = form[:error_field]

    invalid = fn f ->
      if form[:error] && field == f,
        do: ~s( aria-describedby="#{f}-error" aria-invalid="true"),
        else: ""
    end

    error_at = fn f ->
      if form[:error] && field == f, do: field_error(f, form[:error]), else: ""
    end

    today = Date.to_iso8601(FindependenceApp.Web.today())

    debt_fields =
      if debt?,
        do: """
        <p><label for=rate>Interest rate (%)</label><input id=rate name=rate inputmode=decimal autocomplete=off placeholder="e.g. 21.99" value="#{esc(form[:rate])}"#{invalid.(:rate)}>#{error_at.(:rate)}</p>
        <p><label for=min_payment>Minimum payment</label><input id=min_payment name=min_payment inputmode=decimal autocomplete=off placeholder="e.g. 150" value="#{esc(form[:min_payment])}"#{invalid.(:min_payment)}>#{error_at.(:min_payment)}</p>
        """,
        else: ""

    """
    <h3 id=update>Update balance</h3>
    <form method=post action="/act/add_reading" class=row>#{fields}<input type=hidden name=item value="#{esc(i.id)}">
    <p><label for=balance>#{if debt?, do: "Amount owed", else: "Balance"}</label><input id=balance name=balance inputmode=decimal autocomplete=off placeholder="#{if debt?, do: "e.g. 5,200", else: "e.g. 1,240.50"}" value="#{esc(form[:balance])}"#{invalid.(:balance)}>#{error_at.(:balance)}</p>
    #{debt_fields}
    <p><label for=on>As of</label><input id=on name=on type=date required value="#{esc(form[:on] || today)}"#{invalid.(:on)}>#{error_at.(:on)}</p>
    <button>Save balance</button></form>
    <p class=hint>#{if debt?, do: "Anyone who owns it can update it. People it's shared with see only the latest.", else: "Anyone who owns it can update it. People it's shared with see only the latest. For an overdrawn account, start with −."}</p>
    """
  end

  defp earlier_readings(h, m, i) do
    case Balances.readings(sc(h, m), i.id) do
      {:ok, list} when length(list) > 1 ->
        rows =
          list
          |> Enum.reverse()
          |> Enum.filter(&is_map/1)
          |> Enum.map_join("", fn r ->
            extra = if i.attrs.kind == :debt, do: " at #{rate_text(r.rate_bp)}", else: ""

            "<li>#{esc(date_text(r.on))}: #{esc(balance_text(i, r) <> extra)} <span class=hint>(#{esc(people([r.by], m))})</span></li>"
          end)

        ~s(<section class=card><h2>Earlier balances</h2><ol>#{rows}</ol></section>)

      _ ->
        ""
    end
  end

  defp shared_with_me(i, m) do
    """
    <p>#{esc(people(i.owners, m))} shared this with you. Only owners can change who can see it or view its history.</p>
    """
  end

  # {explanation, share button, owners button, owners hint}, by who must agree (REQ-103, REQ-107, REQ-115)
  defp owner_sections(i, m, others, pending, owners_of, names, fields) do
    id = i.id
    sole? = length(i.owners) == 1
    {agreement, share_label, owners_label, owners_hint} = agreement_text(sole?, value?(i))
    grantees = Map.get(i, :grantees, [])
    can_share_with = Enum.reject(others, &(&1 in i.owners or &1 in grantees))

    visible_to =
      if grantees == [],
        do: "<p>Nobody else can see it.</p>",
        else:
          "<ul class=plain>" <>
            Enum.map_join(grantees, "", fn g ->
              "<li>#{esc(g)} can see it #{button("revoke", %{"item" => id, "member" => g}, "Stop sharing", "Stop sharing #{title(i)} with #{g}", fields)}</li>"
            end) <> "</ul>"

    share =
      if can_share_with == [],
        do: "",
        else: """
        <form method=post action="/act/grant" class=row>#{fields}<input type=hidden name=item value="#{esc(id)}">
        <p><label for=share-with>Share with</label><select id=share-with name=member>#{Enum.map_join(can_share_with, "", &"<option>#{esc(&1)}</option>")}</select></p>
        <button>#{share_label}</button></form>
        """

    checkboxes =
      Enum.map_join([m | others], "", fn x ->
        checked = if x in i.owners, do: " checked", else: ""

        ~s(<label class=check><input type=checkbox name="owners[]" value="#{esc(x)}"#{checked}> #{esc(if x == m, do: "#{x} (you)", else: x)}</label>)
      end)

    waiting =
      if pending == [],
        do: "",
        else:
          ~s(<h3>Waiting</h3>) <>
            pending_list(pending, names, owners_of, m, fields, :item)

    """
    <p class=status>Owned by #{esc(people(i.owners, m))}.</p>
    <p class="hint agreement">#{agreement}</p>
    #{waiting}
    <h3>Who else can see it</h3>
    #{visible_to}
    #{share}
    <h3 id=owners>Who owns it</h3>
    <form method=post action="/act/owners">#{fields}<input type=hidden name=item value="#{esc(id)}">
    <fieldset><legend>Owners of “#{esc(title(i))}”</legend><div class=checks>#{checkboxes}</div></fieldset>
    <p class=hint>Ticked now: the current owners. #{owners_hint}</p>
    <button>#{owners_label}</button></form>
    """
  end

  # Links belong to the member (REQ-112): a money item links to values; a value lists what's linked to it.
  defp links_section(h, i, m, visible, fields) do
    links = Values.links(sc(h, m))
    names = Map.new(visible, &{&1.id, title(&1)})

    if value?(i) do
      linked =
        for({item, v} <- links, v == i.id, do: item)
        |> Enum.sort_by(&String.downcase(names[&1] || ""))

      body =
        if linked == [],
          do: "<p class=empty>Nothing linked yet. Open an item to link it here.</p>",
          else:
            "<ul class=plain>" <>
              Enum.map_join(linked, "", fn item ->
                ~s(<li><a href="/items/#{esc(item)}">#{esc(names[item])}</a> #{button("unlink", %{"item" => item, "value" => i.id}, "Unlink", "Unlink #{names[item]} from #{names[i.id]}", fields)}</li>)
              end) <> "</ul>"

      ~s(<section class=card><h2>Linked to this value</h2><p class=hint>Only you see your links.</p>#{body}</section>)
    else
      linked =
        for({item, v} <- links, item == i.id, do: v)
        |> Enum.sort_by(&String.downcase(names[&1] || ""))

      values = Enum.filter(visible, &value?/1)
      unlinked = Enum.reject(values, &(&1.id in linked))

      list =
        if linked == [],
          do: "<p class=empty>Not linked to anything you value.</p>",
          else:
            "<ul class=plain>" <>
              Enum.map_join(linked, "", fn v ->
                ~s(<li>#{esc(names[v])} #{button("unlink", %{"item" => i.id, "value" => v}, "Unlink", "Unlink from #{names[v]}", fields)}</li>)
              end) <> "</ul>"

      form =
        cond do
          values == [] ->
            ~s(<p class=hint>Add a value on the <a href="/">main page</a> to link this to it.</p>)

          unlinked == [] ->
            ""

          true ->
            """
            <form method=post action="/act/link" class=row>#{fields}<input type=hidden name=item value="#{esc(i.id)}">
            <p><label for=link-value>Link to</label><select id=link-value name=value>#{options(unlinked)}</select></p>
            <button>Link</button></form>
            """
        end

      ~s(<section class=card><h2>What it's for</h2><p class=hint>Link it to what matters to you. Only you see your links.</p>#{list}#{form}</section>)
    end
  end

  defp history_section(h, m, i) do
    case Items.ledger(sc(h, m), i.id) do
      {:ok, entries} ->
        ~s(<section class=card><h2>History</h2><ol>) <>
          Enum.map_join(entries, "", &"<li>#{esc(event_text(&1))}</li>") <> "</ol></section>"

      _ ->
        ""
    end
  end

  # UX-001 R3: only actions that can succeed. A sole owner gets Give away and Delete; a joint owner
  # gets Stop owning, behind a confirmation because they can only regain it if the others agree.
  defp let_go_section(i, fields) do
    name = title(i)
    id = esc(i.id)
    sole? = length(Enum.to_list(i.owners)) == 1

    actions =
      if sole? do
        ~s(<a class="button-link" href="#owners" aria-label="Give away #{esc(name)}">Give away…</a>) <>
          ~s(<form class=inline method=post action="/confirm/delete">#{fields}<input type=hidden name=item value="#{id}"><button class=danger aria-label="Delete #{esc(name)}">Delete…</button></form>)
      else
        ~s(<form class=inline method=post action="/confirm/relinquish">#{fields}<input type=hidden name=item value="#{id}"><button class=danger aria-label="Stop owning #{esc(name)}">Stop owning…</button></form>)
      end

    heading = if sole?, do: "Give away or delete", else: "Stop owning"
    ~s(<section class=card><h2>#{heading}</h2>#{actions}</section>)
  end

  # Waiting changes. :respond and :item show Agree for changes this member hasn't agreed to;
  # everything shows Withdraw for owners (REQ-125) and who is still needed.
  defp pending_list(list, names, owners_of, m, fields, mode) do
    "<ul class=plain>" <>
      Enum.map_join(list, "", fn p ->
        text = proposal_text(p, names, m)
        needed = needed(p, owners_of) |> MapSet.difference(MapSet.new(p.consents))

        link =
          cond do
            mode != :item and Map.has_key?(names, p.item_id) ->
              ~s( <a href="/items/#{esc(p.item_id)}">Open</a>)

            # REQ-148: a plan request can be seen before agreeing
            is_map(p[:attrs]) and p.attrs[:kind] == :plan ->
              ~s( <a href="/requests/#{p.id}">See the plan</a>)

            true ->
              ""
          end

        status =
          if m in p.consents,
            do: "Waiting for #{people(needed, m, "no one")}.",
            else: if(p.consents == [], do: "", else: "Agreed so far: #{people(p.consents)}.")

        agree =
          if m not in p.consents,
            do: button("consent", %{"proposal" => p.id}, "Agree", "Agree: #{text}", fields),
            else: ""

        "<li>#{esc(text)} <span class=hint>#{esc(status)}</span>#{link} #{agree}#{withdraw_button(p, owners_of, m, fields)}</li>"
      end) <> "</ul>"
  end

  # REQ-125: owners of the item can withdraw; a prospective joiner declines by not agreeing.
  defp withdraw_button(p, owners_of, m, fields) do
    owners = get_in(owners_of, [p.item_id, :owners]) || MapSet.new()

    if m in owners,
      do: button("withdraw", %{"proposal" => p.id}, "Withdraw", "Withdraw this request", fields),
      else: ""
  end

  # Who must agree: the current owners, and for a shared value or plan also anyone being added
  # (REQ-115, REQ-148).

  # REQ-126: per month in and out over repeating items, one-off in and out apart; no evaluation.
  # Stacked on phones like the item tables, with explicit table roles (WI-024).
  defp distribution(%{by_value: bv, unlinked: u}, values) do
    label = Map.new(values, &{&1.id, &1.attrs[:label]})

    row = fn name, b, class ->
      cells =
        [
          {"Money in, per month", "In/month", b.per_month.in},
          {"Money out, per month", "Out/month", b.per_month.out},
          {"One-off in", "One-off in", b.one_off.in},
          {"One-off out", "One-off out", b.one_off.out}
        ]
        |> Enum.map_join("", fn {head, short, cents} ->
          ~s(<td role=cell class=num data-label="#{head}" data-short="#{short}">#{esc(format_amount(cents))}</td>)
        end)

      ~s(<tr role=row#{class}><td role=cell data-label="Value">#{name}</td>#{cells}<td role=cell class=num data-label="Items" data-short="Items">#{b.count}</td></tr>)
    end

    rows =
      bv
      |> Enum.sort_by(fn {id, _} -> String.downcase(label[id] || "") end)
      |> Enum.map_join("", fn {id, b} ->
        row.(~s(<a href="/items/#{esc(id)}">#{esc(label[id])}</a>), b, "")
      end)

    head =
      [
        "What matters to you",
        {"Money in, per month", :num},
        {"Money out, per month", :num},
        {"One-off in", :num},
        {"One-off out", :num},
        {"Items", :num}
      ]
      |> Enum.map_join("", &th/1)

    """
    <div class=scroll><table class="stack dist" role=table aria-label="Totals by value"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}
    #{row.("Not linked to anything", u, " class=muted")}</tbody></table></div>
    """
  end

  @doc """
  UX-001 R8: everything needed to leave, on one page. The export comes first; each item or value
  the member owns is listed with the one action it needs (a joint owner stops owning; a sole owner
  gives it away or deletes it, chosen explicitly); the leave button appears once nothing is owned.
  The page states the consequences, so it is also the confirmation.
  """
  def leave_page(h, m, csrf, message \\ nil) do
    fields = csrf <> ~s(<input type=hidden name=return value="/leave">)
    visible = Items.visible(sc(h, m))
    {owned, shared} = Enum.split_with(visible, &(m in &1.owners))
    owned = Enum.sort_by(owned, &String.downcase(title(&1)))
    others = Households.members(sc(h, m)) |> MapSet.delete(m) |> Enum.sort()
    pending = Items.pending(sc(h, m))

    rows =
      Enum.map_join(owned, "", fn i ->
        ~s(<li class=leave-row><a href="/items/#{esc(i.id)}"><b>#{esc(display(i))}</b></a> #{leave_action(i, m, others, pending, fields)}</li>)
      end)

    step2 =
      if owned == [],
        do: "<p>You don't own anything now.</p>",
        else: ~s(<ul class="plain leave-list">#{rows}</ul>)

    shared_text =
      case length(shared) do
        0 -> ""
        1 -> "You'll stop seeing the 1 item or value others share with you. "
        n -> "You'll stop seeing the #{n} items and values others share with you. "
      end

    step3 =
      if owned == [],
        do: """
        <p>#{shared_text}Your links and your passphrase stop working here. This can't be undone.</p>
        <form method=post action="/act/leave">#{fields}<button class=danger>Leave the household</button></form>
        """,
        else: "<p class=hint>You can leave once you don't own anything.</p>"

    """
    <p class=back><a href="/">← Everything</a></p>
    #{message(message)}
    <section class=card><h2>Leave the household</h2>
    <p class=hint>Everything you own needs someone to own it, or to be deleted, before you go. Nothing here happens until you press a button.</p>
    <h3>1. Save a copy</h3>
    <p><a href="/export">See everything you'd take with you</a>, and save it as a file.</p>
    <h3>2. What you own (#{length(owned)})</h3>
    #{step2}
    <h3>3. Leave</h3>
    #{step3}</section>
    """
  end

  defp leave_action(i, m, others, pending, fields) do
    name = title(i)
    id = esc(i.id)
    keepers = i.owners |> Enum.reject(&(&1 == m))
    mine = Enum.filter(pending, &(&1.item_id == i.id and m in &1.consents))

    cond do
      mine != [] ->
        ~s(<span class=hint>Waiting for #{esc(waiting_on_people(i, mine, m))} to agree.</span> ) <>
          Enum.map_join(mine, "", fn p ->
            button(
              "withdraw",
              %{"proposal" => p.id},
              "Withdraw",
              "Withdraw the request for #{name}",
              fields
            )
          end)

      keepers != [] ->
        ~s(<span class=hint>Owned with #{esc(people(keepers))}, who will keep it. To own it again, you'd need #{if length(keepers) == 1, do: "their", else: "all their"} agreement.</span> ) <>
          button(
            "relinquish",
            %{"item" => i.id},
            "Stop owning",
            "Stop owning #{name}",
            fields,
            :danger
          )

      true ->
        give =
          Enum.map_join(others, "", fn o ->
            label =
              if value?(i),
                do: "Give it to #{o} (waits for #{o} to agree)",
                else: "Give it to #{o}"

            ~s(<option value="give:#{esc(o)}">#{esc(label)}</option>)
          end)

        """
        <form method=post action="/act/let_go" class=row>#{fields}<input type=hidden name=item value="#{id}">
        <p><label for="to-#{id}">What happens to “#{esc(name)}”</label><select id="to-#{id}" name=to required><option value="">Choose…</option>#{give}<option value="delete">Delete it for everyone (can't be undone)</option></select></p>
        <button>Do this</button></form>
        """
    end
  end

  defp waiting_on_people(i, mine, m) do
    owners = MapSet.new(i.owners)

    mine
    |> Enum.flat_map(fn p ->
      needed =
        if joiners?(i), do: needed(p, %{i.id => %{owners: owners, joiners?: true}}), else: owners

      needed |> MapSet.difference(MapSet.new(p.consents)) |> Enum.to_list()
    end)
    |> Enum.uniq()
    |> people(m, "the others")
  end

  # UX-001 R2: amount as text with an explicit direction; errors shown at the field, input kept.
  # UX-001 R2: amount as text with an explicit direction; errors shown at the field, input kept.
  # REQ-127: how often it happens is chosen explicitly; there is no default.
  defp add_item_form(csrf, form) do
    error = form[:error]
    field = form[:error_field] || :amount
    dir = form[:direction] || "out"
    checked = fn d -> if d == dir, do: " checked", else: "" end

    invalid = fn f ->
      if error && field == f,
        do: ~s( aria-describedby="#{f}-error" aria-invalid="true"),
        else: ""
    end

    # UX-003 C6: the message sits in the field's own group, directly under it
    error_at = fn f -> if error && field == f, do: field_error(f, error), else: "" end

    options =
      [{"", "Choose…"} | Words.item_frequency_choices()]
      |> Enum.map_join("", fn {v, text} ->
        selected = if v != "" and v == form[:frequency], do: " selected", else: ""
        ~s(<option value="#{v}"#{selected}>#{text}</option>)
      end)

    """
    <form method=post action="/act/add_item" class=row id=add-item>#{csrf}
    <p><label for=note>What is it?</label><input id=note name=note required maxlength=200 placeholder="e.g. Rent" value="#{esc(form[:note])}"#{invalid.(:note)}>#{error_at.(:note)}</p>
    <p><label for=amount>Amount</label><input id=amount name=amount inputmode=decimal autocomplete=off placeholder="e.g. 62.40" value="#{esc(form[:amount])}"#{invalid.(:amount)}>#{error_at.(:amount)}</p>
    <p><label for=frequency>How often?</label><select id=frequency name=frequency required#{invalid.(:frequency)}>#{options}</select>#{error_at.(:frequency)}</p>
    <p><label for=on>Date it happens <span class=hint>(optional)</span></label><input id=on name=on type=date value="#{esc(form[:on])}"#{invalid.(:on)}>#{error_at.(:on)}</p>
    <fieldset class=direction><legend>Money</legend>
    <label class=check><input type=radio name=direction value=out#{checked.("out")}> Money out</label>
    <label class=check><input type=radio name=direction value=in#{checked.("in")}> Money in</label></fieldset>
    <button>Add</button></form>
    """
  end

  def export_page(export, names) do
    m = export.member

    {balances, rest} =
      export.items
      |> Enum.sort_by(&String.downcase(title(&1)))
      |> Enum.split_with(&Balances.balance?/1)

    {values, money} = Enum.split_with(rest, &value?/1)

    render_balances =
      Enum.map_join(balances, "", fn i ->
        readings = Enum.filter(Map.get(i, :readings, []), &is_map/1)

        latest =
          case List.last(readings) do
            nil -> "No balance yet."
            r -> "#{balance_text(i, r)} as of #{date_text(r.on)}."
          end

        "<li><b>#{esc(title(i))}</b> (#{esc(kind_words(i))}). #{esc(latest)} #{length(readings)} #{if length(readings) == 1, do: "balance", else: "balances"} recorded.</li>"
      end)

    render = fn list ->
      Enum.map_join(list, "", fn i ->
        """
        <li><b>#{esc(display(i))}</b>#{amount_text(i.attrs)}. Owned by #{esc(people(i.owners, m))}.
        #{if i.grantees != [], do: "#{esc(people(i.grantees, m))} can see it too.", else: ""}
        <details><summary>History</summary><ol>#{Enum.map_join(i.ledger, "", &"<li>#{esc(event_text(&1))}</li>")}</ol></details></li>
        """
      end)
    end

    links =
      export.links
      |> Enum.sort_by(fn {i, v} ->
        {String.downcase(names[i] || ""), String.downcase(names[v] || "")}
      end)
      |> Enum.map_join("", fn {i, v} ->
        "<li>#{esc(names[i])} → #{esc(names[v])}</li>"
      end)

    """
    <section class=card><h2>What you'd take with you</h2>
    <p class=hint>Everything you own, with its history, and your own links between them. Nothing that belongs to anyone else.</p>
    #{if export.items == [], do: "<p class=empty>You don't own anything yet.</p>", else: ""}
    #{if money != [], do: "<h3>Items</h3><ul>#{render.(money)}</ul>", else: ""}
    #{if values != [], do: "<h3>What matters to you</h3><ul>#{render.(values)}</ul>", else: ""}
    #{if balances != [], do: "<h3>Balances and debts</h3><ul>#{render_balances}</ul>", else: ""}
    #{if links != "", do: "<h3>Your links</h3><ul>#{links}</ul>", else: ""}
    <p><a href="/export.json" download="findependence-export.json">Save as a file</a> · <a href="/">Back</a></p></section>
    """
  end

  # REQ-166: deleting something that holds other records is previewed by name and confirmed.
  def confirm_page(action, fields, what, csrf, keepers \\ []) do
    {title, body, yes} =
      case action do
        "delete_plan" ->
          steps = if keepers == 1, do: "Its 1 step", else: "Its #{keepers} steps"

          {"Delete the plan “#{what}”?",
           "#{steps} will be deleted with it. Your real items and totals don't change. This can't be undone.",
           "Yes, delete the plan"}

        "delete" ->
          {"Delete “#{what}”?",
           "It will be gone for everyone who could see it, with its history. This can't be undone.",
           "Yes, delete"}

        "relinquish" ->
          {"Stop owning “#{what}”?",
           "You'll stop seeing it unless someone shares it with you again. #{people(keepers)} will keep it. To own it again, #{if length(keepers) == 1, do: "they", else: "all of them"} would have to agree.",
           "Yes, stop owning"}
      end

    hidden =
      Enum.map_join(fields, "", fn {k, v} ->
        ~s(<input type=hidden name="#{k}" value="#{esc(v)}">)
      end)

    """
    <section class="card warn"><h2>#{esc(title)}</h2><p>#{esc(body)}</p>
    <form method=post action="/act/#{action}">#{csrf}#{hidden}<button class=danger>#{esc(yes)}</button></form>
    <p><a href="#{back_from(action, fields)}">No, go back</a></p></section>
    """
  end

  # ---------------------------------------------------------------------------
  defp message(nil), do: ""
  defp message({:ok, text}), do: ~s(<p class="msg ok" role="status">#{esc(text)}</p>)
  defp message({:error, text}), do: ~s(<p class="msg err" role="alert">#{esc(text)}</p>)

  # ---------------------------------------------------------------------------
  # Helpers

  defp back_from("delete_plan", %{"plan" => id}), do: "/plans/" <> URI.encode_www_form(id)
  defp back_from(_action, _fields), do: "/"

  defp value?(i), do: Map.get(i.attrs, :kind) == :value

  # Values and plans are shared only with the agreement of each person being added (REQ-115).

  # Sorted by name, so choices keep a stable order (WI-030).
  defp options(entries),
    do:
      entries
      |> Enum.sort_by(&String.downcase(title(&1)))
      |> Enum.map_join("", &~s(<option value="#{esc(&1.id)}">#{esc(title(&1))}</option>))

  # UX-003 C7: an action that deletes, gives up ownership, or leaves is styled as destructive (:danger)
  defp button(action, fields, label, aria, csrf, variant \\ nil) do
    hidden =
      Enum.map_join(fields, "", fn {k, v} ->
        ~s(<input type=hidden name="#{k}" value="#{esc(v)}">)
      end)

    class = if variant == :danger, do: " class=danger", else: ""

    ~s(<form class=inline method=post action="/act/#{action}">#{csrf}#{hidden}<button#{class} aria-label="#{esc(aria)}">#{esc(label)}</button></form>)
  end

  # Everything but monthly and one-off: the per-month figure the totals use (REQ-128).
  defp per_month_hint(attrs) do
    case Words.per_month_figure(attrs) do
      nil -> ""
      figure -> ~s(<p class=hint>Counted as #{esc(figure)} a month in your totals.</p>)
    end
  end

  def esc(nil), do: ""
  def esc(v) when is_binary(v), do: Plug.HTML.html_escape(v)
  def esc(v), do: v |> to_string() |> Plug.HTML.html_escape()

  # ---------------------------------------------------------------------------
  # Words shared with the hosted form (FindependenceShared.Words, WI-075): here member ids are the names.

  defp kind_words(i), do: Words.kind_words(i)
  defp balance_text(i, r), do: Words.balance_text(i, r)
  defp plain_amount(c), do: Words.plain_amount(c)
  defdelegate rate_text(bp), to: Words
  def date_text(iso, today \\ FindependenceApp.Web.today()), do: Words.date_text(iso, today)
  defdelegate month_text(mo), to: Words
  defp money_line(attrs), do: Words.money_line(attrs)
  defp amount_text(attrs), do: Words.amount_text(attrs)
  defp figure_text(attrs), do: Words.figure_text(attrs)
  defp frequency_text(attrs), do: Words.frequency_text(attrs)
  defdelegate format_amount(amount), to: Words
  defp title(i), do: Words.title(i)
  defp display(i), do: Words.display(i)
  defp joiners?(i), do: Words.joiners?(i)
  defp owners_of(visible), do: Words.owners_of(visible)
  defp needed(p, owners_of), do: Words.needed(p, owners_of)
  defdelegate names(h, m), to: Words
  defp people(list, me \\ nil, empty \\ "No one"), do: Words.people(list, me, empty)
  defp proposal_text(p, names, m), do: Words.proposal_text(p, names, m)
  defp counted_note(h, m, account_ids), do: Words.counted_note(h, m, account_ids)
  defp partial?(h, m, account_ids), do: Words.partial?(h, m, account_ids)
  defp agreement_text(sole?, value?), do: Words.agreement_text(sole?, value?)
  def event_text(entry), do: Words.event_text(entry)

  def outcome(action, params, before, after_h, m),
    do: Words.outcome(action, params, before, after_h, m)

  # Shared with the hosted form (FindependenceShared.PlanWords, GoalWords, PortabilityWords; WI-076)
  defp step_text(h, m, step), do: PlanWords.step_text(h, m, step)
  defp lasts_sentence(p), do: GoalWords.lasts_sentence(p)
  defp lasts_short(p), do: GoalWords.lasts_short(p)
  defp pct_text(bp), do: GoalWords.pct_text(bp)
  defp about(cents), do: GoalWords.about(cents)
  defp about_signed(cents), do: GoalWords.about_signed(cents)
  defp where_text(where), do: PortabilityWords.where_text(where)
  defp what_text(what), do: PortabilityWords.what_text(what)
  def export_json(export), do: PortabilityWords.export_json(export)
end
