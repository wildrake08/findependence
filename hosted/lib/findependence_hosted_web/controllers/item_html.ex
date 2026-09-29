defmodule FindependenceHostedWeb.ItemHTML do
  @moduledoc """
  One page per thing (UX-001 R1; WI-075): an item of money in or out, a value, an account, or a debt, as the
  local form's item page says it, and the confirmation pages for deleting and for stopping owning (REQ-166).
  Owners see who can see it, sharing, owners, what is waiting, links, history, and how to let go; someone it
  is shared with sees it, who shared it, and their own links. Members are named by their display name.
  The wording is the local form's (web/html.ex); amounts, dates, kinds, people, and history come from
  `FindependenceShared.Words`.
  """
  use FindependenceHostedWeb, :html

  alias FindependenceShared.{
    Balances,
    CashFlow,
    Decode,
    Households,
    Items,
    Money,
    Planning,
    Values,
    Words
  }

  # ---------------------------------------------------------------------------
  # Page data: everything the templates show, read through the contexts over the member's view

  @doc """
  What the item's page shows for the member (`scope`), with `name_of` naming members, `message` a refusal
  (`{:error, text}`) or nil, and `form` what was typed into the balance form after a refused save, and the
  what-if query (`:query`).
  """
  def page(scope, i, name_of, today, message, form) do
    m = scope.member
    visible = Items.visible(scope)

    kind =
      cond do
        Balances.balance?(i) -> :balance
        Planning.plan?(i) -> :plan
        true -> :money
      end

    owner? = m in i.owners

    base = %{
      kind: kind,
      item: i,
      id: i.id,
      title: Words.title(i),
      display: Words.display(i),
      value?: value?(i),
      owner?: owner?,
      return: "/items/#{i.id}",
      message: message,
      people: &Words.people(&1, m, "No one", name_of),
      shared_text:
        "#{Words.people(i.owners, m, "No one", name_of)} shared this with you. Only owners can change who can see it or view its history."
    }

    case kind do
      :plan ->
        base

      _ ->
        base
        |> Map.put(
          :owner,
          if(owner?, do: owner_data(scope, i, visible, name_of), else: nil)
        )
        |> Map.put(:history, if(owner?, do: history(scope, i, name_of), else: nil))
        |> Map.put(:sole?, length(Enum.to_list(i.owners)) == 1)
        |> Map.merge(kind_data(kind, scope, i, visible, name_of, today, form))
    end
  end

  defp kind_data(:money, scope, i, visible, _name_of, today, _form) do
    %{
      money_line: Words.money_line(i.attrs),
      next_date: next_date_line(i, today),
      per_month: Words.per_month_figure(i.attrs),
      links: links(scope, i, visible),
      account: account(scope, i),
      depends: if(scope.member in i.owners, do: depends(scope, i), else: nil)
    }
  end

  defp kind_data(:balance, scope, i, _visible, name_of, today, form) do
    r = Balances.latest(scope, i.id)
    debt? = i.attrs.kind == :debt

    %{
      kind_words: Words.kind_words(i),
      debt?: debt?,
      latest: latest(i, r, today),
      retirement?: Balances.retirement?(i),
      reading: if(scope.member in i.owners, do: reading_form(i, form, r, today), else: nil),
      what_if: if(debt?, do: what_if(r, form[:query] || %{}), else: nil),
      earlier: if(scope.member in i.owners, do: earlier(scope, i, name_of, today), else: nil)
    }
  end

  defp value?(i), do: Map.get(i.attrs, :kind) == :value

  defp next_date_line(i, today) do
    case CashFlow.occurrences(i, today, Date.add(today, 800)) do
      [d | _] ->
        label = if Items.frequency(i) == :one_off, do: "On", else: "Next:"
        {:next, "#{label} #{Words.date_text(Date.to_iso8601(d), today)}"}

      [] ->
        case CashFlow.date(i) do
          nil -> nil
          d -> {:past, "Happened on #{Words.date_text(Date.to_iso8601(d), today)}."}
        end
    end
  end

  defp latest(_i, nil, _today), do: nil

  defp latest(i, r, today) do
    %{
      balance: Words.balance_text(i, r),
      as_of: "As of #{Words.date_text(r.on, today)}.",
      debt:
        if(i.attrs.kind == :debt,
          do: %{
            terms:
              "Interest rate #{Words.rate_text(r.rate_bp)} · Minimum payment #{Words.plain_amount(r.min_payment)}",
            interest:
              "At #{Words.rate_text(r.rate_bp)}, a month's interest on #{Words.plain_amount(r.balance)} is #{Words.plain_amount(Balances.monthly_interest(r))}."
          },
          else: nil
        )
    }
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

  defp owner_data(scope, i, visible, name_of) do
    m = scope.member
    sole? = length(Enum.to_list(i.owners)) == 1
    {agreement, share_label, owners_label, owners_hint} = agreement_text(sole?, value?(i))
    grantees = Map.get(i, :grantees, []) |> Enum.sort_by(name_of)
    others = Households.members(scope) |> MapSet.delete(m) |> Enum.sort_by(name_of)
    can_share_with = Enum.reject(others, &(&1 in i.owners or &1 in grantees))
    names = Words.names(scope.household, m)
    owners_of = Words.owners_of(visible)

    pending =
      Items.pending(scope)
      |> Enum.filter(&(&1.item_id == i.id))
      |> Enum.map(&pending_entry(&1, names, owners_of, m, name_of))

    %{
      owned_by: "Owned by #{Words.people(i.owners, m, "No one", name_of)}.",
      agreement: agreement,
      share_label: share_label,
      owners_label: owners_label,
      owners_hint: "Ticked now: the current owners. #{owners_hint}",
      grantees: Enum.map(grantees, &{&1, name_of.(&1)}),
      share_options: Enum.map(can_share_with, &{name_of.(&1), &1}),
      owner_choices:
        Enum.map([m | others], fn x ->
          %{
            id: x,
            label: if(x == m, do: "#{name_of.(x)} (you)", else: name_of.(x)),
            checked: x in i.owners
          }
        end),
      pending: pending
    }
  end

  # A waiting change on the item's page: Agree for a change this member hasn't agreed to, Withdraw for owners
  # (REQ-125), and who is still needed.
  defp pending_entry(p, names, owners_of, m, name_of) do
    text = proposal_text(p, names, m, name_of)
    needed = Words.needed(p, owners_of) |> MapSet.difference(MapSet.new(p.consents))
    owners = get_in(owners_of, [p.item_id, :owners]) || MapSet.new()

    status =
      cond do
        m in p.consents -> "Waiting for #{Words.people(needed, m, "no one", name_of)}."
        p.consents == [] -> ""
        true -> "Agreed so far: #{Words.people(p.consents, nil, "No one", name_of)}."
      end

    %{
      id: p.id,
      text: text,
      status: status,
      # REQ-148: a plan request can be seen before agreeing
      plan_link: if(is_map(p[:attrs]) and p.attrs[:kind] == :plan, do: "/requests/#{p.id}"),
      agree?: m not in p.consents,
      withdraw?: m in owners
    }
  end

  defp proposal_text(p, names, m, name_of) do
    name = names[p.item_id] || (p[:attrs] && (p.attrs[:label] || p.attrs[:note])) || "an item"
    people = &Words.people(&1, nil, "No one", name_of)

    case p.change do
      {:grant, g} ->
        "Share “#{name}” with #{name_of.(g)}."

      {:owners, owners} ->
        others = people.(MapSet.delete(owners, m))

        cond do
          m in owners and Map.has_key?(names, p.item_id) ->
            "Make “#{name}” owned by #{people.(owners)}."

          (m in owners and p[:attrs]) && p.attrs[:kind] == :plan ->
            "Request: share the plan “#{name}” with #{others}."

          m in owners ->
            "Request: own “#{name}” together with #{others}."

          true ->
            "Make “#{name}” owned by #{people.(owners)}."
        end
    end
  end

  # Links belong to the member (REQ-112): a money item links to values; a value lists what's linked to it.
  defp links(scope, i, visible) do
    links = Values.links(scope)
    names = Map.new(visible, &{&1.id, Words.title(&1)})
    sort = &Enum.sort_by(&1, fn id -> String.downcase(names[id] || "") end)

    if value?(i) do
      linked = sort.(for {item, v} <- links, v == i.id, do: item)
      %{value?: true, linked: Enum.map(linked, &{&1, names[&1]}), title: names[i.id]}
    else
      linked = sort.(for {item, v} <- links, item == i.id, do: v)
      values = Enum.filter(visible, &value?/1)
      unlinked = Enum.reject(values, &(&1.id in linked))

      %{
        value?: false,
        linked: Enum.map(linked, &{&1, names[&1]}),
        no_values?: values == [],
        options: options(unlinked)
      }
    end
  end

  # Sorted by name, so choices keep a stable order (WI-030).
  defp options(entries),
    do:
      entries
      |> Enum.sort_by(&String.downcase(Words.title(&1)))
      |> Enum.map(&{Words.title(&1), &1.id})

  # REQ-160 (CP-014 A): which cash account a money item goes through, for this member only
  defp account(scope, i) do
    accounts =
      Items.visible(scope)
      |> Enum.filter(&Balances.cash_account?/1)
      |> Enum.sort_by(&String.downcase(Words.title(&1)))

    if value?(i) or accounts == [] do
      nil
    else
      rule =
        if scope.member in i.owners,
          do: "Until you choose, an item you own counts toward all your accounts.",
          else:
            "Shared with you, it counts in your Coming up and the next 12 months only once you choose its account."

      %{
        hint: "Only you see this. #{rule}",
        options: [{"Not said", ""} | Enum.map(accounts, &{Words.title(&1), &1.id})],
        current: Balances.attached(scope)[i.id] || ""
      }
    end
  end

  # REQ-144: items the member owns can be marked as depending on a job (an income they own).
  defp depends(scope, i) do
    m = scope.member

    if Items.money?(i) and not (is_integer(i.attrs[:amount]) and i.attrs[:amount] > 0) do
      jobs =
        Items.visible(scope)
        |> Enum.filter(
          &(m in &1.owners and Items.money?(&1) and is_integer(&1.attrs[:amount]) and
              &1.attrs[:amount] > 0 and &1.id != i.id)
        )
        |> Enum.sort_by(&String.downcase(Words.title(&1)))

      marks =
        for {x, j} <- Planning.depends(scope), x == i.id do
          {j, Words.title(Items.lookup(scope, j))}
        end

      %{marks: marks, jobs: Enum.map(jobs, &{Words.title(&1), &1.id})}
    end
  end

  defp history(scope, i, name_of) do
    case Items.ledger(scope, i.id) do
      {:ok, entries} -> Enum.map(entries, &Words.event_text(&1, name_of))
      _ -> nil
    end
  end

  defp earlier(scope, i, name_of, today) do
    case Balances.readings(scope, i.id) do
      {:ok, list} when length(list) > 1 ->
        list
        |> Enum.reverse()
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn r ->
          extra = if i.attrs.kind == :debt, do: " at #{Words.rate_text(r.rate_bp)}", else: ""

          %{
            text: "#{Words.date_text(r.on, today)}: #{Words.balance_text(i, r) <> extra}",
            by: "(#{Words.people([r.by], scope.member, "No one", name_of)})"
          }
        end)

      _ ->
        nil
    end
  end

  defp reading_form(i, form, latest, today) do
    debt? = i.attrs.kind == :debt

    # UX-002 R2: a debt's rate and minimum rarely change, so they start from the latest balance;
    # after a refused save, what was typed is kept instead
    form =
      if debt? and latest != nil and not Map.has_key?(form, :rate),
        do:
          Map.merge(form, %{
            rate: latest.rate_bp |> Words.rate_text() |> String.replace_suffix("%", ""),
            min_payment:
              latest.min_payment |> Words.plain_amount() |> String.replace_prefix("$", "")
          }),
        else: form

    %{
      debt?: debt?,
      balance: form[:balance],
      rate: form[:rate],
      min_payment: form[:min_payment],
      on: form[:on] || Date.to_iso8601(today),
      error: form[:error] && {form[:error_field], form[:error]},
      hint:
        if(debt?,
          do: "Anyone who owns it can update it. People it's shared with see only the latest.",
          else:
            "Anyone who owns it can update it. People it's shared with see only the latest. For an overdrawn account, start with −."
        )
    }
  end

  # REQ-145: a calculation on the debt's page, from a GET form; nothing is stored.
  defp what_if(nil, _q), do: nil

  defp what_if(r, q) do
    extra = q["extra"] |> to_string() |> String.trim()
    rate = q["rate"] |> to_string() |> String.trim()

    base =
      case Balances.payoff(r.balance, r.rate_bp, r.min_payment) do
        {:ok, n, int} ->
          "Paying the minimum of #{Words.plain_amount(r.min_payment)}, it would take #{months_text(n)} to clear, with #{Words.plain_amount(int)} of interest."

        :never ->
          "Paying the minimum of #{Words.plain_amount(r.min_payment)} doesn't cover a month's interest, so it wouldn't clear."
      end

    with_extra =
      case Money.parse(extra, "in") do
        {:ok, cents} when is_integer(cents) and cents > 0 ->
          lead = "With #{Words.plain_amount(cents)} more a month:"

          case Balances.payoff(r.balance, r.rate_bp, r.min_payment + cents) do
            {:ok, n, int} ->
              {lead, "#{months_text(n)}, with #{Words.plain_amount(int)} of interest."}

            :never ->
              {lead, "it still wouldn't clear."}
          end

        {:ok, _} ->
          nil

        _ ->
          {:error, "Enter the extra amount like 100 or 100.00."}
      end

    at_rate =
      case Decode.rate(rate) do
        _ when rate == "" ->
          nil

        {:ok, bp} when bp <= 10_000 ->
          {"At #{Words.rate_text(bp)}:",
           "a month's interest on #{Words.plain_amount(r.balance)} would be #{Words.plain_amount(Balances.monthly_interest(%{balance: r.balance, rate_bp: bp}))}."}

        {:ok, _} ->
          {:error, "Enter a rate from 0 to 100."}

        :error ->
          {:error, "Enter the rate as a percentage, like 10.5."}
      end

    %{base: base, extra: extra, rate: rate, with_extra: with_extra, at_rate: at_rate}
  end

  defp months_text(n) when n < 12, do: "#{n} #{if n == 1, do: "month", else: "months"}"

  defp months_text(n) do
    {y, mo} = {div(n, 12), rem(n, 12)}
    years = "#{y} #{if y == 1, do: "year", else: "years"}"
    if mo == 0, do: years, else: "#{years} and #{mo} #{if mo == 1, do: "month", else: "months"}"
  end

  @doc "The confirmation page's words for deleting or stopping owning (REQ-166), as the local form's."
  def confirm_words("delete", what, _keepers),
    do:
      {"Delete “#{what}”?",
       "It will be gone for everyone who could see it, with its history. This can't be undone.",
       "Yes, delete"}

  def confirm_words("relinquish", what, keepers),
    do:
      {"Stop owning “#{what}”?",
       "You'll stop seeing it unless someone shares it with you again. #{keepers.people} will keep it. To own it again, #{if keepers.count == 1, do: "they", else: "all of them"} would have to agree.",
       "Yes, stop owning"}

  # ---------------------------------------------------------------------------
  # Templates

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <p><.link href={~p"/"}>← Everything</.link></p>
      <.alert :if={@page.message} variant="soft" color="danger" role="alert">
        {elem(@page.message, 1)}
      </.alert>
      <.item_body page={@page} />
    </Layouts.app>
    """
  end

  attr :page, :map, required: true

  defp item_body(%{page: %{kind: :plan}} = assigns) do
    ~H"""
    <.h1>{@page.display}</.h1>
    <.card>
      <.card_content>
        <.p>
          A shared plan, owned by {@page.people.(@page.item.owners)}. Its steps don't change; a revised plan is a new request.
        </.p>
      </.card_content>
    </.card>
    """
  end

  defp item_body(%{page: %{kind: :money}} = assigns) do
    ~H"""
    <.h1>{@page.title}</.h1>
    <.card>
      <.card_content class="space-y-3">
        <%= if @page.value? do %>
          <p class="text-sm text-gray-600 dark:text-gray-400">A value.</p>
        <% else %>
          <p id="amount" class="text-2xl font-semibold">{@page.money_line}</p>
          <p :if={match?({:next, _}, @page.next_date)}>{elem(@page.next_date, 1)}</p>
          <p
            :if={match?({:past, _}, @page.next_date)}
            class="text-sm text-gray-600 dark:text-gray-400"
          >
            {elem(@page.next_date, 1)}
          </p>
          <p :if={@page.per_month} class="text-sm text-gray-600 dark:text-gray-400">
            Counted as {@page.per_month} a month in your totals.
          </p>
          <p :if={@page.owner?} class="text-sm text-gray-600 dark:text-gray-400">
            Amounts can't be changed yet. For a new amount, add a new item with it and remove this one; its links and history don't carry over.
          </p>
        <% end %>
        <.owner_or_shared page={@page} />
      </.card_content>
    </.card>
    <.links_section page={@page} />
    <.account_section :if={@page.account} page={@page} />
    <.depends_section :if={@page.depends} page={@page} />
    <.history_section :if={@page.owner?} page={@page} />
    <.let_go_section :if={@page.owner?} page={@page} />
    """
  end

  defp item_body(%{page: %{kind: :balance}} = assigns) do
    ~H"""
    <.h1>{@page.title}</.h1>
    <.card>
      <.card_content class="space-y-3">
        <p class="text-sm text-gray-600 dark:text-gray-400">{@page.kind_words}</p>
        <p :if={@page.latest == nil} class="text-gray-600 dark:text-gray-400">
          No balance recorded yet.
        </p>
        <div :if={@page.latest} id="latest" class="space-y-1">
          <p class="text-2xl font-semibold">{@page.latest.balance}</p>
          <p class="text-sm text-gray-600 dark:text-gray-400">{@page.latest.as_of}</p>
          <p :if={@page.latest.debt}>{@page.latest.debt.terms}</p>
          <p :if={@page.latest.debt} class="text-sm text-gray-600 dark:text-gray-400">
            {@page.latest.debt.interest}
          </p>
          <p :if={@page.retirement?} class="text-sm text-gray-600 dark:text-gray-400">
            A retirement account: it isn't counted as cash. See <.link href="/retirement">Retirement</.link>.
          </p>
        </div>
        <.reading_form :if={@page.reading} page={@page} />
        <.owner_or_shared page={@page} />
      </.card_content>
    </.card>
    <.what_if_section :if={@page.what_if} page={@page} />
    <.card :if={@page.earlier}>
      <.section_header title="Earlier balances" />
      <.card_content>
        <ol id="earlier" class="list-decimal space-y-1 pl-6">
          <li :for={r <- @page.earlier}>
            {r.text} <span class="text-sm text-gray-600 dark:text-gray-400">{r.by}</span>
          </li>
        </ol>
      </.card_content>
    </.card>
    <.history_section :if={@page.owner?} page={@page} />
    <.let_go_section :if={@page.owner?} page={@page} />
    """
  end

  attr :page, :map, required: true

  defp owner_or_shared(%{page: %{owner?: false}} = assigns) do
    ~H"""
    <p id="shared-with-me">{@page.shared_text}</p>
    """
  end

  defp owner_or_shared(assigns) do
    ~H"""
    <div id="owners-part" class="space-y-3">
      <p class="font-medium">{@page.owner.owned_by}</p>
      <p class="text-sm text-gray-600 dark:text-gray-400">{@page.owner.agreement}</p>

      <div :if={@page.owner.pending != []}>
        <h2 class="pc-card__title">Waiting</h2>
        <ul id="waiting-here" class="space-y-2">
          <li :for={p <- @page.owner.pending} class="flex flex-wrap items-center gap-2">
            <span>{p.text}</span>
            <span :if={p.status != ""} class="text-sm text-gray-600 dark:text-gray-400">
              {p.status}
            </span>
            <.link :if={p.plan_link} href={p.plan_link}>See the plan</.link>
            <.act_form
              :if={p.agree?}
              action="/act/consent"
              return={@page.return}
              fields={[{"proposal", p.id}]}
              button="Agree"
              aria={"Agree: #{p.text}"}
            />
            <.act_form
              :if={p.withdraw?}
              action="/act/withdraw"
              return={@page.return}
              fields={[{"proposal", p.id}]}
              button="Withdraw"
              aria="Withdraw this request"
            />
          </li>
        </ul>
      </div>

      <h2 class="pc-card__title">Who else can see it</h2>
      <p :if={@page.owner.grantees == []}>Nobody else can see it.</p>
      <ul :if={@page.owner.grantees != []} id="grantees" class="space-y-2">
        <li :for={{g, name} <- @page.owner.grantees} class="flex flex-wrap items-center gap-2">
          <span>{name} can see it</span>
          <.act_form
            action="/act/revoke"
            return={@page.return}
            fields={[{"item", @page.id}, {"member", g}]}
            button="Stop sharing"
            aria={"Stop sharing #{@page.title} with #{name}"}
          />
        </li>
      </ul>
      <.act_form
        :if={@page.owner.share_options != []}
        action="/act/grant"
        return={@page.return}
        fields={[{"item", @page.id}]}
        class="flex flex-wrap items-end gap-3"
      >
        <.field
          type="select"
          id="share-with"
          name="member"
          label="Share with"
          options={@page.owner.share_options}
          no_margin
        />
        <.button type="submit" size="sm" label={@page.owner.share_label} />
      </.act_form>

      <h2 id="owners" class="pc-card__title">Who owns it</h2>
      <.act_form action="/act/owners" return={@page.return} fields={[{"item", @page.id}]}>
        <fieldset>
          <legend class="pc-label">Owners of “{@page.title}”</legend>
          <div class="flex flex-wrap gap-4">
            <label :for={o <- @page.owner.owner_choices} class="pc-checkbox-label">
              <input
                type="checkbox"
                name="owners[]"
                value={o.id}
                checked={o.checked}
                class="pc-checkbox"
              />
              <span class="pc-checkbox-text">{o.label}</span>
            </label>
          </div>
        </fieldset>
        <p class="my-2 text-sm text-gray-600 dark:text-gray-400">{@page.owner.owners_hint}</p>
        <.button type="submit" size="sm" label={@page.owner.owners_label} />
      </.act_form>
    </div>
    """
  end

  attr :page, :map, required: true

  defp reading_form(assigns) do
    ~H"""
    <h2 id="update" class="pc-card__title">Update balance</h2>
    <.act_form
      action="/act/add_reading"
      return={@page.return}
      fields={[{"item", @page.id}]}
      class="space-y-3"
    >
      <.text_field
        id="balance"
        name="balance"
        label={if @page.reading.debt?, do: "Amount owed", else: "Balance"}
        value={@page.reading.balance}
        placeholder={if @page.reading.debt?, do: "e.g. 5,200", else: "e.g. 1,240.50"}
        error={field_error(@page.reading.error, :balance)}
      />
      <.text_field
        :if={@page.reading.debt?}
        id="rate"
        name="rate"
        label="Interest rate (%)"
        value={@page.reading.rate}
        placeholder="e.g. 21.99"
        error={field_error(@page.reading.error, :rate)}
      />
      <.text_field
        :if={@page.reading.debt?}
        id="min_payment"
        name="min_payment"
        label="Minimum payment"
        value={@page.reading.min_payment}
        placeholder="e.g. 150"
        error={field_error(@page.reading.error, :min_payment)}
      />
      <.text_field
        id="on"
        name="on"
        type="date"
        label="As of"
        value={@page.reading.on}
        required
        error={field_error(@page.reading.error, :on)}
      />
      <.button type="submit" size="sm" label="Save balance" />
    </.act_form>
    <p class="text-sm text-gray-600 dark:text-gray-400">{@page.reading.hint}</p>
    """
  end

  defp field_error({field, message}, field), do: message
  defp field_error(_, _), do: nil

  # A labelled text input whose error, if any, is placed right after it and described by it (UX-003 C6).
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :placeholder, :string, default: nil
  attr :required, :boolean, default: false
  attr :error, :string, default: nil

  defp text_field(assigns) do
    ~H"""
    <div class={["pc-form-field-wrapper", @error && "pc-form-field-wrapper--error"]}>
      <label for={@id} class={["pc-label", @required && "pc-label--required"]}>{@label}</label>
      <input
        id={@id}
        name={@name}
        type={@type}
        value={@value}
        placeholder={@placeholder}
        required={@required}
        inputmode={if @type == "text", do: "decimal"}
        autocomplete="off"
        aria-invalid={if @error, do: "true"}
        aria-describedby={if @error, do: "#{@id}-error"}
        class="pc-text-input"
      />
      <p :if={@error} id={"#{@id}-error"} class="pc-form-field-error" role="alert">{@error}</p>
    </div>
    """
  end

  attr :page, :map, required: true

  defp what_if_section(assigns) do
    ~H"""
    <.card id="what-if">
      <.section_header title="What if" />
      <.card_content class="space-y-3">
        <p>{@page.what_if.base}</p>
        <p :if={result?(@page.what_if.with_extra)}>
          <b>{elem(@page.what_if.with_extra, 0)}</b> {elem(@page.what_if.with_extra, 1)}
        </p>
        <p :if={result?(@page.what_if.at_rate)}>
          <b>{elem(@page.what_if.at_rate, 0)}</b> {elem(@page.what_if.at_rate, 1)}
        </p>
        <form method="get" action={@page.return} class="space-y-3">
          <.text_field
            id="extra"
            name="extra"
            label="Extra each month"
            value={@page.what_if.extra}
            placeholder="e.g. 100"
            error={error_of(@page.what_if.with_extra)}
          />
          <.text_field
            id="whatif-rate"
            name="rate"
            label="Or a different rate (%)"
            value={@page.what_if.rate}
            placeholder="e.g. 10.5"
            error={error_of(@page.what_if.at_rate)}
          />
          <.button type="submit" size="sm" label="Work it out" />
        </form>
        <p class="text-sm text-gray-600 dark:text-gray-400">
          Worked out from the latest balance. Nothing is saved, and no payment order is suggested.
        </p>
      </.card_content>
    </.card>
    """
  end

  defp result?({:error, _}), do: false
  defp result?(nil), do: false
  defp result?(_), do: true

  defp error_of({:error, message}), do: message
  defp error_of(_), do: nil

  attr :page, :map, required: true

  defp links_section(%{page: %{links: %{value?: true}}} = assigns) do
    ~H"""
    <.card id="links">
      <.section_header title="Linked to this value" description="Only you see your links." />
      <.card_content>
        <p :if={@page.links.linked == []} class="text-gray-600 dark:text-gray-400">
          Nothing linked yet. Open an item to link it here.
        </p>
        <ul :if={@page.links.linked != []} class="space-y-2">
          <li :for={{item, name} <- @page.links.linked} class="flex flex-wrap items-center gap-2">
            <.link href={"/items/#{item}"}>{name}</.link>
            <.act_form
              action="/act/unlink"
              return={@page.return}
              fields={[{"item", item}, {"value", @page.id}]}
              button="Unlink"
              aria={"Unlink #{name} from #{@page.links.title}"}
            />
          </li>
        </ul>
      </.card_content>
    </.card>
    """
  end

  defp links_section(assigns) do
    ~H"""
    <.card id="links">
      <.section_header
        title="What it's for"
        description="Link it to what matters to you. Only you see your links."
      />
      <.card_content class="space-y-3">
        <p :if={@page.links.linked == []} class="text-gray-600 dark:text-gray-400">
          Not linked to anything you value.
        </p>
        <ul :if={@page.links.linked != []} class="space-y-2">
          <li :for={{v, name} <- @page.links.linked} class="flex flex-wrap items-center gap-2">
            <span>{name}</span>
            <.act_form
              action="/act/unlink"
              return={@page.return}
              fields={[{"item", @page.id}, {"value", v}]}
              button="Unlink"
              aria={"Unlink from #{name}"}
            />
          </li>
        </ul>
        <p :if={@page.links.no_values?} class="text-sm text-gray-600 dark:text-gray-400">
          Add a value on the <.link href={~p"/"}>main page</.link> to link this to it.
        </p>
        <.act_form
          :if={@page.links.options != []}
          action="/act/link"
          return={@page.return}
          fields={[{"item", @page.id}]}
          class="flex flex-wrap items-end gap-3"
        >
          <.field
            type="select"
            id="link-value"
            name="value"
            label="Link to"
            options={@page.links.options}
            no_margin
          />
          <.button type="submit" size="sm" label="Link" />
        </.act_form>
      </.card_content>
    </.card>
    """
  end

  attr :page, :map, required: true

  defp account_section(assigns) do
    ~H"""
    <.card id="account">
      <.section_header title="Which account does it go through?" description={@page.account.hint} />
      <.card_content>
        <.act_form
          action="/act/attach"
          return={@page.return}
          fields={[{"item", @page.id}]}
          class="flex flex-wrap items-end gap-3"
        >
          <.field
            type="select"
            id="through"
            name="account"
            label="Account"
            options={@page.account.options}
            selected={@page.account.current}
            no_margin
          />
          <.button type="submit" size="sm" label="Save" />
        </.act_form>
      </.card_content>
    </.card>
    """
  end

  attr :page, :map, required: true

  defp depends_section(assigns) do
    ~H"""
    <.card id="depends">
      <.section_header
        title="Does it depend on a job?"
        description="If this stops when a job stops (like an employer's health plan or a commute), mark it. In a plan, switching off the job switches this off too. Only you see your marks."
      />
      <.card_content class="space-y-3">
        <ul :if={@page.depends.marks != []} class="space-y-2">
          <li :for={{j, job} <- @page.depends.marks} class="flex flex-wrap items-center gap-2">
            <span>Depends on {job}</span>
            <.act_form
              action="/act/unmark"
              return={@page.return}
              fields={[{"item", @page.id}, {"job", j}]}
              button="Remove"
              aria={"Stop marking it as depending on #{job}"}
            />
          </li>
        </ul>
        <p :if={@page.depends.jobs == []} class="text-sm text-gray-600 dark:text-gray-400">
          Add a paycheck or other income you own to mark this as depending on it.
        </p>
        <.act_form
          :if={@page.depends.jobs != []}
          action="/act/mark"
          return={@page.return}
          fields={[{"item", @page.id}]}
          class="flex flex-wrap items-end gap-3"
        >
          <.field
            type="select"
            id="job"
            name="job"
            label="Depends on"
            options={@page.depends.jobs}
            no_margin
          />
          <.button type="submit" size="sm" label="Mark" />
        </.act_form>
      </.card_content>
    </.card>
    """
  end

  attr :page, :map, required: true

  defp history_section(assigns) do
    ~H"""
    <.card :if={@page.history} id="history">
      <.section_header title="History" />
      <.card_content>
        <ol class="list-decimal space-y-1 pl-6">
          <li :for={e <- @page.history}>{e}</li>
        </ol>
      </.card_content>
    </.card>
    """
  end

  # UX-001 R3: only actions that can succeed. A sole owner gets Give away and Delete; a joint owner gets Stop
  # owning, behind a confirmation because they can only regain it if the others agree.
  attr :page, :map, required: true

  defp let_go_section(assigns) do
    ~H"""
    <.card id="let-go">
      <.section_header title={if @page.sole?, do: "Give away or delete", else: "Stop owning"} />
      <.card_content class="flex flex-wrap items-center gap-3">
        <%= if @page.sole? do %>
          <.link href="#owners" aria-label={"Give away #{@page.title}"}>Give away…</.link>
          <.act_form
            action="/confirm/delete"
            return={@page.return}
            fields={[{"item", @page.id}]}
            button="Delete…"
            aria={"Delete #{@page.title}"}
            danger
          />
        <% else %>
          <.act_form
            action="/confirm/relinquish"
            return={@page.return}
            fields={[{"item", @page.id}]}
            button="Stop owning…"
            aria={"Stop owning #{@page.title}"}
            danger
          />
        <% end %>
      </.card_content>
    </.card>
    """
  end

  # Petal's card header, with the title as a heading so each section is in the page's outline under the h1
  # (as HouseholdHTML's).
  attr :title, :string, required: true
  attr :description, :string, default: nil

  defp section_header(assigns) do
    ~H"""
    <div class="pc-card__header">
      <div class="pc-card__header-titles">
        <h2 class="pc-card__title">{@title}</h2>
        <div :if={@description} class="pc-card__description">{@description}</div>
      </div>
    </div>
    """
  end

  def not_found(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.h1>Not available</.h1>
      <.card>
        <.card_content class="space-y-3">
          <.p>
            That isn't available to you. It may have been deleted, or it isn't shared with you.
          </.p>
          <.p><.link href={~p"/"}>Back to everything</.link></.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # REQ-166: deleting, or stopping owning, is shown by name and asked first; the only form that does it is here.
  def confirm(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.h1>{@heading}</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.p>{@body}</.p>
          <.act_form action={"/act/#{@action}"} fields={@fields} button={@yes} danger />
          <.p><.link href={~p"/"}>No, go back</.link></.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end
end
