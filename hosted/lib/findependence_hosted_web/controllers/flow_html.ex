defmodule FindependenceHostedWeb.FlowHTML do
  @moduledoc """
  The next sixty days, the next twelve months, and adding an account or a debt (WI-075): what the local form's
  pages say, in the same words (FindependenceShared.Words), with members named by their display names.
  """
  use FindependenceHostedWeb, :html

  alias FindependenceShared.{Items, Words}

  # REQ-106 applies to the running balance too; say so, so a gap isn't mistaken for a shortfall.
  # REQ-162 (DEF-048): says what the months count, including shared items attached to your accounts
  @assumptions "How this is worked out: repeating items count at their per-month amount; one-off items count in their month when they have a date; cash starts from the latest balances of the accounts you can see; each debt grows by a month's interest and falls by its minimum payment. It counts items you own, and items shared with you that you've said go through your accounts, and nothing is advice."

  @account_kinds [
    {"Checking", "checking"},
    {"Savings", "savings"},
    {"401(k)", "retirement_401k"},
    {"IRA", "ira"},
    {"Other", "other"}
  ]
  @debt_kinds [{"Credit card", "card"}, {"HELOC", "heloc"}, {"Loan", "loan"}, {"Other", "other"}]

  # ---------------------------------------------------------------------------
  # REQ-161, REQ-173, REQ-140: the next sixty days

  def next_60_days(assigns) do
    %{start: start, days: days} = assigns.flow

    assigns =
      page_assigns(assigns,
        start: start,
        rows: Enum.filter(days, &(&1.entries != [])),
        below: below_ranges(days, assigns.today),
        partial: start != nil and partial?(assigns.scope, start.accounts)
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.h1>The next 60 days</.h1>

      <.card>
        <.card_content class="space-y-4">
          <.p class="text-sm">
            What's dated, day by day, from {date(@today, @today)}. Only items with a date appear; irregular items have no dates.
          </.p>
          <.p :if={@rows != [] and @start == nil} class="text-sm">
            To see a running balance,
            <.link href={~p"/balances/new"}>add your checking account</.link>
            and its balance.
          </.p>
          <.p :if={@rows != [] and @start != nil} id="starts-from" class="text-sm">
            Starting from {Words.people(account_titles(@scope, @start.accounts))}: {Words.plain_amount(
              @start.balance
            )} as of {date(@start.on, @today)}. {counted_note(@scope, @start.accounts, @name_of)}
          </.p>
          <.p :if={@below != []} id="below-zero">
            <b>Below zero:</b> {Enum.join(@below, "; ")}.
          </.p>
          <.p :if={@rows == []}>Nothing dated in the next 60 days.</.p>
          <div :if={@rows != []} class="overflow-x-auto">
            <table class="pc-table--basic w-full" aria-label="The next 60 days" id="flow">
              <thead>
                <.tr>
                  <th scope="col" class="pc-table__th">Date</th>
                  <th scope="col" class="pc-table__th">What</th>
                  <th scope="col" class="pc-table__th text-right">Net</th>
                  <th scope="col" class="pc-table__th text-right">
                    {if @partial, do: "Your part after", else: "Balance after"}
                  </th>
                </.tr>
              </thead>
              <tbody>
                <.tr :for={d <- @rows}>
                  <th scope="row" class="pc-table__td text-left font-semibold">
                    {date(d.date, @today)}
                  </th>
                  <.td>
                    <div :for={{i, a} <- d.entries}>
                      <.link href={"/items/" <> i.id}>{Words.title(i)}</.link>
                      <span class="whitespace-nowrap">{Words.format_amount(a)}</span>
                    </div>
                  </.td>
                  <.td class="text-right whitespace-nowrap">
                    {Words.format_amount(d.entries |> Enum.map(&elem(&1, 1)) |> Enum.sum())}
                  </.td>
                  <.td class="text-right whitespace-nowrap">
                    <.cash cents={d.balance} />
                  </.td>
                </.tr>
              </tbody>
            </table>
          </div>
        </.card_content>
      </.card>

      <.card>
        <.section_header
          title="Setting aside for bills that come a few times a year"
          description="Money-out items you own that happen less often than monthly, as a monthly amount."
        />
        <.card_content>
          <.p :if={@set_asides.items == []}>
            No money-out items that happen less often than monthly.
          </.p>
          <div :if={@set_asides.items != []} class="space-y-2">
            <.p>
              Setting aside <b>{Words.plain_amount(@set_asides.total)} a month</b> covers these:
            </.p>
            <ul class="space-y-1" id="set-asides">
              <li :for={{i, c} <- @set_asides.items}>
                <.link href={"/items/" <> i.id}>{Words.title(i)}</.link>: {Words.money_line(i.attrs)}, {Words.plain_amount(
                  c
                )} a month
              </li>
            </ul>
          </div>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # The stretches of days below zero, each as a day or "from to" (REQ-173 AC-4).
  defp below_ranges(days, today) do
    days
    |> Enum.chunk_by(&(&1.balance != nil and &1.balance < 0))
    |> Enum.filter(fn [d | _] -> d.balance != nil and d.balance < 0 end)
    |> Enum.map(fn chunk ->
      {a, b} = {hd(chunk).date, List.last(chunk).date}
      if a == b, do: date(a, today), else: date(a, today) <> " to " <> date(b, today)
    end)
  end

  # ---------------------------------------------------------------------------
  # REQ-162: the next twelve months

  def ahead(assigns) do
    p = assigns.projection

    assigns =
      page_assigns(assigns,
        p: p,
        cash_label:
          if(p.start && partial?(assigns.scope, p.start.accounts),
            do: "Your part at the end",
            else: "Cash at the end"
          ),
        assumptions: @assumptions
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.h1>The next 12 months</.h1>

      <.card>
        <.card_content class="space-y-4">
          <.p :if={@p.start == nil} class="text-sm">
            To see cash month by month, <.link href={~p"/balances/new"}>add an account</.link>
            and its balance.
          </.p>
          <.p :if={@p.start != nil} id="cash-starts" class="text-sm">
            Cash starts from {Words.people(account_titles(@scope, @p.start.accounts))}: {Words.plain_amount(
              @p.start.cash
            )}. {counted_note(@scope, @p.start.accounts, @name_of)}
          </.p>
          <div class="overflow-x-auto">
            <table class="pc-table--basic w-full" aria-label="The next 12 months" id="months">
              <thead>
                <.tr>
                  <th scope="col" class="pc-table__th">Month</th>
                  <th scope="col" class="pc-table__th text-right">In</th>
                  <th scope="col" class="pc-table__th text-right">Out</th>
                  <th scope="col" class="pc-table__th text-right">Net</th>
                  <th scope="col" class="pc-table__th text-right">{@cash_label}</th>
                </.tr>
              </thead>
              <tbody>
                <.tr :for={r <- @p.months}>
                  <th scope="row" class="pc-table__td text-left font-semibold">
                    {Words.month_text(r.month)}
                  </th>
                  <.td class="text-right whitespace-nowrap">{Words.format_amount(r.in)}</.td>
                  <.td class="text-right whitespace-nowrap">{Words.format_amount(r.out)}</.td>
                  <.td class="text-right whitespace-nowrap">{Words.format_amount(r.net)}</.td>
                  <.td class="text-right whitespace-nowrap"><.cash cents={r.cash} /></.td>
                </.tr>
              </tbody>
            </table>
          </div>
          <.p class="text-sm" id="assumptions">{@assumptions}</.p>
        </.card_content>
      </.card>

      <.card :if={@p.debts != []}>
        <.section_header
          title="Debts over the next 12 months"
          description="Paying each debt's minimum payment, at its latest rate."
        />
        <.card_content>
          <div class="overflow-x-auto">
            <table
              class="pc-table--basic w-full"
              aria-label="Debts over the next 12 months"
              id="debts"
            >
              <thead>
                <.tr>
                  <th scope="col" class="pc-table__th">Debt</th>
                  <th scope="col" class="pc-table__th text-right">Now</th>
                  <th scope="col" class="pc-table__th text-right">In 12 months</th>
                  <th scope="col" class="pc-table__th text-right">Interest over 12 months</th>
                  <th scope="col" class="pc-table__th">Paid off</th>
                </.tr>
              </thead>
              <tbody>
                <.tr :for={d <- @p.debts}>
                  <th scope="row" class="pc-table__td text-left font-semibold">
                    <.link :if={d.id} href={"/items/" <> d.id}>{debt_name(d)}</.link>
                    <span :if={!d.id}>{debt_name(d)}</span>
                  </th>
                  <.td class="text-right whitespace-nowrap">{Words.plain_amount(d.balance)}</.td>
                  <.td class="text-right whitespace-nowrap">
                    {Words.plain_amount(List.last(d.months))}
                  </.td>
                  <.td class="text-right whitespace-nowrap">{Words.plain_amount(d.interest)}</.td>
                  <.td>
                    {if d.paid_off, do: Words.month_text(d.paid_off), else: "Not within 12 months"}
                  </.td>
                </.tr>
              </tbody>
            </table>
          </div>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  defp debt_name(%{planned: true} = d), do: "#{d.name} (plan, from #{Words.month_text(d.from)})"
  defp debt_name(d), do: d.name

  # ---------------------------------------------------------------------------
  # REQ-130: adding an account or a debt

  def new_balance(assigns) do
    assigns = page_assigns(assigns, account_kinds: @account_kinds, debt_kinds: @debt_kinds)

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.h1>Add an account or debt</.h1>

      <.card>
        <.section_header
          title="Add an account"
          description="Checking, savings, or another account. You'll add its balance next. Only you can see it unless you share it."
        />
        <.card_content>
          <.act_form action="/act/add_account" button="Add account" class="max-w-md">
            <.balance_fields
              which="account"
              form={@form}
              kinds={@account_kinds}
              example="e.g. Joint checking"
            />
          </.act_form>
        </.card_content>
      </.card>

      <.card>
        <.section_header
          title="Add a debt"
          description="A credit card, HELOC, loan, or anything else you owe. You'll add what's owed, the interest rate, and the minimum payment next."
        />
        <.card_content>
          <.act_form action="/act/add_debt" button="Add debt" class="max-w-md">
            <.balance_fields which="debt" form={@form} kinds={@debt_kinds} example="e.g. Visa card" />
          </.act_form>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  attr :which, :string, required: true
  attr :form, :map, required: true
  attr :kinds, :list, required: true
  attr :example, :string, required: true

  # UX-003 C6: the message goes under the field it's about: the name when it's empty, else the kind.
  defp balance_fields(assigns) do
    mine? = assigns.form[:which] == assigns.which

    bad =
      if mine? and assigns.form[:error] != nil,
        do: if(String.trim(assigns.form[:label] || "") == "", do: "label", else: "type")

    assigns =
      assign(assigns,
        bad: bad,
        label: if(mine?, do: assigns.form[:label], else: nil),
        type: if(mine?, do: assigns.form[:type], else: nil),
        error: assigns.form[:error]
      )

    ~H"""
    <div>
      <.field
        type="text"
        id={"#{@which}-label"}
        name="label"
        label="Name"
        value={@label}
        placeholder={@example}
        required
        aria-invalid={@bad == "label" && "true"}
        aria-describedby={@bad == "label" && "#{@which}-label-error"}
      />
      <.field_problem :if={@bad == "label"} id={"#{@which}-label-error"} message={@error} />
    </div>
    <div>
      <.field
        type="select"
        id={"#{@which}-type"}
        name="type"
        label="Kind"
        prompt="Choose…"
        options={@kinds}
        value={@type}
        required
        aria-invalid={@bad == "type" && "true"}
        aria-describedby={@bad == "type" && "#{@which}-type-error"}
      />
      <.field_problem :if={@bad == "type"} id={"#{@which}-type-error"} message={@error} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :message, :string, required: true

  defp field_problem(assigns) do
    ~H"""
    <p id={@id} class="pc-form-field-error -mt-3 mb-4" role="alert">{@message}</p>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared by the pages

  # A controller's assigns carry no change tracking, so a page adds what it works out by merging.
  defp page_assigns(assigns, more), do: Map.merge(assigns, Map.new(more))

  # A cash figure; below zero it carries REQ-173's mark, read as text after the figure.
  attr :cents, :integer, default: nil

  defp cash(%{cents: nil} = assigns), do: ~H""

  defp cash(%{cents: c} = assigns) when c < 0 do
    ~H"""
    <span class="below-zero whitespace-nowrap">
      {Words.plain_amount(@cents)} <.badge variant="soft" color="danger" label="Below zero" />
    </span>
    """
  end

  defp cash(assigns), do: ~H"{Words.plain_amount(@cents)}"

  defp date(%Date{} = d, today), do: Words.date_text(Date.to_iso8601(d), today)
  defp date(iso, today), do: Words.date_text(iso, today)

  defp account_titles(scope, ids), do: Enum.map(ids, &Words.title(Items.lookup(scope, &1)))

  # UX-002 R1a, UX-004 P2: on an account someone else also owns, the view is the member's part, and says
  # whose items it leaves out, by their names in the household.

  defp counted_note(scope, account_ids, name_of),
    do: Words.counted_note(scope.household, scope.member, account_ids, name_of)

  defp partial?(scope, account_ids),
    do: Words.partial?(scope.household, scope.member, account_ids)
end
