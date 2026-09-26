defmodule FindependenceApp.Web.Html do
  @moduledoc """
  Page rendering for the local interface (WI-013). Pure functions of a member's own view of the
  household; nothing here reads data the member cannot see. Every user-supplied string passes
  through `esc/1`.
  """

  alias Findependence.{Alignment, Household, Ledger, View}

  # ---------------------------------------------------------------------------
  # Plain-language text

  @errors %{
    not_found: "That isn't available to you.",
    not_a_member: "That person isn't in this household.",
    already_owner: "They already own it.",
    already_granted: "They can already see it.",
    not_granted: "They can't see it now, so there is nothing to stop.",
    no_owners: "An item or value needs at least one owner.",
    no_change: "That wouldn't change anything.",
    sole_owner:
      "You're the only owner, so you can't stop owning it. Give it away or delete it instead.",
    not_sole_owner: "Only a sole owner can delete it. You can stop owning it instead.",
    still_owner:
      "You still own items or values. Give them away, stop owning them, or delete them first.",
    no_choice: "Choose what should happen to it first.",
    already_linked: "Those are already linked.",
    not_a_value: "You can only link to one of your values.",
    cannot_link_a_value: "A value can't be linked to another value.",
    unknown_action: "That didn't work.",
    file_changed:
      "The household file was changed by another copy of Findependence while you were working. Nothing was saved, so nothing was lost. The page now shows the latest version; please try again."
  }

  @done %{
    "add_item" => "Added.",
    "add_value" => "Value added.",
    "grant" => "Done. If others own it too, they need to agree first.",
    "revoke" => "They can no longer see it.",
    "owners" => "Requested. It takes effect when everyone who needs to has agreed.",
    "consent" => "You agreed.",
    "relinquish" => "You no longer own it.",
    "delete" => "Deleted.",
    "link" => "Linked.",
    "unlink" => "Unlinked.",
    "withdraw" => "Withdrawn. Nothing was changed."
  }

  @doc """
  WI-020: a warning when the household file shows signs of being changed outside the app. Plain
  language, with no item names, since an altered file can't be trusted to name things.
  """
  def integrity_banner([]), do: ""

  def integrity_banner(issues) do
    """
    <section class="card warn" role="alert"><h2>This household file may have been changed outside Findependence</h2>
    <p>Some sharing or ownership details don't match what the app itself wrote (#{length(issues)} #{if length(issues) == 1, do: "sign", else: "signs"}). Nothing new has been shared because of this: the app only shares with people it added itself.</p>
    <p>Until this is sorted out, be careful about what you add or share, and talk to the person running the study.</p>
    </section>
    """
  end

  def error_text(reason), do: Map.get(@errors, reason, "That didn't work.")
  @doc false
  def error_reasons, do: Map.keys(@errors)
  def done_text(action), do: Map.get(@done, action)

  # ---------------------------------------------------------------------------
  # Pages

  def login(members, csrf, error \\ nil, notice \\ nil) do
    options = Enum.map_join(members, "", &"<option>#{esc(&1)}</option>")

    """
    #{lock_notice(notice)}
    #{if error, do: ~s(<p class="msg err" role="alert">#{esc(error)}</p>), else: ""}
    <section class=card><h2>Unlock</h2>
    <form method=post action="/login">#{csrf}
    <p><label for=member>Who are you?</label><select id=member name=member>#{options}</select></p>
    <p><label for=pass>Your passphrase</label><input id=pass type=password name=passphrase autocomplete=off required></p>
    <button>Unlock</button></form>
    <p class=hint>One person at a time. Press <b>Lock</b> when you're done; it also locks itself after 15 minutes.</p></section>
    """
  end

  # UX-001 R4
  defp lock_notice(:idle),
    do:
      ~s(<p class="msg info" role="status">Locked after 15 minutes without use. Unlock to carry on.</p>)

  defp lock_notice(:idle_action),
    do:
      ~s(<p class="msg info" role="status">Locked after 15 minutes without use. Your last action was not saved. Unlock and do it again.</p>)

  defp lock_notice(_), do: ""

  # UX-001 R1: the home page lists items and values compactly, each linking to its own page; no
  # per-item action forms here. R7: anything waiting for the member comes first. R9: the words used
  # here follow the glossary in `FindependenceApp.Web.Glossary`.
  def home(h, m, csrf, message \\ nil, form \\ %{}) do
    visible = View.visible_items(h, m)
    {values, items} = Enum.split_with(visible, &value?/1)
    names = names(h, m)
    owners_of = owners_of(visible)
    {mine, theirs} = Household.pending(h, m) |> Enum.split_with(&(m not in &1.consents))

    """
    #{message(message)}
    #{if mine != [], do: ~s(<section class="card attention" id=waiting><h2>Waiting for you</h2>#{pending_list(mine, names, owners_of, m, csrf, :respond)}</section>), else: ""}
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

    <section class=card><h2>Your money and what matters to you</h2>
    <p class=hint>Totals of what you can see, by what you've linked it to. Items that repeat are shown per month (weekly, every-two-weeks, and yearly amounts are converted); one-off items are shown apart. To link an item, open it. Only you can see your links, and an item linked to two values counts toward both.</p>
    #{distribution(Alignment.distribution(h, m), values)}</section>

    #{if theirs != [], do: ~s(<section class=card><h2>Waiting for others</h2>#{pending_list(theirs, names, owners_of, m, csrf, :waiting)}</section>), else: ""}

    <section class=card><h2>Leaving</h2>
    <p><a href="/export">See everything you'd take with you</a>, and save it as a file.</p>
    <p><a class="button-link" href="/leave">Leave the household…</a></p></section>
    """
  end

  @doc "How many changes are waiting for this member's answer (UX-001 R7: shown in the header)."
  def waiting_count(h, m), do: h |> Household.pending(m) |> Enum.count(&(m not in &1.consents))

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

        amount =
          if kind == :item,
            do: ~s(<td role=cell class=num data-label="Amount">#{esc(money_line(i.attrs))}</td>),
            else: ""

        """
        <tr role=row><td role=cell data-label="#{if kind == :item, do: "Item", else: "Value"}"><a href="/items/#{esc(i.id)}"><b>#{esc(title(i))}</b></a>#{badge}</td>#{amount}
        <td role=cell data-label="Owned by">#{esc(people(i.owners, m))}</td>
        <td role=cell data-label="Who else can see it">#{visibility_summary(i, m)}</td></tr>
        """
      end)

    head =
      if kind == :item,
        do: ["Item", "Amount", "Owned by", "Who else can see it"],
        else: ["Value", "Owned by", "Who else can see it"]

    # UX-001 R10: explicit roles, because the phone layout restyles the table with display:block,
    # which can remove its table semantics in some browsers; the header row stays readable to
    # screen readers while hidden on screen.
    head = Enum.map_join(head, "", &"<th role=columnheader scope=col>#{&1}</th>")
    caption = if kind == :item, do: "Your items", else: "Your values"

    ~s(<div class=scroll><table class=stack role=table aria-label="#{caption}"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}</tbody></table></div>)
  end

  defp visibility_summary(i, m) do
    cond do
      m not in i.owners -> "Shared with you"
      Map.get(i, :grantees, []) == [] -> "Only the owners"
      true -> esc(people(i.grantees, m))
    end
  end

  @doc """
  UX-001 R1: everything about one item or value on one page. Owners see who can see it, sharing, owners,
  what is waiting, links, history, and how to let go. Someone it is shared with sees it, who shared
  it, and their own links. Returns `nil` if the member can't see it.
  """
  def item_page(h, m, id, csrf, message \\ nil) do
    case View.get(h, m, id) do
      {:ok, i} ->
        # Every form on this page returns here (UX-001 R6).
        fields = csrf <> ~s(<input type=hidden name=return value="/items/#{esc(id)}">)
        owner? = m in i.owners
        visible = View.visible_items(h, m)
        names = names(h, m)
        owners_of = owners_of(visible)
        pending = h |> Household.pending(m) |> Enum.filter(&(&1.item_id == id))
        others = h.members |> MapSet.delete(m) |> Enum.sort()

        """
        <p><a href="/">← Everything</a></p>
        #{message(message)}
        <section class=card><h2>#{esc(title(i))}</h2>
        #{if value?(i), do: ~s(<p class=hint>A value.</p>), else: ~s(<p class="amount-big">#{esc(money_line(i.attrs))}</p>#{per_month_hint(i.attrs)})}
        #{if owner?, do: owner_sections(i, m, others, pending, owners_of, names, fields), else: shared_with_me(i, m)}
        </section>
        #{links_section(h, i, m, visible, fields)}
        #{if owner?, do: history_section(h, m, i) <> let_go_section(i, fields), else: ""}
        """

      _ ->
        nil
    end
  end

  defp owners_of(visible),
    do: Map.new(visible, &{&1.id, %{owners: MapSet.new(&1.owners), value?: value?(&1)}})

  defp shared_with_me(i, m) do
    """
    <p>#{esc(people(i.owners, m))} shared this with you. Only owners can change who can see it or view its history.</p>
    """
  end

  # {explanation, share button, owners button, owners hint}, by who must agree (REQ-103, REQ-107, REQ-115)
  defp agreement_text(true = _sole?, false = _value?),
    do:
      {"You're the only owner, so changes here take effect right away.", "Share", "Change owners",
       "This takes effect right away. To give it away, tick only the other person; you'll stop owning it."}

  defp agreement_text(true, true),
    do:
      {"You're the only owner. Sharing takes effect right away. Adding someone as an owner of a value waits for them to agree.",
       "Share", "Request change",
       "Anyone you add as an owner has to agree before it takes effect."}

  defp agreement_text(false, value?),
    do:
      {"Owned jointly, so changes here wait until every owner agrees#{if value?, do: " (and anyone being added)", else: ""}.",
       "Request sharing", "Request change",
       "Every current owner has to agree before this takes effect."}

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
    <fieldset><legend>Owners of “#{esc(title(i))}”</legend>#{checkboxes}</fieldset>
    <p class=hint>Ticked now: the current owners. #{owners_hint}</p>
    <button>#{owners_label}</button></form>
    """
  end

  # Links belong to the member (REQ-112): a money item links to values; a value lists what's linked to it.
  defp links_section(h, i, m, visible, fields) do
    links = Alignment.links(h, m)
    names = Map.new(visible, &{&1.id, title(&1)})

    if value?(i) do
      linked = for {item, v} <- links, v == i.id, do: item

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
      linked = for {item, v} <- links, item == i.id, do: v
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
    case Ledger.read(h, m, i.id) do
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
        ~s(<form class=inline method=post action="/confirm/relinquish">#{fields}<input type=hidden name=item value="#{id}"><button aria-label="Stop owning #{esc(name)}">Stop owning…</button></form>)
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
          if mode != :item and Map.has_key?(names, p.item_id),
            do: ~s( <a href="/items/#{esc(p.item_id)}">Open</a>),
            else: ""

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

  defp proposal_text(p, names, m) do
    name = names[p.item_id] || (p[:attrs] && (p.attrs[:label] || p.attrs[:note])) || "an item"

    case p.change do
      {:grant, g} ->
        "Share “#{name}” with #{g}."

      {:owners, owners} ->
        if m in owners and not Map.has_key?(names, p.item_id),
          do: "Request: own “#{name}” together with #{people(MapSet.delete(owners, m))}.",
          else: "Make “#{name}” owned by #{people(owners)}."
    end
  end

  # Who must agree: the current owners, and for a shared value also anyone being added (REQ-115).
  defp needed(%{item_id: id, change: change}, owners_of) do
    %{owners: owners, value?: value?} =
      Map.get(owners_of, id, %{owners: MapSet.new(), value?: false})

    case change do
      {:owners, new} when value? -> MapSet.union(owners, MapSet.difference(new, owners))
      _ -> owners
    end
  end

  @doc """
  UX-001 R6: what actually happened, worded from the household before and after the action, so
  the member can tell an applied change from one still waiting for someone.
  """
  def outcome(action, params, before, after_h, m) do
    names = Map.merge(names(before, m), names(after_h, m))
    item = params["item"]
    name = names[item] || "it"
    now = after_h.items[item]
    waiting_on = fn -> waiting_names(after_h, m, item) end

    case action do
      "add_item" ->
        "Added “#{params["note"]}”."

      "add_value" ->
        "Added “#{params["label"]}”."

      "grant" ->
        if now && params["member"] in now.grantees,
          do: "#{params["member"]} can now see “#{name}”.",
          else: "Requested. Waiting for #{waiting_on.()} to agree."

      "revoke" ->
        "#{params["member"]} can no longer see “#{name}”."

      "owners" ->
        if now && MapSet.equal?(now.owners, MapSet.new(List.wrap(params["owners"]))),
          do: "“#{name}” is now owned by #{people(now.owners, m)}.",
          else: "Requested. Waiting for #{waiting_on.()} to agree."

      "consent" ->
        consent_outcome(before, after_h, m, params)

      "withdraw" ->
        "Withdrawn. Nothing was changed."

      "relinquish" ->
        "You no longer own “#{name}”."

      "delete" ->
        "Deleted “#{name}”."

      "let_go" ->
        case params["to"] do
          "give:" <> to -> outcome("owners", Map.put(params, "owners", [to]), before, after_h, m)
          _ -> outcome("delete", params, before, after_h, m)
        end

      "link" ->
        "Linked “#{name}” to “#{names[params["value"]]}”."

      "unlink" ->
        "Unlinked “#{name}” from “#{names[params["value"]]}”."

      _ ->
        "Done."
    end
  end

  defp consent_outcome(before, after_h, m, params) do
    id = String.to_integer(to_string(params["proposal"] || "0"))

    case {before.proposals[id], after_h.proposals[id]} do
      {nil, _} -> "Done."
      {_, nil} -> "You agreed, and the change has been made."
      {p, _} -> "You agreed. Still waiting for #{waiting_names(after_h, m, p.item_id)}."
    end
  rescue
    ArgumentError -> "Done."
  end

  defp waiting_names(h, m, item_id) do
    owners_of = owners_of(View.visible_items(h, m))

    h
    |> Household.pending(m)
    |> Enum.filter(&(&1.item_id == item_id))
    |> Enum.flat_map(
      &(needed(&1, owners_of)
        |> MapSet.difference(MapSet.new(&1.consents))
        |> Enum.to_list())
    )
    |> Enum.uniq()
    |> people(m, "the others")
  end

  # REQ-126: per month in and out over repeating items, one-off in and out apart; no evaluation.
  # Stacked on phones like the item tables, with explicit table roles (WI-024).
  defp distribution(%{by_value: bv, unlinked: u}, values) do
    label = Map.new(values, &{&1.id, &1.attrs[:label]})

    row = fn name, b, class ->
      cells =
        [
          {"Money in, per month", b.per_month.in},
          {"Money out, per month", b.per_month.out},
          {"One-off in", b.one_off.in},
          {"One-off out", b.one_off.out}
        ]
        |> Enum.map_join("", fn {head, cents} ->
          ~s(<td role=cell class=num data-label="#{head}">#{esc(format_amount(cents))}</td>)
        end)

      ~s(<tr role=row#{class}><td role=cell data-label="Value">#{name}</td>#{cells}<td role=cell class=num data-label="Items">#{b.count}</td></tr>)
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
        "Money in, per month",
        "Money out, per month",
        "One-off in",
        "One-off out",
        "Items"
      ]
      |> Enum.map_join("", &"<th role=columnheader scope=col>#{&1}</th>")

    """
    <div class=scroll><table class=stack role=table aria-label="Totals by value"><thead role=rowgroup><tr role=row>#{head}</tr></thead><tbody role=rowgroup>#{rows}
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
    visible = View.visible_items(h, m)
    {owned, shared} = Enum.split_with(visible, &(m in &1.owners))
    owned = Enum.sort_by(owned, &String.downcase(title(&1)))
    others = h.members |> MapSet.delete(m) |> Enum.sort()
    pending = Household.pending(h, m)

    rows =
      Enum.map_join(owned, "", fn i ->
        ~s(<li class=leave-row><a href="/items/#{esc(i.id)}"><b>#{esc(title(i))}</b></a> #{leave_action(i, m, others, pending, fields)}</li>)
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
    <p><a href="/">← Everything</a></p>
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
          button("relinquish", %{"item" => i.id}, "Stop owning", "Stop owning #{name}", fields)

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
        if value?(i), do: needed(p, %{i.id => %{owners: owners, value?: true}}), else: owners

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

    options =
      [
        {"", "Choose…"},
        {"monthly", "Every month"},
        {"biweekly", "Every two weeks"},
        {"weekly", "Every week"},
        {"yearly", "Every year"},
        {"one_off", "One-off"}
      ]
      |> Enum.map_join("", fn {v, text} ->
        selected = if v != "" and v == form[:frequency], do: " selected", else: ""
        ~s(<option value="#{v}"#{selected}>#{text}</option>)
      end)

    """
    <form method=post action="/act/add_item" class=row id=add-item>#{csrf}
    <p><label for=note>What is it?</label><input id=note name=note required placeholder="e.g. Rent" value="#{esc(form[:note])}"></p>
    <p><label for=amount>Amount</label><input id=amount name=amount inputmode=decimal autocomplete=off placeholder="e.g. 62.40" value="#{esc(form[:amount])}"#{invalid.(:amount)}></p>
    <p><label for=frequency>How often?</label><select id=frequency name=frequency required#{invalid.(:frequency)}>#{options}</select></p>
    <fieldset class=direction><legend>Money</legend>
    <label class=check><input type=radio name=direction value=out#{checked.("out")}> Money out</label>
    <label class=check><input type=radio name=direction value=in#{checked.("in")}> Money in</label></fieldset>
    <button>Add</button>
    #{if error, do: ~s(<p class="field-error" id="#{field}-error" role="alert">#{esc(error)}</p>), else: ""}</form>
    """
  end

  def export_page(export, names) do
    m = export.member

    {values, money} =
      export.items |> Enum.sort_by(&String.downcase(title(&1))) |> Enum.split_with(&value?/1)

    render = fn list ->
      Enum.map_join(list, "", fn i ->
        """
        <li><b>#{esc(title(i))}</b>#{amount_text(i.attrs)}. Owned by #{esc(people(i.owners, m))}.
        #{if i.grantees != [], do: "#{esc(people(i.grantees, m))} can see it too.", else: ""}
        <details><summary>History</summary><ol>#{Enum.map_join(i.ledger, "", &"<li>#{esc(event_text(&1))}</li>")}</ol></details></li>
        """
      end)
    end

    links =
      Enum.map_join(export.links, "", fn {i, v} ->
        "<li>#{esc(names[i])} → #{esc(names[v])}</li>"
      end)

    """
    <section class=card><h2>What you'd take with you</h2>
    <p class=hint>Everything you own, with its history, and your own links between them. Nothing that belongs to anyone else.</p>
    #{if export.items == [], do: "<p class=empty>You don't own anything yet.</p>", else: ""}
    #{if money != [], do: "<h3>Items</h3><ul>#{render.(money)}</ul>", else: ""}
    #{if values != [], do: "<h3>What matters to you</h3><ul>#{render.(values)}</ul>", else: ""}
    #{if links != "", do: "<h3>Your links</h3><ul>#{links}</ul>", else: ""}
    <p><a href="/export.json" download="findependence-export.json">Save as a file</a> · <a href="/">Back</a></p></section>
    """
  end

  def confirm_page(action, fields, what, csrf, keepers \\ []) do
    {title, body, yes} =
      case action do
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
    <p><a href="/">No, go back</a></p></section>
    """
  end

  # ---------------------------------------------------------------------------
  defp message(nil), do: ""
  defp message({:ok, text}), do: ~s(<p class="msg ok" role="status">#{esc(text)}</p>)
  defp message({:error, text}), do: ~s(<p class="msg err" role="alert">#{esc(text)}</p>)

  # ---------------------------------------------------------------------------
  # Helpers

  @doc "Display names of everything the member can see, by id."
  def names(h, m), do: Map.new(View.visible_items(h, m), &{&1.id, title(&1)})

  def event_text(%{event: e, by: by, details: d}) do
    who = people(by)

    case e do
      :created -> "Created by #{who}"
      :owners_changed -> "Owners set to #{people(d.owners)} (agreed by #{who})"
      :owner_relinquished -> "#{d.owner} stopped owning it"
      :granted -> "Shared with #{d.grantee} (agreed by #{who})"
      :grant_revoked -> "#{who} stopped sharing it with #{d.grantee}"
      :grantee_departed -> "#{d.grantee} left the household"
    end
  end

  defp title(i), do: i.attrs[:note] || i.attrs[:label] || "Untitled"
  defp value?(i), do: Map.get(i.attrs, :kind) == :value

  defp options(entries),
    do: Enum.map_join(entries, "", &~s(<option value="#{esc(&1.id)}">#{esc(title(&1))}</option>))

  defp button(action, fields, label, aria, csrf) do
    hidden =
      Enum.map_join(fields, "", fn {k, v} ->
        ~s(<input type=hidden name="#{k}" value="#{esc(v)}">)
      end)

    ~s(<form class=inline method=post action="/act/#{action}">#{csrf}#{hidden}<button aria-label="#{esc(aria)}">#{esc(label)}</button></form>)
  end

  defp people(list, me \\ nil, empty \\ "No one") do
    list = Enum.sort(Enum.to_list(list))

    case Enum.map(list, &if(&1 == me, do: "you", else: &1)) do
      [] -> empty
      [a] -> a
      xs -> Enum.join(Enum.drop(xs, -1), ", ") <> " and " <> List.last(xs)
    end
  end

  defp amount_text(%{amount: a} = attrs) when is_integer(a), do: ", #{money_line(attrs)}"
  defp amount_text(_), do: ""

  # Amounts are integer cents (WI-021).
  def format_amount(amount), do: FindependenceApp.Money.format(amount)

  @frequency_words %{
    one_off: "one-off",
    weekly: "a week",
    biweekly: "every two weeks",
    monthly: "a month",
    yearly: "a year"
  }

  # REQ-127: an amount is always shown with how often it happens.
  defp money_line(%{amount: a} = attrs) when is_integer(a) do
    f = Alignment.frequency(%{attrs: attrs})
    sep = if f == :one_off, do: ", ", else: " "
    format_amount(a) <> sep <> @frequency_words[f]
  end

  defp money_line(_), do: ""

  # For weeks, two weeks, and years: the per-month figure the totals use (REQ-126).
  defp per_month_hint(%{amount: a} = attrs) when is_integer(a) do
    f = Alignment.frequency(%{attrs: attrs})

    if f in [:weekly, :biweekly, :yearly],
      do:
        ~s(<p class=hint>About #{esc(format_amount(Alignment.per_month(a, f)))} a month in your totals.</p>),
      else: ""
  end

  defp per_month_hint(_), do: ""

  def esc(nil), do: ""
  def esc(v) when is_binary(v), do: Plug.HTML.html_escape(v)
  def esc(v), do: v |> to_string() |> Plug.HTML.html_escape()

  @doc "JSON-safe form of an export (for the saved file)."
  def export_json(export) do
    %{
      "member" => export.member,
      "items" =>
        Enum.map(export.items, fn i ->
          %{
            "id" => i.id,
            "attrs" => Map.new(i.attrs, fn {k, v} -> {to_string(k), json_value(v)} end),
            "owners" => i.owners,
            "grantees" => i.grantees,
            "history" => Enum.map(i.ledger, &event_text/1)
          }
        end),
      "links" => Enum.map(export.links, fn {i, v} -> %{"item" => i, "value" => v} end)
    }
    |> :json.encode()
    |> IO.iodata_to_binary()
  end

  defp json_value(v) when is_atom(v) and v not in [nil, true, false], do: Atom.to_string(v)
  defp json_value(v), do: v
end
