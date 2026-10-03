defmodule FindependenceShared.Words do
  @moduledoc """
  The words both forms use for amounts, dates, kinds, people, history, and what an action did (UX-001 R6,
  REQ-129, REQ-143; moved without change from the local form's page rendering by WI-075, CP-021, REV-100 H3).
  Plain text only: each form escapes and marks it up. Where a member is named, `name_of` turns a member id
  into what is shown: the local form's ids are the names themselves; the hosted form's are membership ids,
  shown by display name.
  """

  alias FindependenceShared.{CashFlow, Items, Planning, Scope, Values}

  defp sc(h, m), do: Scope.read(h, m)

  @account_words %{
    checking: "Checking account",
    savings: "Savings account",
    other: "Account",
    retirement_401k: "401(k)",
    ira: "IRA"
  }
  @debt_words %{card: "Credit card", heloc: "HELOC", loan: "Loan", other: "Debt"}

  @doc "An account's or debt's kind in words."
  def kind_words(%{attrs: %{kind: :account} = a}),
    do: @account_words[a.account_type] || "Account"

  def kind_words(%{attrs: %{kind: :debt} = a}), do: @debt_words[a.debt_type] || "Debt"

  @doc "\"$1,240.00\", or \"−$50.00\" when overdrawn; a debt's balance reads \"$5,200.00 owed\"."
  def balance_text(%{attrs: %{kind: :account}}, %{balance: b}), do: plain_amount(b)
  def balance_text(%{attrs: %{kind: :debt}}, %{balance: b}), do: plain_amount(b) <> " owed"
  def balance_text(_, _), do: "No balance yet"

  @doc "An amount without a plus sign."
  def plain_amount(0), do: "$0.00"
  def plain_amount(c), do: c |> format_amount() |> String.replace_prefix("+", "")

  @doc "Amounts are integer cents (WI-021)."
  def format_amount(amount), do: FindependenceShared.Money.format(amount)

  @doc "A rate in basis points, as a percentage: 2199 is \"21.99%\"."
  def rate_text(bp),
    do:
      :erlang.float_to_binary(bp / 100, decimals: 2)
      |> String.replace_suffix(".00", "")
      |> Kernel.<>("%")

  @doc "An ISO date written out, with the year only when it isn't `today`'s: \"Friday, September 27\"."
  def date_text(iso, today) do
    case Date.from_iso8601(to_string(iso)) do
      {:ok, d} ->
        day = Calendar.strftime(d, "%A, %B ") <> Integer.to_string(d.day)
        if d.year == today.year, do: day, else: day <> ", " <> Integer.to_string(d.year)

      _ ->
        to_string(iso)
    end
  end

  @doc "\"2026-11\" as \"November 2026\"."
  def month_text(mo) do
    case Date.from_iso8601(mo <> "-01") do
      {:ok, d} -> Calendar.strftime(d, "%B %Y")
      _ -> mo
    end
  end

  @doc "REQ-129: how often an amount happens, in words."
  def frequency_words(:one_off), do: "one-off"
  def frequency_words(:irregular), do: "a year, irregular"
  def frequency_words({:every, 1, :week}), do: "a week"
  def frequency_words({:every, 2, :week}), do: "every two weeks"
  def frequency_words({:every, 1, :month}), do: "a month"
  def frequency_words({:every, 2, :month}), do: "every two months"
  def frequency_words({:every, 3, :month}), do: "every three months"
  def frequency_words({:every, 6, :month}), do: "twice a year"
  def frequency_words({:every, 1, :year}), do: "a year"
  def frequency_words({:every, n, unit}), do: "every #{n} #{unit}s"

  @doc "An amount with how often it happens: \"−$62.40 a month\"."
  def money_line(%{amount: a} = attrs) when is_integer(a) do
    f = Items.frequency(%{attrs: attrs})
    sep = if f == :one_off, do: ", ", else: " "
    format_amount(a) <> sep <> frequency_words(f)
  end

  def money_line(_), do: ""

  @doc "\", \" and the amount with how often, or nothing."
  def amount_text(%{amount: a} = attrs) when is_integer(a), do: ", #{money_line(attrs)}"
  def amount_text(_), do: ""

  @doc "An item's figure alone."
  def figure_text(%{amount: a}) when is_integer(a), do: format_amount(a)
  def figure_text(_), do: ""

  @doc "How often an item's amount happens, in words."
  def frequency_text(%{amount: a} = attrs) when is_integer(a),
    do: frequency_words(Items.frequency(%{attrs: attrs}))

  def frequency_text(_), do: ""

  @doc "The per-month figure the totals use, for everything but monthly and one-off (REQ-128); nil otherwise."
  def per_month_figure(%{amount: a} = attrs) when is_integer(a) do
    f = Items.frequency(%{attrs: attrs})
    if f not in [:one_off, {:every, 1, :month}], do: format_amount(CashFlow.per_month(a, f))
  end

  def per_month_figure(_), do: nil

  @doc "An item's or value's name."
  def title(i), do: i.attrs[:note] || i.attrs[:label] || "Untitled"

  @doc "REQ-143 (DEF-047): wherever a shared plan is named outside the plan pages, it says it is a plan."
  def display(i),
    do: if(Map.get(i.attrs, :kind) == :plan, do: title(i) <> " (a plan)", else: title(i))

  @doc "The names of what the member can see, by id."
  def names(h, m), do: Map.new(Items.visible(sc(h, m)), &{&1.id, display(&1)})

  @doc "Whether an item needs the agreement of each person being added: every item (REQ-115; WI-086, CP-029)."
  # every kind since WI-086 (CP-029): nobody becomes an owner without agreeing
  def joiners?(_i), do: true

  @doc "Owners and whether joiners must agree, by item id."
  def owners_of(visible),
    do: Map.new(visible, &{&1.id, %{owners: MapSet.new(&1.owners), joiners?: joiners?(&1)}})

  @doc """
  Who must agree: the current owners, and for a shared value or plan also anyone being added (REQ-115,
  REQ-148).
  """
  def needed(%{item_id: id, change: change}, owners_of) do
    %{owners: owners, joiners?: joiners?} =
      Map.get(owners_of, id, %{owners: MapSet.new(), joiners?: false})

    case change do
      {:owners, new} when joiners? -> MapSet.union(owners, MapSet.difference(new, owners))
      _ -> owners
    end
  end

  @doc """
  REQ-201 (WI-088): for a waiting change whose cooling-off is running, when it takes effect and that it can be
  cancelled until then; for one whose cooling-off has ended, nil (the usual waiting words apply).
  """
  def cooling_text(%{due: due}) when is_integer(due) do
    if FindependenceShared.Clock.now() < due,
      do: "Everyone needed has agreed. Takes effect #{when_text(due)}. #{cancel_hint()}",
      else: nil
  end

  def cooling_text(_p), do: nil

  @doc "When a waiting change takes effect, in the device's local time: \"on Monday, October 5 at 15:00\"."
  def when_text(due) do
    {{y, mo, d}, {h, mi, _}} = :calendar.system_time_to_local_time(due, :second)
    date = Date.new!(y, mo, d)

    "on #{Calendar.strftime(date, "%A, %B %-d")} at #{String.pad_leading("#{h}", 2, "0")}:#{String.pad_leading("#{mi}", 2, "0")}"
  end

  defp cancel_hint,
    do: "Until then, anyone whose agreement it rests on can cancel it, and nothing changes."

  # the cooling-off's end of a waiting change on `item` the member made or agreed to, or nil
  defp waiting_due(h, m, item) do
    Enum.find_value(Items.pending(sc(h, m)), fn p ->
      (p.item_id == item and m in p.consents and is_integer(p[:due]) and
         FindependenceShared.Clock.now() < p.due) && p.due
    end)
  end

  @doc """
  People in a sentence, sorted by what is shown, the member as "you" in their own place: "Ben and you". With
  the local form's names as ids this is the order it has always used.
  """
  def people(list, me \\ nil, empty \\ "No one", name_of \\ &Function.identity/1) do
    list = list |> Enum.to_list() |> Enum.sort_by(name_of)

    case Enum.map(list, &if(&1 == me, do: "you", else: name_of.(&1))) do
      [] -> empty
      [a] -> a
      xs -> Enum.join(Enum.drop(xs, -1), ", ") <> " and " <> List.last(xs)
    end
  end

  @doc "A history entry in words (REQ-107)."
  def event_text(entry, name_of \\ &Function.identity/1)

  # WI-079: a change in the history that can't be opened, or isn't signed by someone who could have made it
  def event_text(:sealed, _name_of), do: "A change that can't be shown"

  def event_text(%{event: e, by: by, details: d}, name_of) do
    who = people(by, nil, "No one", name_of)

    case e do
      :created ->
        if(d[:imported], do: "Brought in by #{who}", else: "Created by #{who}")

      :owners_changed ->
        "Owners set to #{people(d.owners, nil, "No one", name_of)} (agreed by #{who})"

      :owner_relinquished ->
        "#{name_of.(d.owner)} stopped owning it"

      :granted ->
        "Shared with #{name_of.(d.grantee)} (agreed by #{who})"

      :grant_revoked ->
        "#{who} stopped sharing it with #{name_of.(d.grantee)}"

      :grantee_departed ->
        "#{name_of.(d.grantee)} left the household"

      :reading_added ->
        "Balance updated by #{who}"
    end
  end

  @doc """
  UX-001 R6: what actually happened, worded from the household before and after the action, so the member
  can tell an applied change from one still waiting for someone.
  """
  def outcome(action, params, before, after_h, m, name_of \\ &Function.identity/1) do
    names = Map.merge(names(before, m), names(after_h, m))
    item = params["item"]
    name = names[item] || "it"
    now = Items.lookup(sc(after_h, m), item)
    waiting_on = fn -> waiting_names(after_h, m, item, name_of) end

    case action do
      "add_item" ->
        "Added “#{params["note"]}”."

      "add_account" ->
        "Added “#{String.trim(params["label"] || "")}”. Add its balance below."

      "add_debt" ->
        "Added “#{String.trim(params["label"] || "")}”. Add what's owed below."

      "add_reading" ->
        "Saved the balance for “#{name}”."

      "new_plan" ->
        "Started “#{String.trim(params["name"] || "")}”. Add its steps below."

      "plan_step" ->
        "Added the step. The comparison below includes it."

      "remove_step" ->
        "Removed the step."

      "delete_plan" ->
        case Planning.plans(sc(before, m))[params["plan"]] do
          %{name: plan} -> "Deleted the plan “#{plan}”."
          nil -> "Deleted the plan."
        end

      "share_plan" ->
        (fn ms ->
           "Sent the request. It becomes a shared plan when #{people(ms, nil, "No one", name_of)} #{if length(ms) == 1, do: "agrees", else: "agree"}."
         end).(List.wrap(params["members"]))

      "mark" ->
        "Marked “#{name}” as depending on “#{names[params["job"]]}”."

      "unmark" ->
        "Removed the mark."

      "retirement" ->
        "Saved your retirement assumptions."

      "bring_in" ->
        new =
          for {id, i} <- Items.all(sc(after_h, m)),
              m in i.owners,
              not Map.has_key?(Items.all(sc(before, m)), id),
              do: i

        kinds =
          [
            {Enum.count(new, &Items.money?/1), "item", "items"},
            {Enum.count(new, &Values.value?/1), "value", "values"},
            {Enum.count(new, &(&1.attrs[:kind] == :account)), "account", "accounts"},
            {Enum.count(new, &(&1.attrs[:kind] == :debt)), "debt", "debts"}
          ]
          |> Enum.reject(fn {n, _, _} -> n == 0 end)
          |> Enum.map(fn {n, one, many} -> "#{n} #{if n == 1, do: one, else: many}" end)

        # in this order: items, values, accounts, debts (people/3 would sort them)
        what =
          case kinds do
            [] -> "nothing"
            [one] -> one
            xs -> Enum.join(Enum.drop(xs, -1), ", ") <> " and " <> List.last(xs)
          end

        "Brought in #{what} from your file. Only you own them; nobody else can see them until you share."

      "fund_goal" ->
        if String.trim(params["months"] || "") == "",
          do: "Cleared the goal.",
          else: "Saved the goal."

      "set_aside" ->
        if String.trim(params["rate"] || "") == "",
          do: "Removed the set-aside.",
          else: "Saved the rate."

      "add_value" ->
        "Added “#{params["label"]}”."

      "grant" ->
        cond do
          now && params["member"] in now.grantees ->
            "#{name_of.(params["member"])} can now see “#{name}”."

          due = waiting_due(after_h, m, item) ->
            "“#{name}” will be shared with #{name_of.(params["member"])} #{when_text(due)}. #{cancel_hint()}"

          true ->
            "Requested. Waiting for #{waiting_on.()} to agree."
        end

      "revoke" ->
        "#{name_of.(params["member"])} can no longer see “#{name}”."

      "owners" ->
        cond do
          now && MapSet.equal?(now.owners, MapSet.new(List.wrap(params["owners"]))) ->
            "“#{name}” is now owned by #{people(now.owners, m, "No one", name_of)}."

          due = waiting_due(after_h, m, item) ->
            "Agreed. Anyone being added sees the request #{when_text(due)}, and can agree then. #{cancel_hint()}"

          true ->
            "Requested. Waiting for #{waiting_on.()} to agree."
        end

      "consent" ->
        consent_outcome(before, after_h, m, params, name_of)

      "withdraw" ->
        "Withdrawn. Nothing was changed."

      # REQ-202 (WI-088)
      "retract" ->
        "You took back your agreement. Nothing was changed."

      "relinquish" ->
        "You no longer own “#{name}”."

      "delete" ->
        case waiting_due(after_h, m, item) do
          nil -> "Deleted “#{name}”."
          due -> "“#{name}” will be deleted #{when_text(due)}. #{cancel_hint()}"
        end

      "let_go" ->
        case params["to"] do
          "give:" <> to ->
            outcome("owners", Map.put(params, "owners", [to]), before, after_h, m, name_of)

          _ ->
            outcome("delete", params, before, after_h, m, name_of)
        end

      "link" ->
        "Linked “#{name}” to “#{names[params["value"]]}”."

      "attach" ->
        case params["account"] do
          a when a in [nil, ""] ->
            "“#{name}” no longer goes through a particular account for you."

          a ->
            "“#{name}” now goes through “#{names[a]}” in your Coming up and the next 12 months."
        end

      "unlink" ->
        "Unlinked “#{name}” from “#{names[params["value"]]}”."

      _ ->
        "Done."
    end
  end

  defp consent_outcome(before, after_h, m, params, name_of) do
    # a request number (the local form) or the identifier members see (the hosted form, REQ-199)
    raw = to_string(params["proposal"] || "0")
    id = if Regex.match?(~r/\A[0-9]+\z/, raw), do: String.to_integer(raw), else: raw

    case {Items.proposal(sc(before, m), id), Items.proposal(sc(after_h, m), id)} do
      {nil, _} ->
        "Done."

      {_, nil} ->
        "You agreed, and the change has been made."

      {_, %{due: due}} when is_integer(due) ->
        if FindependenceShared.Clock.now() < due,
          do: "You agreed. It takes effect #{when_text(due)}. #{cancel_hint()}",
          else: "You agreed. Still waiting for #{waiting_names_for(after_h, m, id, name_of)}."

      {p, _} ->
        "You agreed. Still waiting for #{waiting_names(after_h, m, p.item_id, name_of)}."
    end
  rescue
    ArgumentError -> "Done."
  end

  defp waiting_names_for(h, m, id, name_of) do
    case Items.proposal(sc(h, m), id) do
      %{item_id: item} -> waiting_names(h, m, item, name_of)
      _ -> "the others"
    end
  end

  defp waiting_names(h, m, item_id, name_of) do
    owners_of = owners_of(Items.visible(sc(h, m)))

    Items.pending(sc(h, m))
    |> Enum.filter(&(&1.item_id == item_id))
    |> Enum.flat_map(
      &(needed(&1, owners_of)
        |> MapSet.difference(MapSet.new(&1.consents))
        |> Enum.to_list())
    )
    |> Enum.uniq()
    |> people(m, "the others", name_of)
  end

  @doc "REQ-129: the add-item form's nine choices of how often, in order, as {form value, label}."
  def item_frequency_choices, do: frequency_choices() ++ [{"one_off", "One-off"}]

  @doc "A plan step's choices of how often (repeating or irregular; not one-off), as {form value, label}."
  def frequency_choices,
    do: [
      {"monthly", "Every month"},
      {"biweekly", "Every two weeks"},
      {"weekly", "Every week"},
      {"every_2_months", "Every two months"},
      {"every_3_months", "Every three months"},
      {"twice_a_year", "Twice a year"},
      {"yearly", "Every year"},
      {"irregular", "Irregular (enter the total for a year)"}
    ]

  @doc "A number of months in words: \"8 months\", \"2 years and 3 months\"."
  def months_text(n) when n < 12, do: "#{n} #{if n == 1, do: "month", else: "months"}"

  def months_text(n) do
    {y, mo} = {div(n, 12), rem(n, 12)}
    years = "#{y} #{if y == 1, do: "year", else: "years"}"
    if mo == 0, do: years, else: "#{years} and #{mo} #{if mo == 1, do: "month", else: "months"}"
  end

  @doc """
  REQ-145: a what-if (`FindependenceShared.Balances.what_if/3`) in words: the sentence at the minimum, and for
  each figure nil, `{lead, text}`, or `{:error, message}`.
  """
  def what_if_lines(%{min_payment: min}, w) do
    base =
      case w.base do
        {:ok, n, int} ->
          "Paying the minimum of #{plain_amount(min)}, it would take #{months_text(n)} to clear, with #{plain_amount(int)} of interest."

        :never ->
          "Paying the minimum of #{plain_amount(min)} doesn't cover a month's interest, so it wouldn't clear."
      end

    with_extra =
      case w.with_extra do
        {:ok, cents, {:ok, n, int}} ->
          {"With #{plain_amount(cents)} more a month:",
           "#{months_text(n)}, with #{plain_amount(int)} of interest."}

        {:ok, cents, :never} ->
          {"With #{plain_amount(cents)} more a month:", "it still wouldn't clear."}

        other ->
          other
      end

    at_rate =
      case w.at_rate do
        {:ok, bp, interest} ->
          {"At #{rate_text(bp)}:",
           "a month's interest on #{plain_amount(w.balance)} would be #{plain_amount(interest)}."}

        other ->
          other
      end

    %{base: base, with_extra: with_extra, at_rate: at_rate}
  end

  @only_visible "Counts items you own, and items shared with you that you've said go through these accounts; anything others keep private isn't included."

  @doc """
  REQ-161 AC-9, REQ-162 AC-8: of these accounts, those others also own, by name, and who those others are;
  nil when the member owns them alone.
  """
  def joint_owners(h, m, account_ids) do
    joint =
      Enum.filter(account_ids, fn id ->
        MapSet.size(MapSet.delete(Items.lookup(sc(h, m), id).owners, m)) > 0
      end)

    case joint do
      [] ->
        nil

      ids ->
        others =
          ids
          |> Enum.flat_map(&MapSet.to_list(MapSet.delete(Items.lookup(sc(h, m), &1).owners, m)))
          |> Enum.uniq()
          |> Enum.sort()

        {Enum.map(ids, &title(Items.lookup(sc(h, m), &1))), others}
    end
  end

  @doc "Whether a balance counts only the member's part (some of the accounts are owned with others)."
  def partial?(h, m, account_ids), do: joint_owners(h, m, account_ids) != nil

  @doc "What a starting balance counts, naming anyone who also owns the accounts (REQ-161, REQ-162)."
  def counted_note(h, m, account_ids, name_of \\ &Function.identity/1) do
    case joint_owners(h, m, account_ids) do
      nil ->
        @only_visible

      {accounts, others} ->
        own = if length(others) == 1, do: "owns", else: "own"
        who = people(others, nil, "No one", name_of)

        "#{who} also #{own} #{people(accounts)}, so this is your part: items #{who} #{own} count only once they're shared with you and you say they go through it."
    end
  end

  @doc """
  How an item's sharing and ownership changes work for the member, and the form labels: {agreement,
  share label, owners label, owners hint} (UX-001 R5).
  """
  #
  # WI-086 (CP-029): nobody becomes an owner without agreeing, whatever the item, so adding or giving to someone
  # always waits for them; `value?` no longer changes the words.
  def agreement_text(true = _sole?, _value?),
    do:
      {"You're the only owner. Sharing takes effect right away. Adding someone as an owner, or giving it to them, waits for them to agree.",
       "Share", "Request change",
       "Anyone you add as an owner has to agree before it takes effect. To give it away, tick only the other person; it's theirs, and you stop owning it, once they agree."}

  def agreement_text(false, _value?),
    do:
      {"Owned jointly, so changes here wait until every owner agrees (and anyone being added).",
       "Request sharing", "Request change",
       "Every current owner, and anyone being added, has to agree before this takes effect."}

  @doc "A waiting change in words (UX-001 R7), naming the item as the member knows it."
  def proposal_text(p, names, m, name_of \\ &Function.identity/1) do
    name = names[p.item_id] || (p[:attrs] && (p.attrs[:label] || p.attrs[:note])) || "an item"

    case p.change do
      # REQ-201 (WI-088): a scheduled deletion
      :delete ->
        "Delete “#{name}”."

      {:grant, g} ->
        "Share “#{name}” with #{name_of.(g)}."

      {:owners, owners} ->
        others = people(MapSet.delete(owners, m), nil, "No one", name_of)

        cond do
          m in owners and Map.has_key?(names, p.item_id) ->
            "Make “#{name}” owned by #{people(owners, nil, "No one", name_of)}."

          (m in owners and p[:attrs]) && p.attrs[:kind] == :plan ->
            "Request: share the plan “#{name}” with #{others}."

          m in owners ->
            "Request: own “#{name}” together with #{others}."

          true ->
            "Make “#{name}” owned by #{people(owners, nil, "No one", name_of)}."
        end
    end
  end

  # ---------------------------------------------------------------------------
  # WI-079: signing (both forms)

  @signing_issues [:unsigned_box, :bad_signature, :signer_not_entitled, :signing_key_changed]

  @doc """
  The note on an item's page when parts of it were saved before Findependence began signing changes (WI-079):
  `parts` from `FindependenceShared.Envelope.written_before_signing/2`. Neutral: this is expected for anything
  saved by an earlier version. nil when there is nothing to say.
  """
  def before_signing_note([]), do: nil

  def before_signing_note(parts) do
    what =
      for part <- [:content, :history, :readings], part in parts do
        case part do
          :content -> "its details"
          :history -> "some of its history"
          :readings -> "some of its balances"
        end
      end

    list =
      case what do
        [a] -> a
        xs -> Enum.join(Enum.drop(xs, -1), ", ") <> " and " <> List.last(xs)
      end

    "An earlier version of Findependence saved #{list} before it began signing each change, so who wrote them isn't recorded."
  end

  @doc """
  The integrity notice's heading and lines for `issues` (`FindependenceShared.Envelope.integrity_issues/1`),
  worded for where the household is kept (`:file` locally, `:stored` in the hosted form); nil when there are
  none.
  """
  def integrity_notice([], _where), do: nil

  def integrity_notice(issues, where) do
    heading =
      case where do
        :file ->
          "This household file may have been changed outside Findependence"

        :stored ->
          "This household's stored information may have been changed outside Findependence"
      end

    count = length(issues)

    # REQ-203 (WI-090)
    lines =
      [
        "Some sharing, ownership, or signing details don't match what the app itself wrote (#{count} #{if count == 1, do: "sign", else: "signs"}). Nothing new has been shared because of this: the app only shares with people it added itself, or whose keys it can check."
      ] ++
        if(signing_issue?(issues),
          do: [
            "Some details aren't signed by someone who could have written them, so they aren't shown."
          ],
          else: []
        ) ++
        if(Enum.any?(issues, &match?({:forged_agreement, _, _}, &1)),
          do: [
            "An agreement in the records wasn't made by the member it names, so it isn't counted: nothing changes because of it."
          ],
          else: []
        ) ++
        [
          "Until this is sorted out, be careful about what you add or share, and talk to the person running the study."
        ]

    {heading, lines}
  end

  @doc "Whether any of `issues` is about signatures (WI-079)."
  def signing_issue?(issues),
    do: Enum.any?(issues, &(is_tuple(&1) and elem(&1, 0) in @signing_issues))
end
