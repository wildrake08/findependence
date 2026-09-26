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
    no_owners: "Something needs at least one owner.",
    no_change: "That wouldn't change anything.",
    sole_owner: "You're the only owner. To let go of it, give it to someone else or delete it.",
    not_sole_owner: "Only a sole owner can delete something. You can stop owning it instead.",
    still_owner:
      "You still own some things. Stop owning them, give them away, or delete them first.",
    already_linked: "Those are already linked.",
    not_a_value: "You can only link to one of your values.",
    cannot_link_a_value: "A value can't be linked to another value.",
    unknown_action: "That didn't work."
  }

  @done %{
    "add_item" => "Added.",
    "add_value" => "Value added.",
    "grant" => "Done. If others own it too, they need to agree first.",
    "revoke" => "They can no longer see it.",
    "owners" => "Proposed. It takes effect when everyone who needs to has agreed.",
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

  # UX-001 R1: the home page lists things compactly and links to one page per thing; no per-item
  # action forms here. R7: anything waiting for the member comes first.
  def home(h, m, csrf, message \\ nil, form \\ %{}) do
    visible = View.visible_items(h, m)
    {values, items} = Enum.split_with(visible, &value?/1)
    names = names(h, m)
    owned = Enum.filter(visible, &(m in &1.owners))
    owners_of = owners_of(visible)
    {mine, theirs} = Household.pending(h, m) |> Enum.split_with(&(m not in &1.consents))

    """
    #{message(message)}
    #{if mine != [], do: ~s(<section class="card attention" id=waiting><h2>Waiting for you</h2>#{pending_list(mine, names, owners_of, m, csrf, :respond)}</section>), else: ""}
    <section class=card><h2>Your money items</h2>
    <p class=hint>Things you own, and things others have chosen to show you. Open one to share it, change who owns it, or link it to what matters to you.</p>
    #{thing_list(items, m, mine ++ theirs, :item)}
    #{add_item_form(csrf, form)}</section>

    <section class=card><h2>What matters to you</h2>
    <p class=hint>In your own words. Nothing here is scored or judged, and only you decide who sees it.</p>
    #{thing_list(values, m, mine ++ theirs, :value)}
    <form method=post action="/act/add_value" class=row>#{csrf}
    <p><label for=label>Something you value</label><input id=label name=label required placeholder="e.g. Time with the kids"></p>
    <button>Add value</button></form></section>

    <section class=card><h2>Your money and what matters to you</h2>
    <p class=hint>Totals of what you can see, by what you've linked it to. To link an item, open it. Your links are visible only to you, and something linked to two values counts toward both.</p>
    #{distribution(Alignment.distribution(h, m), values)}</section>

    #{if theirs != [], do: ~s(<section class=card><h2>Waiting for others</h2>#{pending_list(theirs, names, owners_of, m, csrf, :waiting)}</section>), else: ""}

    <section class=card><h2>Leaving</h2>
    <p><a href="/export">See everything you'd take with you</a>, and save it as a file.</p>
    #{leave_block(owned, csrf)}</section>
    """
  end

  @doc "How many changes are waiting for this member's answer (UX-001 R7: shown in the header)."
  def waiting_count(h, m), do: h |> Household.pending(m) |> Enum.count(&(m not in &1.consents))

  # A compact, action-free list: each thing links to its own page.
  defp thing_list([], _m, _pending, :item), do: "<p class=empty>No money items yet.</p>"
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
            do:
              ~s(<td class=num data-label="Amount">#{esc(format_amount(i.attrs[:amount]))}</td>),
            else: ""

        """
        <tr><td data-label="#{if kind == :item, do: "Item", else: "Value"}"><a href="/items/#{esc(i.id)}"><b>#{esc(title(i))}</b></a>#{badge}</td>#{amount}
        <td data-label="Owned by">#{esc(people(i.owners, m))}</td>
        <td data-label="Who else can see it">#{visibility_summary(i, m)}</td></tr>
        """
      end)

    head =
      if kind == :item,
        do: "<th>Item</th><th>Amount</th><th>Owned by</th><th>Who else can see it</th>",
        else: "<th>Value</th><th>Owned by</th><th>Who else can see it</th>"

    ~s(<div class=scroll><table class=stack><thead><tr>#{head}</tr></thead><tbody>#{rows}</tbody></table></div>)
  end

  defp visibility_summary(i, m) do
    cond do
      m not in i.owners -> "Shared with you"
      Map.get(i, :grantees, []) == [] -> "Only the owners"
      true -> esc(people(i.grantees, m))
    end
  end

  @doc """
  UX-001 R1: everything about one thing on one page. Owners see who can see it, sharing, owners,
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
        #{if value?(i), do: ~s(<p class=hint>Something you value.</p>), else: ~s(<p class="amount-big">#{esc(format_amount(i.attrs[:amount]))}</p>)}
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
    <p>#{esc(people(i.owners, m))} let you see this. Only owners can change who sees it or view its history.</p>
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
       "Share", "Propose change",
       "Anyone you add as an owner has to agree before it takes effect."}

  defp agreement_text(false, value?),
    do:
      {"Owned jointly, so changes here wait until every owner agrees#{if value?, do: " (and anyone being added)", else: ""}.",
       "Propose sharing", "Propose change",
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
          do: "<p class=empty>Nothing linked yet. Open a money item to link it here.</p>",
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

    actions =
      if length(Enum.to_list(i.owners)) == 1 do
        ~s(<a class="button-link" href="#owners" aria-label="Give away #{esc(name)}">Give away…</a>) <>
          ~s(<form class=inline method=post action="/confirm/delete">#{fields}<input type=hidden name=item value="#{id}"><button class=danger aria-label="Delete #{esc(name)}">Delete…</button></form>)
      else
        ~s(<form class=inline method=post action="/confirm/relinquish">#{fields}<input type=hidden name=item value="#{id}"><button aria-label="Stop owning #{esc(name)}">Stop owning…</button></form>)
      end

    ~s(<section class=card><h2>Letting go</h2>#{actions}</section>)
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
      do: button("withdraw", %{"proposal" => p.id}, "Withdraw", "Withdraw this proposal", fields),
      else: ""
  end

  defp proposal_text(p, names, m) do
    name = names[p.item_id] || (p[:attrs] && (p.attrs[:label] || p.attrs[:note])) || "something"

    case p.change do
      {:grant, g} ->
        "Let #{g} see “#{name}”."

      {:owners, owners} ->
        if m in owners and not Map.has_key?(names, p.item_id),
          do: "You're invited to share “#{name}” with #{people(MapSet.delete(owners, m))}.",
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
          else: "Proposed. Waiting for #{waiting_on.()} to agree."

      "revoke" ->
        "#{params["member"]} can no longer see “#{name}”."

      "owners" ->
        if now && MapSet.equal?(now.owners, MapSet.new(List.wrap(params["owners"]))),
          do: "“#{name}” is now owned by #{people(now.owners, m)}.",
          else: "Proposed. Waiting for #{waiting_on.()} to agree."

      "consent" ->
        consent_outcome(before, after_h, m, params)

      "withdraw" ->
        "Withdrawn. Nothing was changed."

      "relinquish" ->
        "You no longer own “#{name}”."

      "delete" ->
        "Deleted “#{name}”."

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

  defp distribution(%{by_value: bv, unlinked: u}, values) do
    label = Map.new(values, &{&1.id, &1.attrs[:label]})

    rows =
      bv
      |> Enum.sort_by(fn {id, _} -> label[id] end)
      |> Enum.map_join("", fn {id, %{sum: s, count: c}} ->
        ~s(<tr><td><a href="/items/#{esc(id)}">#{esc(label[id])}</a></td><td class=num>#{esc(format_amount(s))}</td><td class=num>#{c}</td></tr>)
      end)

    """
    <div class=scroll><table><thead><tr><th>What matters to you</th><th>Total</th><th>Items</th></tr></thead><tbody>#{rows}
    <tr class=muted><td>Not linked to anything</td><td class=num>#{esc(format_amount(u.sum))}</td><td class=num>#{u.count}</td></tr></tbody></table></div>
    """
  end

  defp leave_block([], csrf) do
    ~s(<form method=post action="/confirm/leave">#{csrf}<button class=danger>Leave the household…</button></form>)
  end

  defp leave_block(_owned, _csrf) do
    "<p class=hint>To leave, first stop owning, give away, or delete what you own. Your export shows what that is.</p>"
  end

  # UX-001 R2: amount as text with an explicit direction; errors shown at the field, input kept.
  defp add_item_form(csrf, form) do
    error = form[:error]
    dir = form[:direction] || "out"
    checked = fn d -> if d == dir, do: " checked", else: "" end
    described = if error, do: ~s( aria-describedby="amount-error" aria-invalid="true"), else: ""

    """
    <form method=post action="/act/add_item" class=row id=add-item>#{csrf}
    <p><label for=note>What is it?</label><input id=note name=note required placeholder="e.g. Rent" value="#{esc(form[:note])}"></p>
    <p><label for=amount>Amount</label><input id=amount name=amount inputmode=decimal autocomplete=off placeholder="e.g. 62.40" value="#{esc(form[:amount])}"#{described}></p>
    <fieldset class=direction><legend>Money</legend>
    <label class=check><input type=radio name=direction value=out#{checked.("out")}> Money out</label>
    <label class=check><input type=radio name=direction value=in#{checked.("in")}> Money in</label></fieldset>
    <button>Add</button>
    #{if error, do: ~s(<p class="field-error" id="amount-error" role="alert">#{esc(error)}</p>), else: ""}</form>
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
        #{if i.grantees != [], do: "Also visible to #{esc(people(i.grantees, m))}.", else: ""}
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
    #{if money != [], do: "<h3>Money items</h3><ul>#{render.(money)}</ul>", else: ""}
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

        "leave" ->
          {"Leave this household?",
           "You'll stop seeing anything shared with you, and your links and passphrase stop working here. This can't be undone. Save your export first if you want to keep it.",
           "Yes, leave"}
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

  defp amount_text(%{amount: a}) when is_integer(a), do: ", #{format_amount(a)}"
  defp amount_text(_), do: ""

  # Amounts are integer cents (WI-021).
  def format_amount(amount), do: FindependenceApp.Money.format(amount)

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
