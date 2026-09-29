defmodule FindependenceHostedWeb.HomeHTML do
  @moduledoc """
  The household page (WI-075): what the local form's home says (app/lib/findependence_app/web/html.ex
  `home/5`), in the same words, as Petal markup. What is waiting for the member comes first (UX-001 R7);
  items, values, accounts and debts are listed compactly, each linking to its own page (UX-001 R1, REQ-172).
  Members are named by their display names; ids are only ever sent by forms.
  """
  use FindependenceHostedWeb, :html

  alias FindependenceShared.{Balances, CashFlow, Decode, Items, Planning, Values, Words}

  @totals_hint "Totals of what you can see, by what you've linked it to. Items that repeat are shown per month (weekly, every-two-weeks, and yearly amounts are converted); one-off items are shown apart. To link an item, open it. Only you can see your links, and an item linked to two values counts toward both."

  # REQ-106 applies to the running balance too; say so, so a gap isn't mistaken for a shortfall.
  @only_visible "Counts items you own, and items shared with you that you've said go through these accounts; anything others keep private isn't included."

  # REQ-129: how often, in the local form's order and words; the choices are Decode's (checked below).
  @frequencies [
    {"Every month", "monthly"},
    {"Every two weeks", "biweekly"},
    {"Every week", "weekly"},
    {"Every two months", "every_2_months"},
    {"Every three months", "every_3_months"},
    {"Twice a year", "twice_a_year"},
    {"Every year", "yearly"},
    {"Irregular (enter the total for a year)", "irregular"},
    {"One-off", "one_off"}
  ]

  if Enum.sort(Enum.map(@frequencies, &elem(&1, 1))) != Enum.sort(Map.keys(Decode.frequencies())),
    do: raise("the add-item form's choices must be exactly Decode.frequencies/0")

  @doc "The add-item form's choices of how often, as {words, choice}."
  def frequency_choices, do: @frequencies

  def home(assigns) do
    %{scope: scope, today: today} = assigns
    m = scope.member
    visible = Items.visible(scope)

    # CAP-010: accounts and debts have their own list; shared plans live on the plans page
    {balances, rest} =
      visible
      |> Enum.reject(&Planning.plan?/1)
      |> Enum.split_with(&Balances.balance?/1)

    {values, items} = Enum.split_with(rest, &Values.value?/1)
    {mine, theirs} = Items.pending(scope) |> Enum.split_with(&(m not in &1.consents))

    # a controller's assigns carry no change tracking, so these are merged in, not assigned
    assigns =
      Map.merge(assigns, %{
        me: m,
        items: items,
        values: values,
        balances: balances,
        mine: mine,
        theirs: theirs,
        pending: mine ++ theirs,
        names: Words.names(scope.household, m),
        owners_of: Words.owners_of(visible),
        flow: CashFlow.cash_flow(scope, today, 14)
      })

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <h1 class="sr-only">Findependence</h1>
      <.page_message message={@message} />

      <.card :if={@mine != []} id="waiting">
        <.section_header title="Waiting for you" />
        <.card_content>
          <.pending_list
            list={@mine}
            names={@names}
            owners_of={@owners_of}
            me={@me}
            name_of={@name_of}
          />
        </.card_content>
      </.card>

      <.coming_up flow={@flow} scope={@scope} name_of={@name_of} today={@today} />

      <.card>
        <.section_header
          title="Your items"
          description="Money in and out: items you own, and items others share with you. Open one to share it, change who owns it, or link it to a value."
        />
        <.card_content class="space-y-6">
          <.thing_list
            things={@items}
            kind={:item}
            me={@me}
            pending={@pending}
            name_of={@name_of}
          />
          <.add_item_form form={@form} />
        </.card_content>
      </.card>

      <.card>
        <.section_header
          title="What matters to you"
          description="Your values, in your own words. Nothing here is scored or judged, and only you decide who can see them."
        />
        <.card_content class="space-y-6">
          <.thing_list
            things={@values}
            kind={:value}
            me={@me}
            pending={@pending}
            name_of={@name_of}
          />
          <.act_form
            action="/act/add_value"
            return="/"
            button="Add value"
            class="flex flex-wrap items-end gap-3"
          >
            <div class="pc-form-field-wrapper pc-form-field-wrapper--no-margin">
              <.field_label for="label">A value</.field_label>
              <input
                id="label"
                name="label"
                type="text"
                required
                placeholder="e.g. Time with the kids"
                class="pc-text-input"
              />
            </div>
          </.act_form>
        </.card_content>
      </.card>

      <.balances_card
        balances={@balances}
        scope={@scope}
        me={@me}
        name_of={@name_of}
        today={@today}
      />

      <.card>
        <.section_header title="Your money and what matters to you" />
        <.card_content class="space-y-4">
          <p :if={@items == []} class="pc-text">Totals appear once you add items.</p>
          <p :if={@items != []} class="pc-text">{totals_hint()}</p>
          <.distribution :if={@items != []} scope={@scope} values={@values} />
        </.card_content>
      </.card>

      <.card :if={@theirs != []}>
        <.section_header title="Waiting for others" />
        <.card_content>
          <.pending_list
            list={@theirs}
            names={@names}
            owners_of={@owners_of}
            me={@me}
            name_of={@name_of}
          />
        </.card_content>
      </.card>

      <.card>
        <.section_header title="Leaving" />
        <.card_content class="space-y-2">
          <.p><.link href={~p"/household"}>Members and invitation codes</.link></.p>
          <.p><.link href={~p"/leave"}>Leave the household…</.link></.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  defp totals_hint, do: @totals_hint

  # ---------------------------------------------------------------------------
  # Sections

  attr :message, :any, required: true

  defp page_message(%{message: {:error, text}} = assigns) do
    assigns = assign(assigns, :text, text)
    ~H|<.alert variant="soft" color="danger" label={@text} />|
  end

  defp page_message(%{message: {:ok, text}} = assigns) do
    assigns = assign(assigns, :text, text)
    ~H|<.alert variant="soft" color="success" label={@text} />|
  end

  defp page_message(assigns), do: ~H""

  # Petal's card_header, with the title as a heading, so the page's sections are in its outline under the
  # h1 (as HouseholdHTML).
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

  # A compact, action-free list: each item or value links to its own page (UX-001 R1). The figure and how
  # often it happens have their own cells, so figures line up (UX-003 C10, REQ-129 AC-6).
  attr :things, :list, required: true
  attr :kind, :atom, required: true
  attr :me, :string, required: true
  attr :pending, :list, required: true
  attr :name_of, :any, required: true

  defp thing_list(%{things: []} = assigns) do
    ~H"""
    <p class="pc-text">{if @kind == :item, do: "No items yet.", else: "No values yet."}</p>
    """
  end

  defp thing_list(assigns) do
    assigns =
      assign(assigns,
        rows: Enum.sort_by(assigns.things, &String.downcase(Words.title(&1))),
        caption: if(assigns.kind == :item, do: "Your items", else: "Your values")
      )

    ~H"""
    <.table_frame label={@caption}>
      <thead>
        <tr class="pc-table__tr">
          <.col_head label={if @kind == :item, do: "Item", else: "Value"} />
          <.col_head :if={@kind == :item} label="Amount" num />
          <.col_head :if={@kind == :item} label="How often" />
          <.col_head label="Owned by" />
          <.col_head label="Who else can see it" />
        </tr>
      </thead>
      <tbody>
        <tr :for={i <- @rows} class="pc-table__tr">
          <td class="pc-table__td">
            <.link href={"/items/#{i.id}"} class="font-semibold">{Words.title(i)}</.link>
            <.badge
              :if={waiting_on(@pending, i) > 0}
              variant="soft"
              color="warning"
              label={"#{waiting_on(@pending, i)} waiting"}
            />
          </td>
          <td :if={@kind == :item} class="pc-table__td text-right tabular-nums whitespace-nowrap">
            {Words.figure_text(i.attrs)}
          </td>
          <td :if={@kind == :item} class="pc-table__td">{Words.frequency_text(i.attrs)}</td>
          <td class="pc-table__td">{Words.people(i.owners, @me, "No one", @name_of)}</td>
          <td class="pc-table__td">{visibility_summary(i, @me, @name_of)}</td>
        </tr>
      </tbody>
    </.table_frame>
    """
  end

  defp waiting_on(pending, i), do: Enum.count(pending, &(&1.item_id == i.id))

  defp visibility_summary(i, m, name_of) do
    cond do
      m not in i.owners -> "Shared with you"
      Map.get(i, :grantees, []) == [] -> "Only the owners"
      true -> Words.people(i.grantees, m, "No one", name_of)
    end
  end

  # UX-001 R2: amount as text with an explicit direction; errors shown at the field, input kept.
  # REQ-129: how often it happens is chosen explicitly; there is no default. REQ-136: one optional date.
  attr :form, :map, required: true

  defp add_item_form(assigns) do
    form = assigns.form

    assigns =
      assign(assigns,
        error: form[:error],
        error_field: form[:error_field] || :amount,
        direction: form[:direction] || "out",
        frequencies: @frequencies
      )

    ~H"""
    <.act_form action="/act/add_item" id="add-item" button="Add" class="space-y-4">
      <div class="grid gap-x-4 sm:grid-cols-2">
        <.typed_field
          id="note"
          label="What is it?"
          value={@form[:note]}
          error={@error_field == :note && @error}
          required
          maxlength="200"
          placeholder="e.g. Rent"
        />
        <.typed_field
          id="amount"
          label="Amount"
          value={@form[:amount]}
          error={@error_field == :amount && @error}
          inputmode="decimal"
          autocomplete="off"
          placeholder="e.g. 62.40"
        />
        <div class={[
          "pc-form-field-wrapper",
          @error_field == :frequency && @error && "pc-form-field-wrapper--error"
        ]}>
          <.field_label for="frequency">How often?</.field_label>
          <select
            id="frequency"
            name="frequency"
            required
            class="pc-text-input"
            aria-invalid={@error_field == :frequency && @error && "true"}
            aria-describedby={@error_field == :frequency && @error && "frequency-error"}
          >
            <option value="">Choose…</option>
            {Phoenix.HTML.Form.options_for_select(@frequencies, @form[:frequency])}
          </select>
          <.error_at id="frequency" error={@error_field == :frequency && @error} />
        </div>
        <.typed_field
          id="on"
          type="date"
          label="Date it happens"
          optional
          value={@form[:on]}
          error={@error_field == :on && @error}
        />
      </div>
      <fieldset class="pc-form-field-wrapper">
        <legend class="pc-label">Money</legend>
        <div class="pc-radio-group pc-radio-group--row">
          <label
            :for={{value, words} <- [{"out", "Money out"}, {"in", "Money in"}]}
            class="pc-checkbox-label"
          >
            <input
              type="radio"
              name="direction"
              value={value}
              checked={value == @direction}
              class="pc-radio"
            />
            <span>{words}</span>
          </label>
        </div>
      </fieldset>
    </.act_form>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :value, :any, default: nil
  attr :error, :any, default: nil
  attr :optional, :boolean, default: false
  attr :rest, :global, include: ~w(required maxlength placeholder autocomplete inputmode)

  defp typed_field(assigns) do
    ~H"""
    <div class={["pc-form-field-wrapper", @error && "pc-form-field-wrapper--error"]}>
      <.field_label for={@id}>
        {@label}<span :if={@optional} class="pc-form-help-text inline"> (optional)</span>
      </.field_label>
      <input
        id={@id}
        name={@id}
        type={@type}
        value={@value}
        class="pc-text-input"
        aria-invalid={@error && "true"}
        aria-describedby={@error && "#{@id}-error"}
        {@rest}
      />
      <.error_at id={@id} error={@error} />
    </div>
    """
  end

  # UX-003 C6: a field's error, in the field's own group, directly under it
  attr :id, :string, required: true
  attr :error, :any, required: true

  defp error_at(assigns) do
    ~H"""
    <p :if={@error} id={"#{@id}-error"} class="pc-form-field-error" role="alert">{@error}</p>
    """
  end

  # REQ-161: the next fourteen days on home: at most four days with something on them, how many more, and
  # a way to the full view.
  attr :flow, :map, required: true
  attr :scope, :any, required: true
  attr :name_of, :any, required: true
  attr :today, :any, required: true

  defp coming_up(assigns) do
    %{start: start, days: days} = assigns.flow
    dated = Enum.filter(days, &(&1.entries != []))

    assigns =
      assign(assigns,
        start: start,
        shown: Enum.take(dated, 4),
        more: length(dated) - 4,
        partial?: start != nil and joint_owners(assigns.scope, start.accounts) != nil
      )

    ~H"""
    <.card id="coming-up">
      <.section_header title="Coming up" />
      <.card_content class="space-y-4">
        <%= cond do %>
          <% @shown == [] and @start == nil -> %>
            <p class="pc-text">
              Coming up needs an account's balance and the date each bill or paycheck happens. <.link href={
                ~p"/balances/new"
              }>Add an account and its balance</.link>, and give items a date when you <.link href="#add-item">add them</.link>.
            </p>
          <% @shown == [] -> %>
            <p class="pc-text">
              Nothing dated in the next 14 days. Add the date a bill or paycheck happens to see it here.
            </p>
          <% true -> %>
            <.start_line start={@start} scope={@scope} name_of={@name_of} today={@today} />
            <.flow_table days={@shown} label="Coming up" partial?={@partial?} today={@today} />
            <p :if={@more > 0} class="pc-text">
              And {@more} more {if @more == 1, do: "day", else: "days"} with something on them in the next 14.
            </p>
        <% end %>
        <p class="pc-text">
          <.link href={~p"/next-60-days"}>The next 60 days</.link>
          · <.link href={~p"/ahead"}>The next 12 months</.link>
        </p>
      </.card_content>
    </.card>
    """
  end

  attr :start, :any, required: true
  attr :scope, :any, required: true
  attr :name_of, :any, required: true
  attr :today, :any, required: true

  defp start_line(%{start: nil} = assigns) do
    ~H"""
    <p class="pc-text">
      To see a running balance, <.link href={~p"/balances/new"}>add your checking account</.link>
      and its balance.
    </p>
    """
  end

  defp start_line(assigns) do
    %{start: start, scope: scope} = assigns
    names = Enum.map(start.accounts, &Words.title(Items.lookup(scope, &1))) |> Words.people()

    assigns =
      assign(assigns,
        text:
          "Starting from #{names}: #{Words.plain_amount(start.balance)} as of #{date(start.on, assigns.today)}. " <>
            counted_note(scope, start.accounts, assigns.name_of)
      )

    ~H"""
    <p class="pc-text">{@text}</p>
    """
  end

  # UX-002 R1a, UX-004 P2: on an account someone else also owns, the view is the member's part, and says
  # whose items it leaves out, by name.
  defp counted_note(scope, account_ids, name_of) do
    case joint_owners(scope, account_ids) do
      nil ->
        @only_visible

      {accounts, others} ->
        own = if length(others) == 1, do: "owns", else: "own"
        whom = Words.people(others, nil, "No one", name_of)

        "#{whom} also #{own} #{Words.people(accounts)}, so this is your part: items #{whom} #{own} count only once they're shared with you and you say they go through it."
    end
  end

  defp joint_owners(scope, account_ids) do
    others_of = fn id ->
      MapSet.delete(MapSet.new(Items.lookup(scope, id).owners), scope.member)
    end

    joint = Enum.filter(account_ids, &(MapSet.size(others_of.(&1)) > 0))

    case joint do
      [] ->
        nil

      ids ->
        others = ids |> Enum.flat_map(&MapSet.to_list(others_of.(&1))) |> Enum.uniq()
        {Enum.map(ids, &Words.title(Items.lookup(scope, &1))), others}
    end
  end

  # One row per day that has something on it: what, the day's net amount, and the balance after.
  attr :days, :list, required: true
  attr :label, :string, required: true
  attr :partial?, :boolean, required: true
  attr :today, :any, required: true

  defp flow_table(assigns) do
    ~H"""
    <.table_frame label={@label}>
      <thead>
        <tr class="pc-table__tr">
          <.col_head label="Date" />
          <.col_head label="What" />
          <.col_head label="Net" num />
          <.col_head label={if @partial?, do: "Your part after", else: "Balance after"} num />
        </tr>
      </thead>
      <tbody>
        <tr :for={d <- @days} class="pc-table__tr">
          <td class="pc-table__td font-semibold whitespace-nowrap">{date(d.date, @today)}</td>
          <td class="pc-table__td">
            <%= for {{i, a}, n} <- Enum.with_index(d.entries) do %>
              <br :if={n > 0} />
              <.link href={"/items/#{i.id}"}>{Words.title(i)}</.link>
              <span class="whitespace-nowrap">{Words.format_amount(a)}</span>
            <% end %>
          </td>
          <td class="pc-table__td text-right tabular-nums whitespace-nowrap">
            {Words.format_amount(d.entries |> Enum.map(&elem(&1, 1)) |> Enum.sum())}
          </td>
          <td class="pc-table__td text-right tabular-nums whitespace-nowrap">
            <.balance_cell balance={d.balance} />
          </td>
        </tr>
      </tbody>
    </.table_frame>
    """
  end

  attr :balance, :any, required: true

  defp balance_cell(%{balance: nil} = assigns), do: ~H""

  # REQ-139's mark, read after the figure; a figure and its mark are one unit (DEF-034)
  defp balance_cell(%{balance: b} = assigns) when b < 0 do
    ~H"""
    <span class="whitespace-nowrap">
      {Words.plain_amount(@balance)} <.badge variant="soft" color="danger" label="Below zero" />
    </span>
    """
  end

  defp balance_cell(assigns), do: ~H"{Words.plain_amount(@balance)}"

  # CAP-010, REQ-172: accounts and debts, one row each, linking to their pages; no forms here.
  attr :balances, :list, required: true
  attr :scope, :any, required: true
  attr :me, :string, required: true
  attr :name_of, :any, required: true
  attr :today, :any, required: true

  defp balances_card(assigns) do
    assigns =
      assign(assigns,
        rows:
          assigns.balances
          |> Enum.sort_by(&{&1.attrs.kind, String.downcase(Words.title(&1))})
          |> Enum.map(&{&1, Balances.latest(assigns.scope, &1.id)})
      )

    ~H"""
    <.card>
      <.section_header
        title="Balances and debts"
        description={
          if @rows == [],
            do: "What's in your accounts and what you owe. Private to you unless you share it.",
            else:
              "What's in your accounts and what you owe, as last updated. Open one to update it or share it."
        }
      />
      <.card_content class="space-y-4">
        <p :if={@rows == []} class="pc-text">No accounts or debts yet.</p>
        <.table_frame :if={@rows != []} label="Balances and debts">
          <thead>
            <tr class="pc-table__tr">
              <.col_head label="Account or debt" />
              <.col_head label="Balance" num />
              <.col_head label="Owned by" />
              <.col_head label="Kind and date" />
            </tr>
          </thead>
          <tbody>
            <tr :for={{i, r} <- @rows} class="pc-table__tr">
              <td class="pc-table__td">
                <.link href={"/items/#{i.id}"} class="font-semibold">{Words.title(i)}</.link>
              </td>
              <td class="pc-table__td text-right tabular-nums whitespace-nowrap">
                {Words.balance_text(i, r)}
              </td>
              <td class="pc-table__td">{Words.people(i.owners, @me, "No one", @name_of)}</td>
              <td class="pc-table__td">{kind_and_date(i, r, @today)}</td>
            </tr>
          </tbody>
        </.table_frame>
        <.button
          link_type="a"
          to={~p"/balances/new"}
          variant="outline"
          label="Add an account or debt"
        />
      </.card_content>
    </.card>
    """
  end

  defp kind_and_date(i, nil, _today), do: Words.kind_words(i)
  defp kind_and_date(i, r, today), do: "#{Words.kind_words(i)}, as of #{date(r.on, today)}"

  # REQ-126: per month in and out over repeating items, one-off in and out apart; no evaluation.
  attr :scope, :any, required: true
  attr :values, :list, required: true

  defp distribution(assigns) do
    %{by_value: bv, unlinked: u} = Values.distribution(assigns.scope)
    label = Map.new(assigns.values, &{&1.id, &1.attrs[:label]})

    assigns =
      assign(assigns,
        rows: Enum.sort_by(bv, fn {id, _} -> String.downcase(label[id] || "") end),
        label: label,
        unlinked: u
      )

    ~H"""
    <.table_frame label="Totals by value">
      <thead>
        <tr class="pc-table__tr">
          <.col_head label="What matters to you" />
          <.col_head label="Money in, per month" num />
          <.col_head label="Money out, per month" num />
          <.col_head label="One-off in" num />
          <.col_head label="One-off out" num />
          <.col_head label="Items" num />
        </tr>
      </thead>
      <tbody>
        <tr :for={{id, b} <- @rows} class="pc-table__tr">
          <td class="pc-table__td"><.link href={"/items/#{id}"}>{@label[id]}</.link></td>
          <.total_cells b={b} />
        </tr>
        <tr class="pc-table__tr text-gray-500 dark:text-gray-400">
          <td class="pc-table__td">Not linked to anything</td>
          <.total_cells b={@unlinked} />
        </tr>
      </tbody>
    </.table_frame>
    """
  end

  attr :b, :map, required: true

  defp total_cells(assigns) do
    ~H"""
    <td
      :for={cents <- [@b.per_month.in, @b.per_month.out, @b.one_off.in, @b.one_off.out]}
      class="pc-table__td text-right tabular-nums whitespace-nowrap"
    >
      {Words.format_amount(cents)}
    </td>
    <td class="pc-table__td text-right tabular-nums">{@b.count}</td>
    """
  end

  # Waiting changes (UX-001 R7): Agree for changes this member hasn't agreed to; Withdraw for the item's
  # owners (REQ-125); and who is still needed.
  attr :list, :list, required: true
  attr :names, :map, required: true
  attr :owners_of, :map, required: true
  attr :me, :string, required: true
  attr :name_of, :any, required: true

  defp pending_list(assigns) do
    ~H"""
    <ul class="space-y-3">
      <li :for={p <- @list} class="flex flex-wrap items-center gap-x-3 gap-y-2">
        <span>{proposal_text(p, @names, @me, @name_of)}</span>
        <span class="pc-form-help-text">{status_text(p, @owners_of, @me, @name_of)}</span>
        <.link :if={Map.has_key?(@names, p.item_id)} href={"/items/#{p.item_id}"}>Open</.link>
        <.act_form
          :if={@me not in p.consents}
          action="/act/consent"
          return="/"
          fields={[{"proposal", p.id}]}
          button="Agree"
          aria={"Agree: #{proposal_text(p, @names, @me, @name_of)}"}
          class="inline"
        />
        <.act_form
          :if={@me in owners(@owners_of, p)}
          action="/act/withdraw"
          return="/"
          fields={[{"proposal", p.id}]}
          button="Withdraw"
          aria="Withdraw this request"
          class="inline"
        />
      </li>
    </ul>
    """
  end

  defp owners(owners_of, p), do: get_in(owners_of, [p.item_id, :owners]) || MapSet.new()

  defp status_text(p, owners_of, m, name_of) do
    needed = Words.needed(p, owners_of) |> MapSet.difference(MapSet.new(p.consents))

    cond do
      m in p.consents -> "Waiting for #{Words.people(needed, m, "no one", name_of)}."
      p.consents == [] -> ""
      true -> "Agreed so far: #{Words.people(p.consents, nil, "No one", name_of)}."
    end
  end

  # As the local form's proposal_text/3, with members by their display names.
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

  # ---------------------------------------------------------------------------
  # Tables: a scrolling frame with the table's name, and header cells with their scope; a numeric column's
  # header aligns with its figures (UX-003 C2).

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp table_frame(assigns) do
    ~H"""
    <div class="overflow-x-auto" tabindex="0" role="region" aria-label={@label}>
      <table class="pc-table--basic pc-table--compact w-full">
        <caption class="sr-only">{@label}</caption>
        {render_slot(@inner_block)}
      </table>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :num, :boolean, default: false

  defp col_head(assigns) do
    ~H"""
    <th scope="col" class={["pc-table__th", @num && "text-right"]}>{@label}</th>
    """
  end

  defp date(%Date{} = d, today), do: Words.date_text(Date.to_iso8601(d), today)
  defp date(iso, today), do: Words.date_text(iso, today)
end
