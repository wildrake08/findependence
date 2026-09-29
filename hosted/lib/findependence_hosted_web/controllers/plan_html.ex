defmodule FindependenceHostedWeb.PlanHTML do
  @moduledoc """
  Plans and plan requests (REQ-142, REQ-143, REQ-148, REQ-166; WI-076): the member's plans and the shared
  plans they can see, one plan with its steps and the twelve months with and without it, the forms that add a
  step, ask others to share it, and delete it, a plan request's preview, and the confirmation for deleting a
  plan. The wording is the local form's (web/html.ex), from `FindependenceShared.PlanWords` and
  `FindependenceShared.Words`; members are named by their display names.

  `plan_steps/1` and `comparison/1` are public, for a shared plan's page (the local form's shared_plan_page).
  """
  use FindependenceHostedWeb, :html

  alias FindependenceShared.{CashFlow, Households, Items, Planning, PlanWords, Words}

  @plans_hint "A plan is a “what if”: switch off an income or a bill from a month, add a planned cost or income, or borrow. Plans are kept apart from what's real and never change your totals. Only you can see your plans unless you ask others to share one."

  # ---------------------------------------------------------------------------
  # REQ-142: the member's plans, and shared plans they own or are asked to join

  def index(assigns) do
    scope = assigns.scope

    assigns =
      page_assigns(assigns,
        hint: @plans_hint,
        mine:
          Planning.plans(scope)
          |> Enum.sort_by(fn {_, p} -> String.downcase(p.name) end),
        shared:
          Items.visible(scope)
          |> Enum.filter(&Planning.plan?/1)
          |> Enum.sort_by(&String.downcase(Words.title(&1)))
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.page_message message={@message} />
      <.h1>Plans</.h1>

      <.card>
        <.card_content class="space-y-4">
          <.p class="text-sm">{@hint}</.p>
          <.p :if={@mine == []}>No plans yet.</.p>
          <ul :if={@mine != []} id="plans" class="space-y-2">
            <li :for={{id, p} <- @mine}>
              <.link href={"/plans/" <> id}><b>{p.name}</b></.link>
              <span class="text-sm text-gray-600 dark:text-gray-400">{PlanWords.plan_entry(p)}</span>
            </li>
          </ul>
          <.act_form action="/act/new_plan" class="flex flex-wrap items-end gap-3">
            <.field
              type="text"
              id="plan-name"
              name="name"
              label="New plan"
              value=""
              placeholder="e.g. If Dad's job stops"
              required
              no_margin
            />
            <.button type="submit" size="sm" label="Start plan" />
          </.act_form>
        </.card_content>
      </.card>

      <.card :if={@shared != []}>
        <.section_header title="Shared plans" />
        <.card_content>
          <ul id="shared-plans" class="space-y-2">
            <li :for={i <- @shared}>
              <.link href={"/items/" <> i.id}><b>{Words.title(i)}</b></.link>
              <span class="text-sm text-gray-600 dark:text-gray-400">
                {PlanWords.shared_plan_entry(i.owners, @scope.member, @name_of)}
              </span>
            </li>
          </ul>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # REQ-142, REQ-143, REQ-148: one of the member's plans

  def show(assigns) do
    %{scope: scope, name_of: name_of} = assigns
    m = scope.member

    assigns =
      page_assigns(assigns,
        owned:
          Items.visible(scope)
          |> Enum.filter(&(m in &1.owners and Items.money?(&1)))
          |> Enum.sort_by(&String.downcase(Words.title(&1))),
        others:
          Households.members(scope)
          |> MapSet.delete(m)
          |> Enum.sort_by(name_of)
          |> Enum.map(&{&1, name_of.(&1)}),
        months: month_options(assigns.today),
        frequencies: Words.frequency_choices() |> Enum.map(fn {v, t} -> {t, v} end),
        fields: [{"plan", assigns.id}]
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/plans"}>← Plans</.link></.p>
      <.page_message message={@message} />
      <.h1>{@plan.name}</.h1>

      <.card>
        <.card_content class="space-y-4">
          <.p class="text-sm">A plan, private to you. It never changes your real totals.</.p>
          <.p :if={@plan.steps == []}>No steps yet. Add one below.</.p>
          <.plan_steps :if={@plan.steps != []} scope={@scope} steps={@plan.steps} plan={@id} />
        </.card_content>
      </.card>

      <.comparison scope={@scope} steps={@plan.steps} today={@today} />

      <.card>
        <.section_header title="Add a step" />
        <.card_content class="space-y-6">
          <.act_form
            action="/act/plan_step"
            fields={@fields ++ [{"kind", "switch_off"}]}
            id="step-switch"
          >
            <h3 class="text-base font-semibold">Switch items off</h3>
            <fieldset class="pc-form-field-wrapper">
              <legend class="pc-label">Which items?</legend>
              <.p :if={@owned == []}>You don't own any items yet.</.p>
              <div :if={@owned != []} class="flex flex-wrap gap-4">
                <label :for={i <- @owned} class="pc-checkbox-label">
                  <input type="checkbox" name="items[]" value={i.id} class="pc-checkbox" />
                  <span class="pc-checkbox-text">{Words.title(i)}</span>
                </label>
              </div>
            </fieldset>
            <.p class="text-sm">
              Anything you've marked as depending on a job switches off with it.
            </.p>
            <.field type="select" id="switch-from" name="from" label="From" options={@months} />
            <.button type="submit" size="sm" label="Add switching off" />
          </.act_form>

          <.act_form action="/act/plan_step" fields={@fields ++ [{"kind", "add"}]} id="step-add">
            <h3 class="text-base font-semibold">Add planned money in or out</h3>
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.field
                type="text"
                id="add-note"
                name="note"
                label="Planned item"
                value=""
                placeholder="e.g. Marketplace health premium"
              />
              <.field
                type="text"
                id="add-amount"
                name="amount"
                label="Amount"
                value=""
                inputmode="decimal"
                autocomplete="off"
                placeholder="e.g. 600"
              />
              <.field
                type="select"
                id="add-frequency"
                name="frequency"
                label="How often?"
                prompt="Choose…"
                options={@frequencies}
              />
              <.field type="select" id="add-from" name="from" label="From" options={@months} />
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
                    checked={value == "out"}
                    class="pc-radio"
                  />
                  <span>{words}</span>
                </label>
              </div>
            </fieldset>
            <.button type="submit" size="sm" label="Add planned item" />
          </.act_form>

          <.act_form action="/act/plan_step" fields={@fields ++ [{"kind", "borrow"}]} id="step-borrow">
            <h3 class="text-base font-semibold">Borrow</h3>
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.field
                type="text"
                id="borrow-amount"
                name="amount"
                label="Amount to borrow"
                value=""
                inputmode="decimal"
                autocomplete="off"
                placeholder="e.g. 5,000"
              />
              <.field
                type="text"
                id="borrow-rate"
                name="rate"
                label="Interest rate (%)"
                value=""
                inputmode="decimal"
                autocomplete="off"
                placeholder="e.g. 9"
              />
              <.field
                type="text"
                id="borrow-payment"
                name="payment"
                label="Monthly payment"
                value=""
                inputmode="decimal"
                autocomplete="off"
                placeholder="e.g. 200"
              />
              <.field type="select" id="borrow-from" name="from" label="From" options={@months} />
            </div>
            <.button type="submit" size="sm" label="Add borrowing" />
          </.act_form>
        </.card_content>
      </.card>

      <.card>
        <.section_header
          title="Ask others to share it"
          description="They'll see this plan as a request and share it only if they agree. What they see is worked out from their own items. Your plan here stays yours."
        />
        <.card_content>
          <.act_form action="/act/share_plan" fields={@fields} id="share-plan">
            <fieldset class="pc-form-field-wrapper">
              <legend class="pc-label">Ask</legend>
              <div class="flex flex-wrap gap-4">
                <label :for={{o, name} <- @others} class="pc-checkbox-label">
                  <input type="checkbox" name="members[]" value={o} class="pc-checkbox" />
                  <span class="pc-checkbox-text">{name}</span>
                </label>
              </div>
            </fieldset>
            <.button type="submit" size="sm" label="Send request" />
          </.act_form>
        </.card_content>
      </.card>

      <.card>
        <.section_header title="Delete this plan" />
        <.card_content>
          <.act_form
            action="/confirm/delete_plan"
            fields={@fields}
            button="Delete plan…"
            aria={"Delete the plan #{@plan.name}"}
            danger
          />
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # REQ-148: a plan someone asks this member to share, before they agree

  def request(assigns) do
    p = assigns.request

    assigns =
      page_assigns(assigns,
        name: p.attrs[:label] || "",
        steps: Map.get(p.attrs, :steps, []),
        agreed?: assigns.scope.member in p.consents
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.h1>{@name}</.h1>

      <.card>
        <.card_content class="space-y-4">
          <.p class="text-sm">
            {PlanWords.request_note(@request.consents, @scope.member, @name_of)}
          </.p>
          <.plan_steps scope={@scope} steps={@steps} />
        </.card_content>
      </.card>

      <.comparison scope={@scope} steps={@steps} today={@today} />

      <.card>
        <.card_content>
          <.p :if={@agreed?} class="text-sm">You've agreed. Waiting for the others.</.p>
          <.act_form
            :if={!@agreed?}
            action="/act/consent"
            return="/plans"
            fields={[{"proposal", to_string(@request.id)}]}
            button="Agree to share it"
          />
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # REQ-166: deleting a plan is shown by name, with how many steps go with it, and asked first

  def confirm(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.h1>{@heading}</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.p>{@body}</.p>
          <.act_form
            action="/act/delete_plan"
            return="/plans"
            fields={[{"plan", @id}]}
            button={@yes}
            danger
          />
          <.p><.link href={"/plans/" <> URI.encode_www_form(@id)}>No, go back</.link></.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  def not_found(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.h1>Not available</.h1>
      <.card>
        <.card_content class="space-y-3">
          <%= if @what == :plan do %>
            <.p>That plan isn't available to you.</.p>
            <.p><.link href={~p"/plans"}>Back to plans</.link></.p>
          <% else %>
            <.p>
              That request isn't waiting for you. It may have been withdrawn or already agreed.
            </.p>
            <.p><.link href={~p"/"}>Back to everything</.link></.p>
          <% end %>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # A plan's steps and its comparison (also for a shared plan's page)

  @doc """
  A plan's steps in words, as the member sees them; with `plan`, each has a Remove button that posts straight
  to the removal (REQ-166 AC-6) and returns to the plan's page.
  """
  attr :scope, :any, required: true
  attr :steps, :list, required: true
  attr :plan, :string, default: nil

  def plan_steps(assigns) do
    ~H"""
    <ol id="steps" class="list-decimal space-y-2 pl-6">
      <li :for={%{n: n, step: st} <- @steps}>
        <div class="flex flex-wrap items-center gap-3">
          <span>{PlanWords.step_text(@scope.household, @scope.member, st)}</span>
          <.act_form
            :if={@plan}
            action="/act/remove_step"
            return={"/plans/" <> @plan}
            fields={[{"plan", @plan}, {"n", to_string(n)}]}
            button="Remove"
            aria={"Remove step #{n}"}
          />
        </div>
      </li>
    </ol>
    """
  end

  @doc """
  REQ-143: the twelve months as things are and with the plan's `steps`, side by side, worked out from the
  member's own items, with the interest on anything borrowed.
  """
  attr :scope, :any, required: true
  attr :steps, :list, required: true
  attr :today, Date, required: true

  def comparison(assigns) do
    base = CashFlow.project(assigns.scope, assigns.today)
    with_plan = CashFlow.project(assigns.scope, assigns.today, %{steps: assigns.steps})

    assigns =
      assign(assigns,
        summary: PlanWords.plan_summary_parts(base, with_plan),
        note: PlanWords.comparison_note(base),
        rows: Enum.zip(base.months, with_plan.months),
        interest: PlanWords.borrowing_interest(Enum.filter(with_plan.debts, & &1.planned))
      )

    ~H"""
    <.card>
      <.section_header title="With and without this plan" />
      <.card_content class="space-y-4">
        <.p :if={@summary} id="plan-summary">{summary_html(@summary)}</.p>
        <.p class="text-sm">{@note}</.p>
        <details>
          <summary class="cursor-pointer">Month by month</summary>
          <div class="overflow-x-auto" tabindex="0" role="region" aria-label="With this plan">
            <table class="pc-table--basic w-full" aria-label="With this plan" id="comparison">
              <thead>
                <.tr>
                  <th scope="col" class="pc-table__th">Month</th>
                  <th scope="col" class="pc-table__th text-right">Without this plan</th>
                  <th scope="col" class="pc-table__th text-right">With this plan</th>
                  <th scope="col" class="pc-table__th text-right">Difference</th>
                </.tr>
              </thead>
              <tbody>
                <.tr :for={{a, b} <- @rows}>
                  <th scope="row" class="pc-table__td text-left font-semibold">
                    {Words.month_text(a.month)}
                  </th>
                  <.td class="text-right whitespace-nowrap"><.figure row={a} /></.td>
                  <.td class="text-right whitespace-nowrap"><.figure row={b} /></.td>
                  <.td class="text-right whitespace-nowrap">{PlanWords.difference(a, b)}</.td>
                </.tr>
              </tbody>
            </table>
          </div>
        </details>
        <.p :if={@interest} id="plan-interest">{@interest}</.p>
      </.card_content>
    </.card>
    """
  end

  # A month's figure: cash at its end, below zero with REQ-173's mark; or net money in and out without cash.
  attr :row, :map, required: true

  defp figure(%{row: %{cash: c}} = assigns) when is_integer(c) and c < 0 do
    ~H"""
    <span class="below-zero whitespace-nowrap">
      {Words.plain_amount(@row.cash)} <.badge variant="soft" color="danger" label="Below zero" />
    </span>
    """
  end

  defp figure(%{row: %{cash: c}} = assigns) when is_integer(c),
    do: ~H"{Words.plain_amount(@row.cash)}"

  defp figure(assigns), do: ~H"{Words.format_amount(@row.net)}"

  # ---------------------------------------------------------------------------
  # Shared by the pages

  attr :message, :any, required: true

  defp page_message(%{message: {:error, text}} = assigns) do
    assigns = assign(assigns, :text, text)
    ~H|<.alert variant="soft" color="danger" role="alert" label={@text} />|
  end

  defp page_message(assigns), do: ~H""

  # UX-002 R5: the comparison's answer, each amount kept from splitting between its sign and its digits.
  defp summary_html(parts) do
    parts
    |> Enum.map(fn
      {:amount, cents} ->
        [~s(<span class="whitespace-nowrap">), escaped(Words.plain_amount(cents)), "</span>"]

      text ->
        escaped(text)
    end)
    |> raw()
  end

  defp escaped(text), do: text |> html_escape() |> safe_to_string()

  # The twelve months a step can start from, as {label, value}.
  defp month_options(today), do: Enum.map(CashFlow.months(today), &{Words.month_text(&1), &1})

  # A controller's assigns carry no change tracking, so a page adds what it works out by merging.
  defp page_assigns(assigns, more), do: Map.merge(assigns, Map.new(more))
end
