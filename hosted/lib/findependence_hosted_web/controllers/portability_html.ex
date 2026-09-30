defmodule FindependenceHostedWeb.PortabilityHTML do
  @moduledoc """
  The export page, bringing in a saved record (the page to choose a file, what was wrong with one, and the
  preview), and the leave checklist (WI-076), as the local form's pages say them (web/html.ex export_page,
  bring_in_page, bring_in_preview, leave_page). The words come from `FindependenceShared.PortabilityWords`
  and `Words`; members are named by their display names.
  """
  use FindependenceHostedWeb, :html

  alias FindependenceShared.{Balances, Households, Items, PortabilityWords, Words}

  @muted "text-sm text-gray-600 dark:text-gray-400"

  # a page's own assigns, next to the controller's (rendered by a controller, not tracked for changes)
  defp page_assigns(assigns, more), do: Map.merge(assigns, Map.new(more))

  # ---------------------------------------------------------------------------
  # The export (REQ-155, REQ-169; REQ-129 AC-6: how often, beside each amount)

  def export(assigns) do
    {balances, rest} =
      assigns.export.items
      |> Enum.sort_by(&String.downcase(Words.title(&1)))
      |> Enum.split_with(&Balances.balance?/1)

    {values, money} = Enum.split_with(rest, &(Map.get(&1.attrs, :kind) == :value))

    assigns =
      page_assigns(assigns,
        balances: balances,
        values: values,
        money: money,
        links: PortabilityWords.links(assigns.export.links, assigns.names),
        muted: @muted
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.h1>What you'd take with you</.h1>
      <.card>
        <.card_content class="space-y-3">
          <p class={@muted}>
            Everything you own, with its history, and your own links between them. Nothing that belongs to anyone else.
          </p>
          <.p :if={@export.items == []}>You don't own anything yet.</.p>
        </.card_content>
      </.card>

      <.card :if={@money != []} id="export-items">
        <.section_header title="Items" />
        <.card_content>
          <.owned_list items={@money} member={@export.member} name_of={@name_of} />
        </.card_content>
      </.card>

      <.card :if={@values != []} id="export-values">
        <.section_header title="What matters to you" />
        <.card_content>
          <.owned_list items={@values} member={@export.member} name_of={@name_of} />
        </.card_content>
      </.card>

      <.card :if={@balances != []} id="export-balances">
        <.section_header title="Balances and debts" />
        <.card_content>
          <ul class="space-y-2">
            <li :for={i <- @balances}>
              <b>{Words.title(i)}</b> {PortabilityWords.balance_summary(i, @today)}
            </li>
          </ul>
        </.card_content>
      </.card>

      <.card :if={@links != []} id="export-links">
        <.section_header title="Your links" />
        <.card_content>
          <ul class="space-y-1">
            <li :for={l <- @links}>{l}</li>
          </ul>
        </.card_content>
      </.card>

      <.p>
        <.link href="/export.json" download="findependence-export.json">Save as a file</.link>
        · <.link href={~p"/"}>Back</.link>
      </.p>
    </Layouts.app>
    """
  end

  attr :items, :list, required: true
  attr :member, :any, required: true
  attr :name_of, :any, required: true

  defp owned_list(assigns) do
    ~H"""
    <ul class="space-y-3">
      <li :for={i <- @items}>
        <b>{Words.display(i)}</b>{Words.amount_text(i.attrs)}. {PortabilityWords.owned_by(
          i,
          @member,
          @name_of
        )}
        {PortabilityWords.also_seen_by(i, @member, @name_of)}
        <details>
          <summary>History</summary>
          <ol class="list-decimal pl-6">
            <li :for={e <- i.ledger}>{Words.event_text(e, @name_of)}</li>
          </ol>
        </details>
      </li>
    </ul>
    """
  end

  # ---------------------------------------------------------------------------
  # Bringing in (CAP-009, REQ-156..159)

  @doc "The page to choose a saved export; `problem` is why the last file was refused."
  def bring_in(assigns) do
    assigns =
      page_assigns(assigns, muted: @muted, form_token: FindependenceHosted.Forms.new_token())

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.h1>Bring in your record</.h1>
      <.problem :if={@problem} problem={@problem} today={@today} />
      <.card>
        <.card_content class="space-y-4">
          <p class={@muted}>
            If you saved your record from another household (Leaving, then “Save as a file”), you can bring it in here. Everything in it becomes yours alone: nobody here can see any of it until you share it. You'll see what's in the file before anything is saved.
          </p>
          <%!-- the one form that sends a file (MEC-022); it carries its one-time token (REQ-165) --%>
          <.form
            for={%{}}
            action={~p"/act/bring-in"}
            method="post"
            multipart
            class="space-y-3"
          >
            <input type="hidden" name="_form" value={@form_token} />
            <div class="pc-form-field-wrapper">
              <label for="file" class="pc-label pc-label--required">Your saved file</label>
              <input
                type="file"
                id="file"
                name="file"
                accept=".json,application/json"
                required
                class="pc-text-input"
              />
            </div>
            <.button type="submit" size="sm" label="Check the file" />
          </.form>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  attr :problem, :any, required: true
  attr :today, :any, required: true

  defp problem(%{problem: {:problems, problems}} = assigns) do
    assigns = assign(assigns, lines: PortabilityWords.problem_lines(problems), muted: @muted)

    ~H"""
    <.card id="problems" role="alert">
      <.section_header title="Nothing was brought in" />
      <.card_content class="space-y-3">
        <.p>The file doesn't pass the checks, so none of it was brought in. What was wrong:</.p>
        <ul class="list-disc space-y-1 pl-6">
          <li :for={l <- @lines}>{l}</li>
        </ul>
        <p class={@muted}>
          A file saved by the app passes. If you changed it by hand, save a fresh copy from the other household.
        </p>
      </.card_content>
    </.card>
    """
  end

  defp problem(assigns) do
    ~H"""
    <.alert variant="soft" color="danger" role="alert">
      {PortabilityWords.problem_text(@problem, @today)}
    </.alert>
    """
  end

  @doc "REQ-158: what the file would bring in, to confirm or cancel; nothing is saved yet."
  def preview(assigns) do
    assigns =
      page_assigns(assigns,
        lines: PortabilityWords.preview_lines(assigns.summary),
        shared: PortabilityWords.shared_plans_text(assigns.summary),
        muted: @muted
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/bring-in"}>← Choose another file</.link></.p>
      <.h1>What would be brought in</.h1>
      <.card id="preview">
        <.card_content class="space-y-3">
          <.p>From <b>{@name}</b>, checked. Nothing is saved until you choose “Bring it in”.</.p>
          <.p :if={@lines == []}>The file has nothing to bring in.</.p>
          <ul :if={@lines != []} class="list-disc space-y-1 pl-6">
            <li :for={l <- @lines}>{l}</li>
          </ul>
          <p class={@muted}>
            All of it becomes yours alone. Its history, owners, and who it was shared with in the other household stay in your file. Goals and retirement assumptions you've already set here are kept.
          </p>
          <p :if={@shared} class={@muted}>{@shared}</p>
          <div class="flex flex-wrap gap-3">
            <.act_form action={~p"/act/bring-in/confirm"} button="Bring it in" />
            <.act_form action={~p"/act/bring-in/cancel"}>
              <.button type="submit" size="sm" variant="outline" label="Cancel" />
            </.act_form>
          </div>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # The leave checklist (UX-001 R8): everything needed to leave, on one page. The export comes first; each
  # item or value the member owns is listed with the one action it needs (a joint owner stops owning; a sole
  # owner gives it away or deletes it, chosen explicitly, REQ-166 AC-5); the leave button appears once nothing
  # is owned. The page states the consequences, so it is also the confirmation.

  def leave(assigns) do
    %{scope: scope, name_of: name_of} = assigns
    m = scope.member
    {owned, shared} = scope |> Items.visible() |> Enum.split_with(&(m in &1.owners))
    others = Households.members(scope) |> MapSet.delete(m) |> Enum.sort_by(name_of)
    pending = Items.pending(scope)

    rows =
      owned
      |> Enum.sort_by(&String.downcase(Words.title(&1)))
      |> Enum.map(&leave_row(&1, m, others, pending, name_of))

    assigns =
      page_assigns(assigns,
        rows: rows,
        shared_text: PortabilityWords.shared_text(length(shared)),
        muted: @muted
      )

    ~H"""
    <Layouts.app flash={@flash} current={@current} waiting={@waiting}>
      <.p><.link href={~p"/"}>← Everything</.link></.p>
      <.h1>Leave the household</.h1>
      <.alert :if={@message} variant="soft" color="danger" role="alert">{@message}</.alert>
      <p class={@muted}>
        Everything you own needs someone to own it, or to be deleted, before you go. Nothing here happens until you press a button.
      </p>

      <.card id="save-a-copy">
        <.section_header title="1. Save a copy" />
        <.card_content>
          <.p>
            <.link href={~p"/export"}>See everything you'd take with you</.link>, and save it as a file.
          </.p>
        </.card_content>
      </.card>

      <.card id="what-you-own">
        <.section_header title={"2. What you own (#{length(@rows)})"} />
        <.card_content>
          <.p :if={@rows == []}>You don't own anything now.</.p>
          <ul :if={@rows != []} class="space-y-4">
            <li :for={r <- @rows} class="space-y-2">
              <.link href={"/items/#{r.id}"}><b>{r.display}</b></.link>
              <.leave_action row={r} />
            </li>
          </ul>
        </.card_content>
      </.card>

      <.card id="leave">
        <.section_header title="3. Leave" />
        <.card_content class="space-y-3">
          <%= if @rows == [] do %>
            <.p>
              {@shared_text}Your links and your passphrase stop working here. This can't be undone.
            </.p>
            <%!-- a household-changing form: it carries its one-time token (REQ-165) --%>
            <.act_form
              action={~p"/leave"}
              return="/leave"
              button="Leave the household"
              danger
            />
          <% else %>
            <p class={@muted}>You can leave once you don't own anything.</p>
          <% end %>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # What one owned item needs before the member can leave, as the local form's leave_action decides it.
  defp leave_row(i, m, others, pending, name_of) do
    keepers = Enum.reject(i.owners, &(&1 == m))
    mine = Enum.filter(pending, &(&1.item_id == i.id and m in &1.consents))
    base = %{id: i.id, title: Words.title(i), display: Words.display(i)}

    cond do
      mine != [] ->
        Map.merge(base, %{
          action: :withdraw,
          hint: PortabilityWords.waiting_text(i, mine, m, name_of),
          proposals: Enum.map(mine, & &1.id)
        })

      keepers != [] ->
        Map.merge(base, %{
          action: :relinquish,
          hint: PortabilityWords.owned_with_text(keepers, name_of)
        })

      true ->
        options =
          Enum.map(others, &{PortabilityWords.give_label(i, name_of.(&1)), "give:#{&1}"}) ++
            [{"Delete it for everyone (can't be undone)", "delete"}]

        Map.merge(base, %{action: :let_go, options: options})
    end
  end

  attr :row, :map, required: true

  defp leave_action(%{row: %{action: :withdraw}} = assigns) do
    assigns = assign(assigns, muted: @muted)

    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <span class={@muted}>{@row.hint}</span>
      <.act_form
        :for={p <- @row.proposals}
        action={~p"/act/withdraw"}
        return="/leave"
        fields={[{"proposal", p}]}
        button="Withdraw"
        aria={"Withdraw the request for #{@row.title}"}
      />
    </div>
    """
  end

  defp leave_action(%{row: %{action: :relinquish}} = assigns) do
    assigns = assign(assigns, muted: @muted)

    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <span class={@muted}>{@row.hint}</span>
      <.act_form
        action={~p"/act/relinquish"}
        return="/leave"
        fields={[{"item", @row.id}]}
        button="Stop owning"
        aria={"Stop owning #{@row.title}"}
        danger
      />
    </div>
    """
  end

  defp leave_action(assigns) do
    ~H"""
    <.act_form
      action={~p"/act/let_go"}
      return="/leave"
      fields={[{"item", @row.id}]}
      class="flex flex-wrap items-end gap-3"
    >
      <.field
        type="select"
        id={"to-#{@row.id}"}
        name="to"
        label={"What happens to “#{@row.title}”"}
        prompt="Choose…"
        options={@row.options}
        required
        no_margin
      />
      <.button type="submit" size="sm" label="Do this" />
    </.act_form>
    """
  end
end
