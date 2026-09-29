defmodule FindependenceHostedWeb.GoalsHTML do
  @moduledoc """
  Goals and set-asides, and retirement (WI-076): what the local form's pages say (web/html.ex goals_page and
  retirement_page), in the same words (FindependenceShared.Words and GoalWords).
  """
  use FindependenceHostedWeb, :html

  alias FindependenceShared.{Balances, GoalWords, Items, Planning, Values, Words}

  # ---------------------------------------------------------------------------
  # REQ-146, REQ-147: goals

  def index(assigns) do
    scope = assigns.scope

    values =
      Items.visible(scope)
      |> Enum.filter(&Values.value?/1)
      |> Enum.sort_by(&String.downcase(Words.title(&1)))

    asides =
      for a <- Planning.set_asides(scope) do
        title = Words.title(Items.lookup(scope, a.value_id))

        %{
          id: a.value_id,
          line: GoalWords.set_aside_line(a, title),
          aria: GoalWords.remove_set_aside(title)
        }
      end

    assigns =
      page_assigns(assigns,
        cover: Planning.cover(scope),
        goal: Planning.goals(scope).fund_months,
        asides: asides,
        values: Enum.map(values, &{Words.title(&1), &1.id})
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.page_message message={@message} />
      <.h1>Goals</.h1>

      <.card id="cover">
        <.section_header title="How long savings would last" />
        <.card_content class="space-y-4">
          <.p :if={@cover.months == nil} class="text-sm">
            To see how long savings would last,
            <.link href={~p"/balances/new"}>add a savings account</.link>
            and its balance.
          </.p>
          <div :if={@cover.months != nil} class="space-y-2">
            <p class="text-2xl font-semibold">{GoalWords.cover_months(@cover.months)}</p>
            <.p class="text-sm">{GoalWords.cover_note(@cover)}</.p>
            <.p :if={@goal} id="goal">{GoalWords.goal_progress(@goal, @cover.months)}</.p>
          </div>
          <.act_form action="/act/fund_goal" class="flex flex-wrap items-end gap-3">
            <.typed_field
              id="fund-months"
              name="months"
              label="Emergency fund goal, in months of money out"
              value={GoalWords.int_field(@goal)}
              inputmode="numeric"
              autocomplete="off"
            />
            <.button type="submit" size="sm" label="Save goal" />
          </.act_form>
          <.p class="text-sm">
            The goal is yours; nothing here suggests one. Leave it empty and save to clear it.
          </.p>
        </.card_content>
      </.card>

      <.card id="set-aside">
        <.section_header
          title="Setting aside from income"
          description="For money in linked to one of your values, such as a side business, choose a rate to set aside, for example for taxes. The rate is yours; this isn't tax advice."
        />
        <.card_content class="space-y-4">
          <ul :if={@asides != []} class="space-y-2" id="set-asides">
            <li :for={a <- @asides} class="flex flex-wrap items-center gap-2">
              <span>{a.line}</span>
              <.act_form
                action="/act/set_aside"
                fields={[{"value", a.id}, {"rate", ""}]}
                button="Remove"
                aria={a.aria}
              />
            </li>
          </ul>
          <.p :if={@values == []} class="text-sm">
            Add a value, and link income to it, to set a rate here.
          </.p>
          <.act_form
            :if={@values != []}
            action="/act/set_aside"
            class="flex flex-wrap items-end gap-3"
          >
            <.field
              type="select"
              id="aside-value"
              name="value"
              label="For money in linked to"
              options={@values}
              no_margin
            />
            <.typed_field
              id="aside-rate"
              name="rate"
              label="Rate (%)"
              inputmode="decimal"
              autocomplete="off"
              placeholder="e.g. 25"
            />
            <.button type="submit" size="sm" label="Save rate" />
          </.act_form>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # REQ-150..154, REQ-174: retirement

  def retirement(assigns) do
    scope = assigns.scope
    today = assigns.today

    accounts =
      Items.visible(scope)
      |> Enum.filter(&Balances.retirement?/1)
      |> Enum.sort_by(&String.downcase(Words.title(&1)))

    projection =
      case Planning.retirement_projection(scope, today) do
        {:missing, _} -> nil
        p -> p
      end

    sensitivity =
      case Planning.retirement_sensitivity(scope, today) do
        {:missing, _} -> []
        list -> list
      end

    starts =
      for i <- accounts,
          do: GoalWords.starting_balance(Words.title(i), Balances.latest(scope, i.id), today)

    assigns =
      page_assigns(assigns,
        p: projection,
        starts: if(starts == [], do: nil, else: Words.people(starts)),
        sensitivity: sensitivity,
        settings: Planning.retirement_settings(scope),
        accounts: accounts,
        errors: assigns.form[:errors] || %{},
        values: assigns.form[:values] || %{}
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.alert :if={@errors != %{}} variant="soft" color="danger">
        Nothing was saved.
        <.link href="#assumptions">Check the fields marked in your assumptions.</.link>
      </.alert>
      <.page_message :if={@errors == %{}} message={@message} />
      <.h1>Retirement</.h1>

      <.card id="result">
        <.card_content class="space-y-4">
          <.p class="text-sm">
            Worked out in today's dollars from assumptions you set. Only you see them, and nothing here is advice or a suggestion.
          </.p>
          <.p :if={@p == nil} class="text-sm">
            To see a projection, enter your birth year, a retirement age, and a yearly return below.
          </.p>
          <.retirement_result :if={@p} p={@p} starts={@starts} today={@today} />
        </.card_content>
      </.card>

      <.card :if={@sensitivity != []} id="sensitivity">
        <.section_header
          title="What changes the result"
          description="The same projection with one assumption changed at a time. Nothing here is saved."
        />
        <.card_content>
          <div class="overflow-x-auto" tabindex="0" role="region" aria-label="What changes the result">
            <table
              class="pc-table--basic w-full"
              aria-label="What changes the result"
              id="alternatives"
            >
              <thead>
                <.tr>
                  <th scope="col" class="pc-table__th">If</th>
                  <th scope="col" class="pc-table__th text-right">Return</th>
                  <th scope="col" class="pc-table__th text-right">Retiring at</th>
                  <th scope="col" class="pc-table__th text-right">At retirement</th>
                  <th scope="col" class="pc-table__th">Paying the difference</th>
                </.tr>
              </thead>
              <tbody>
                <.tr :for={r <- @sensitivity}>
                  <th scope="row" class="pc-table__td text-left font-semibold">
                    {GoalWords.change_label(r.change)}
                  </th>
                  <.td class="text-right whitespace-nowrap">{GoalWords.pct_text(r.return_bp)}</.td>
                  <.td class="text-right">{r.retire_age}</.td>
                  <.td class="text-right whitespace-nowrap">{GoalWords.about(r.at_retirement)}</.td>
                  <.td>{GoalWords.lasts_short(r)}</.td>
                </.tr>
              </tbody>
            </table>
          </div>
        </.card_content>
      </.card>

      <.retirement_form
        settings={@settings}
        accounts={@accounts}
        errors={@errors}
        values={@values}
      />
    </Layouts.app>
    """
  end

  attr :p, :map, required: true
  attr :starts, :string, default: nil
  attr :today, Date, required: true

  defp retirement_result(assigns) do
    ~H"""
    <div class="space-y-4">
      <.p>{GoalWords.retirement_when(@p, @today)}:</.p>
      <p class="text-2xl font-semibold" id="at-retirement">{GoalWords.about(@p.at_retirement)}</p>
      <.p :if={@p.gap == nil} class="text-sm">Enter a target income below to compare with it.</.p>
      <.p :if={@p.gap != nil} id="lasts">{GoalWords.lasts_sentence(@p)}</.p>
      <details :if={@p.rows != []}>
        <summary>{GoalWords.year_by_year(length(@p.rows))}</summary>
        <div
          class="overflow-x-auto"
          tabindex="0"
          role="region"
          aria-label="Retirement accounts year by year"
        >
          <table
            class="pc-table--basic w-full"
            aria-label="Retirement accounts year by year"
            id="years"
          >
            <thead>
              <.tr>
                <th scope="col" class="pc-table__th">Year</th>
                <th scope="col" class="pc-table__th text-right">Age</th>
                <th scope="col" class="pc-table__th text-right">Added</th>
                <th scope="col" class="pc-table__th text-right">Growth</th>
                <th scope="col" class="pc-table__th text-right">Balance at the end</th>
              </.tr>
            </thead>
            <tbody>
              <.tr :for={r <- @p.rows}>
                <th scope="row" class="pc-table__td text-left font-semibold">{r.year}</th>
                <.td class="text-right">{r.age}</.td>
                <.td class="text-right whitespace-nowrap">{Words.plain_amount(r.contributed)}</.td>
                <.td class="text-right whitespace-nowrap">{GoalWords.about_signed(r.growth)}</.td>
                <.td class="text-right whitespace-nowrap">{GoalWords.about(r.balance)}</.td>
              </.tr>
            </tbody>
          </table>
        </div>
      </details>
      <.p :if={@starts} class="text-sm" id="worked-out">
        How this is worked out: starting from {@starts}; {GoalWords.worked_out(@p)}
      </.p>
      <.p :if={!@starts} class="text-sm" id="worked-out">
        How this is worked out: starting from no retirement account yet:
        <.link href={~p"/balances/new"}>add one</.link>
        as a 401(k) or an IRA; {GoalWords.worked_out(@p)}
      </.p>
    </div>
    """
  end

  attr :settings, :map, required: true
  attr :accounts, :list, required: true
  attr :errors, :map, required: true
  attr :values, :map, required: true

  # REQ-150, REQ-154 AC-1: every field starts as the member left it (empty until they set it), with no
  # placeholder, list, select, or datalist; after a refused save, what was typed is shown again.
  defp retirement_form(assigns) do
    s = assigns.settings

    shown = fn name, current ->
      if Map.has_key?(assigns.values, name), do: assigns.values[name], else: current
    end

    contributions =
      for i <- assigns.accounts do
        name = "contribution_" <> i.id

        %{
          name: name,
          label: GoalWords.contribution_label(Words.title(i)),
          value: shown.(name, GoalWords.money_field(s.contributions[i.id]))
        }
      end

    assigns =
      page_assigns(assigns,
        contributions: contributions,
        birth_year: shown.("birth_year", GoalWords.int_field(s.birth_year)),
        retire_age: shown.("retire_age", GoalWords.int_field(s.retire_age)),
        return: shown.("return", GoalWords.return_field(s.return_bp)),
        ss: shown.("ss", GoalWords.money_field(s.ss_monthly)),
        target: shown.("target", GoalWords.money_field(s.target_monthly))
      )

    ~H"""
    <.card id="assumptions">
      <.section_header
        title="Your assumptions"
        description="All yours to set; none is filled in for you. Leave a field empty and save to clear it. Amounts are a month, in today's dollars."
      />
      <.card_content>
        <.act_form action="/act/retirement" class="max-w-md">
          <p :if={@errors != %{}} class="pc-form-field-error mb-4">
            Nothing was saved. Check the fields marked below.
          </p>
          <.typed_field
            id="birth_year"
            label="Year you were born"
            value={@birth_year}
            error={@errors["birth_year"]}
            inputmode="numeric"
            autocomplete="off"
          />
          <.typed_field
            id="retire_age"
            label="Retirement age"
            value={@retire_age}
            error={@errors["retire_age"]}
            inputmode="numeric"
            autocomplete="off"
          />
          <.typed_field
            id="return"
            label="Yearly return after inflation (%)"
            value={@return}
            error={@errors["return"]}
            inputmode="decimal"
            autocomplete="off"
          />
          <.p :if={@contributions == []} class="text-sm mb-4">
            Contributions go with a retirement account.
            <.link href={~p"/balances/new"}>Add one</.link>
            as a 401(k) or an IRA.
          </.p>
          <.typed_field
            :for={c <- @contributions}
            id={c.name}
            label={c.label}
            value={c.value}
            error={@errors[c.name]}
            inputmode="decimal"
            autocomplete="off"
          />
          <.typed_field
            id="ss"
            label="Social Security estimate, a month"
            value={@ss}
            error={@errors["ss"]}
            hint="From your own Social Security statement, in today's dollars."
            inputmode="decimal"
            autocomplete="off"
          />
          <.typed_field
            id="target"
            label="Target income in retirement, a month"
            value={@target}
            error={@errors["target"]}
            inputmode="decimal"
            autocomplete="off"
          />
          <.button type="submit" size="sm" label="Save assumptions" />
        </.act_form>
      </.card_content>
    </.card>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared by the pages

  # A controller's assigns carry no change tracking, so a page adds what it works out by merging.
  defp page_assigns(assigns, more), do: Map.merge(assigns, Map.new(more))

  attr :message, :any, required: true

  defp page_message(%{message: {:error, text}} = assigns) do
    assigns = assign(assigns, :text, text)
    ~H|<.alert variant="soft" color="danger" label={@text} />|
  end

  defp page_message(assigns), do: ~H""

  # A labelled text field with its error directly under it (UX-003 C6) and an optional hint.
  attr :id, :string, required: true
  attr :name, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :error, :any, default: nil
  attr :hint, :string, default: nil
  attr :rest, :global, include: ~w(placeholder autocomplete inputmode)

  defp typed_field(assigns) do
    ~H"""
    <div class={["pc-form-field-wrapper", @error && "pc-form-field-wrapper--error"]}>
      <.field_label for={@id}>{@label}</.field_label>
      <input
        id={@id}
        name={@name || @id}
        type="text"
        value={@value || ""}
        class="pc-text-input"
        aria-invalid={@error && "true"}
        aria-describedby={
          [@error && "#{@id}-error", @hint && "#{@id}-hint"]
          |> Enum.filter(& &1)
          |> Enum.join(" ")
          |> then(&if(&1 == "", do: nil, else: &1))
        }
        {@rest}
      />
      <p :if={@error} id={"#{@id}-error"} class="pc-form-field-error" role="alert">{@error}</p>
      <p :if={@hint} id={"#{@id}-hint"} class="pc-form-help-text">{@hint}</p>
    </div>
    """
  end
end
