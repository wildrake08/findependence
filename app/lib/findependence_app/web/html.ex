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

  def home(h, m, csrf, message \\ nil, form \\ %{}) do
    visible = View.visible_items(h, m)
    {values, items} = Enum.split_with(visible, &value?/1)
    others = h.members |> MapSet.delete(m) |> Enum.sort()
    names = names(h, m)
    owned = Enum.filter(visible, &(m in &1.owners))
    owners_of = Map.new(visible, &{&1.id, %{owners: MapSet.new(&1.owners), value?: value?(&1)}})

    """
    #{message(message)}
    <section class=card><h2>Your money items</h2>
    <p class=hint>Things you own, and things others have chosen to show you.</p>
    #{items_table(items, h, m, csrf)}
    #{add_item_form(csrf, form)}</section>

    <section class=card><h2>What matters to you</h2>
    <p class=hint>In your own words. Nothing here is scored or judged, and only you decide who sees it.</p>
    #{values_table(values, m, csrf)}
    <form method=post action="/act/add_value" class=row>#{csrf}
    <p><label for=label>Something you value</label><input id=label name=label required placeholder="e.g. Time with the kids"></p>
    <button>Add value</button></form></section>

    <section class=card><h2>Your money and what matters to you</h2>
    <p class=hint>Totals of what you can see, by what you've linked it to. Your links are visible only to you.
    Something linked to two values counts toward both.</p>
    #{distribution(Alignment.distribution(h, m), values)}
    #{link_form(items, values, csrf)}
    #{links_list(Alignment.links(h, m), names, csrf)}</section>

    <section class=card><h2>Waiting for you to agree</h2>#{pending(Household.pending(h, m), names, owners_of, m, csrf)}</section>

    <section class=card><h2>Sharing and ownership</h2>#{sharing(owned, Enum.reject(visible, &(m in &1.owners)), m, others, Household.pending(h, m), owners_of, names, csrf)}</section>

    <section class=card><h2>Leaving</h2>
    <p><a href="/export">See everything you'd take with you</a>, and save it as a file.</p>
    #{leave_block(owned, csrf)}</section>
    """
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
  # Sections

  defp items_table([], _h, _m, _csrf), do: "<p class=empty>Nothing yet.</p>"

  defp items_table(items, h, m, csrf) do
    rows =
      items
      |> Enum.sort_by(&String.downcase(title(&1)))
      |> Enum.map_join("", fn i ->
        owner? = m in i.owners

        """
        <tr><td data-label="Item"><b>#{esc(i.attrs[:note])}</b></td><td class=num data-label="Amount">#{esc(format_amount(i.attrs[:amount]))}</td>
        <td data-label="Owned by">#{esc(people(i.owners, m))}</td>
        <td data-label="Who else can see it">#{if owner?, do: esc(people(Map.get(i, :grantees, []), m, "Only the owners")), else: "Shared with you"}</td>
        <td class=actions>#{if owner?, do: owner_actions(i, m, csrf), else: ""}#{history(h, m, i, owner?)}</td></tr>
        """
      end)

    "<div class=scroll><table class=stack><thead><tr><th>Item</th><th>Amount</th><th>Owned by</th><th>Who else can see it</th><th></th></tr></thead><tbody>#{rows}</tbody></table></div>"
  end

  defp values_table([], _m, _csrf), do: "<p class=empty>No values yet.</p>"

  defp values_table(values, m, csrf) do
    rows =
      values
      |> Enum.sort_by(&String.downcase(title(&1)))
      |> Enum.map_join("", fn v ->
        "<tr><td data-label=\"Value\"><b>#{esc(v.attrs[:label])}</b></td><td data-label=\"Held by\">#{esc(people(v.owners, m))}</td><td class=actions>#{if m in v.owners, do: owner_actions(v, m, csrf), else: ""}</td></tr>"
      end)

    "<div class=scroll><table class=stack><thead><tr><th>Value</th><th>Held by</th><th></th></tr></thead><tbody>#{rows}</tbody></table></div>"
  end

  defp distribution(%{by_value: bv, unlinked: u}, values) do
    label = Map.new(values, &{&1.id, &1.attrs[:label]})

    rows =
      bv
      |> Enum.sort_by(fn {id, _} -> label[id] end)
      |> Enum.map_join("", fn {id, %{sum: s, count: c}} ->
        "<tr><td>#{esc(label[id])}</td><td class=num>#{esc(format_amount(s))}</td><td class=num>#{c}</td></tr>"
      end)

    """
    <div class=scroll><table><thead><tr><th>What matters to you</th><th>Total</th><th>Items</th></tr></thead><tbody>#{rows}
    <tr class=muted><td>Not linked to anything</td><td class=num>#{esc(format_amount(u.sum))}</td><td class=num>#{u.count}</td></tr></tbody></table></div>
    """
  end

  defp link_form([], _, _),
    do: "<p class=hint>Add a money item to link it to what matters to you.</p>"

  defp link_form(_, [], _), do: "<p class=hint>Add a value to link your money items to it.</p>"

  defp link_form(items, values, csrf) do
    """
    <form method=post action="/act/link" class=row>#{csrf}
    <p><label for=link-item>Link</label><select id=link-item name=item>#{options(items)}</select></p>
    <p><label for=link-value>to</label><select id=link-value name=value>#{options(values)}</select></p>
    <button>Link</button></form>
    """
  end

  defp links_list([], _names, _csrf), do: ""

  defp links_list(links, names, csrf) do
    "<h3>Your links</h3><ul class=plain>" <>
      Enum.map_join(links, "", fn {i, v} ->
        "<li>#{esc(names[i])} → #{esc(names[v])} #{button("unlink", %{"item" => i, "value" => v}, "Unlink", "Unlink #{names[i]} from #{names[v]}", csrf)}</li>"
      end) <> "</ul>"
  end

  # Proposals the member has not yet agreed to get an Agree button. Those they already agreed to
  # are listed separately, with who is still needed, so nobody is asked to agree twice.
  defp pending(list, names, owners_of, m, csrf) do
    {mine, others} = Enum.split_with(list, &(m not in &1.consents))

    waiting_for_you =
      if mine == [],
        do:
          "<p class=empty>Nothing is waiting for you.</p><p class=hint>Changes only need agreement when something has more than one owner, or when someone is invited to share one of your values. When that happens, the change appears here, with <b>Agree</b> and, for owners, <b>Withdraw</b>.</p>",
        else:
          "<ul class=plain>" <>
            Enum.map_join(mine, "", fn p ->
              text = proposal_text(p, names, m)
              agreed = if p.consents == [], do: "", else: " Agreed so far: #{people(p.consents)}."

              "<li>#{esc(text)}<span class=hint>#{esc(agreed)}</span> #{button("consent", %{"proposal" => p.id}, "Agree", "Agree: #{text}", csrf)}#{withdraw_button(p, owners_of, m, csrf)}</li>"
            end) <> "</ul>"

    waiting_for_others =
      if others == [],
        do: "",
        else:
          "<h3>Waiting for others</h3><ul class=plain>" <>
            Enum.map_join(others, "", fn p ->
              needed = needed(p, owners_of) |> MapSet.difference(MapSet.new(p.consents))

              "<li>#{esc(proposal_text(p, names, m))} <span class=hint>Waiting for #{esc(people(needed, m, "no one"))}.</span> #{withdraw_button(p, owners_of, m, csrf)}</li>"
            end) <> "</ul>"

    waiting_for_you <> waiting_for_others
  end

  # REQ-125: owners of the item can withdraw; a prospective joiner declines by not agreeing.
  defp withdraw_button(p, owners_of, m, csrf) do
    owners = get_in(owners_of, [p.item_id, :owners]) || MapSet.new()

    if m in owners,
      do: button("withdraw", %{"proposal" => p.id}, "Withdraw", "Withdraw this proposal", csrf),
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

  # One block per thing the member owns, showing and acting on its CURRENT state (WI-017), then
  # what others have shared with the member.
  defp sharing(owned, shared_with_me, m, others, pending, owners_of, names, csrf) do
    mine =
      if owned == [],
        do: "<p class=empty>You don't own anything yet.</p>",
        else:
          owned
          |> Enum.sort_by(&String.downcase(title(&1)))
          |> Enum.map_join("", &sharing_block(&1, m, others, pending, owners_of, names, csrf))

    theirs =
      case Enum.sort_by(shared_with_me, &String.downcase(title(&1))) do
        [] ->
          ""

        list ->
          "<h3>Shared with you</h3><ul class=plain>" <>
            Enum.map_join(
              list,
              "",
              &"<li><b>#{esc(title(&1))}</b>. #{esc(people(&1.owners, m))} let you see this.</li>"
            ) <>
            "</ul>"
      end

    mine <> theirs
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

  defp sharing_block(i, m, others, pending, owners_of, names, csrf) do
    id = i.id
    sole? = length(i.owners) == 1
    value? = value?(i)
    # WI-019: say whether changes apply at once or wait, and label actions by their effect.
    {agreement, share_label, owners_label, owners_hint} = agreement_text(sole?, value?)
    grantees = Map.get(i, :grantees, [])
    can_share_with = Enum.reject(others, &(&1 in i.owners or &1 in grantees))

    visible_to =
      if grantees == [],
        do: "Nobody else can see it.",
        else:
          "Also visible to " <>
            Enum.map_join(grantees, " ", fn g ->
              "<span class=person>#{esc(g)} #{button("revoke", %{"item" => id, "member" => g}, "Stop sharing", "Stop sharing #{title(i)} with #{g}", csrf)}</span>"
            end)

    share =
      if can_share_with == [],
        do: "",
        else: """
        <form method=post action="/act/grant" class=inline>#{csrf}<input type=hidden name=item value="#{esc(id)}">
        <label class=inline-label for="g-#{esc(id)}">Share with</label> <select id="g-#{esc(id)}" name=member class=compact>#{Enum.map_join(can_share_with, "", &"<option>#{esc(&1)}</option>")}</select>
        <button class=small>#{share_label}</button></form>
        """

    checkboxes =
      Enum.map_join([m | others], "", fn x ->
        checked = if x in i.owners, do: " checked", else: ""

        ~s(<label class=check><input type=checkbox name="owners[]" value="#{esc(x)}"#{checked}> #{esc(if x == m, do: "#{x} (you)", else: x)}</label>)
      end)

    waiting =
      pending
      |> Enum.filter(&(&1.item_id == id))
      |> Enum.map_join("", fn p ->
        needed = needed(p, owners_of) |> MapSet.difference(MapSet.new(p.consents))

        ~s(<div class="msg pending">Waiting: #{esc(proposal_text(p, names, m))} Needs #{esc(people(needed, m, "no one"))} to agree. #{withdraw_button(p, owners_of, m, csrf)}</div>)
      end)

    """
    <div class=share-item id="own-#{esc(id)}"><h3>#{esc(title(i))}</h3>
    <div class=status>Owned by #{esc(people(i.owners, m))}. #{visible_to}</div>
    <p class="hint agreement">#{agreement}</p>
    #{waiting}
    <div class=controls>#{share}<details open><summary>Change who owns it</summary>
    <form method=post action="/act/owners">#{csrf}<input type=hidden name=item value="#{esc(id)}">
    <fieldset><legend>Owners of “#{esc(title(i))}”</legend>#{checkboxes}</fieldset>
    <p class=hint>Ticked now: the current owners. #{owners_hint}</p>
    <button>#{owners_label}</button></form></details></div></div>
    """
  end

  defp leave_block([], csrf) do
    ~s(<form method=post action="/confirm/leave">#{csrf}<button class=danger>Leave the household…</button></form>)
  end

  defp leave_block(_owned, _csrf) do
    "<p class=hint>To leave, first stop owning, give away, or delete what you own. Your export shows what that is.</p>"
  end

  # UX-001 R3: offer only actions that can succeed. A sole owner can't stop owning (someone must
  # own it), so they get Give away and Delete. A joint owner can't delete, so they get Stop owning,
  # behind a confirmation because they can only regain it if the others agree.
  defp owner_actions(i, _m, csrf) do
    name = title(i)
    id = esc(i.id)

    if length(Enum.to_list(i.owners)) == 1 do
      ~s(<a class="button-link" href="#own-#{id}" aria-label="Give away #{esc(name)}">Give away…</a>) <>
        ~s(<form class=inline method=post action="/confirm/delete">#{csrf}<input type=hidden name=item value="#{id}"><button class=danger aria-label="Delete #{esc(name)}">Delete…</button></form>)
    else
      ~s(<form class=inline method=post action="/confirm/relinquish">#{csrf}<input type=hidden name=item value="#{id}"><button aria-label="Stop owning #{esc(name)}">Stop owning…</button></form>)
    end
  end

  defp history(h, m, i, true) do
    case Ledger.read(h, m, i.id) do
      {:ok, entries} ->
        "<details><summary>History</summary><ol>" <>
          Enum.map_join(entries, "", &"<li>#{esc(event_text(&1))}</li>") <> "</ol></details>"

      _ ->
        ""
    end
  end

  defp history(_h, _m, _i, false),
    do:
      ~s(<span class=hint title="Only owners can see an item's history.">History: owners only</span>)

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
