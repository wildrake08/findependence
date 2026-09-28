defmodule FindependenceHostedWeb.SpecimenLive do
  @moduledoc """
  A design specimen for the hosted edition (WI-063): the Petal primitives the product will use,
  themed from DIR-001, in the device's light or dark setting. It is not a product feature and
  keeps nothing: the form is checked on the server and then discarded. The rows are made up.
  """
  use FindependenceHostedWeb, :live_view

  @sample_rows [
    %{id: 1, name: "Rent", how_often: "Monthly", amount: "−$1,450.00"},
    %{id: 2, name: "Paycheck", how_often: "Every two weeks", amount: "$2,180.00"},
    %{id: 3, name: "Car insurance", how_often: "Every six months", amount: "−$612.00"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Design specimen", rows: @sample_rows, checked: nil)
     |> assign_form(%{"name" => "", "how_often" => "monthly", "note" => ""})}
  end

  @impl true
  def handle_event("validate", %{"sample" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("check", %{"sample" => params}, socket) do
    socket = assign_form(socket, params)

    checked =
      if socket.assigns.form.errors == [],
        do: "That entry passes the checks. Nothing was saved: this page keeps nothing."

    {:noreply, assign(socket, checked: checked)}
  end

  # Only these fields are read; anything else in the event is ignored (ARCH-001 3.7).
  defp assign_form(socket, params) do
    params = Map.take(params, ["name", "how_often", "note"])
    assign(socket, form: to_form(params, as: :sample, errors: errors(params)))
  end

  defp errors(params) do
    name = String.trim(params["name"] || "")

    cond do
      name == "" -> [name: {"Give it a name.", []}]
      String.length(name) > 200 -> [name: {"Keep the name to 200 characters or fewer.", []}]
      true -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-2">
        <.h1 no_margin>Design specimen</.h1>
        <.p class="max-w-2xl text-gray-600 dark:text-gray-300">
          The building blocks of the hosted edition, in DIR-001's colours and type. This page is for
          checking the design; it isn't part of the service and keeps nothing you enter.
        </.p>
      </div>

      <.card>
        <.card_header
          title="Buttons"
          description="One accent colour; red only for actions that remove something."
        />
        <.card_content>
          <div class="flex flex-wrap gap-3">
            <.button label="Save" />
            <.button variant="outline" label="Cancel" />
            <.button variant="ghost" label="More options" />
            <.button color="danger" variant="outline" label="Delete" />
            <.button disabled label="Unavailable" />
          </div>
        </.card_content>
      </.card>

      <.card>
        <.card_header
          title="Messages"
          description="What happened, in words; colour is never the only signal."
        />
        <.card_content class="space-y-3">
          <.alert color="info" with_icon label="Your changes are saved as you go." />
          <.alert color="success" with_icon label="Paycheck added." />
          <.alert color="warning" with_icon label="This plan runs short in March." />
          <.alert color="danger" with_icon label="That wasn't saved. Check the name and try again." />
          <div class="flex flex-wrap gap-2">
            <.badge color="info" label="Shared" />
            <.badge color="success" label="On track" />
            <.badge color="warning" label="Needs a look" />
            <.badge color="danger" label="Overdue" />
          </div>
        </.card_content>
      </.card>

      <.card>
        <.card_header title="Form" description="Checked on the server as you type; nothing is kept." />
        <.card_content>
          <.form
            for={@form}
            id="sample-form"
            phx-change="validate"
            phx-submit="check"
            class="max-w-md"
          >
            <.field field={@form[:name]} label="Name" required help_text="1 to 200 characters." />
            <.field
              field={@form[:how_often]}
              type="select"
              label="How often"
              options={[
                {"Monthly", "monthly"},
                {"Every two weeks", "biweekly"},
                {"Once a year", "yearly"}
              ]}
            />
            <.field field={@form[:note]} type="textarea" label="Note (optional)" rows="3" />
            <.button type="submit" label="Check it" />
          </.form>
          <.alert :if={@checked} color="success" class="mt-4" label={@checked} />
        </.card_content>
      </.card>

      <.card>
        <.card_header title="Table" description="Made-up rows. Amounts line up on the right." />
        <.card_content>
          <.table id="sample-rows" rows={@rows}>
            <:col :let={row} label="Name">{row.name}</:col>
            <:col :let={row} label="How often">{row.how_often}</:col>
            <:col :let={row} label="Amount" class="text-right tabular-nums">{row.amount}</:col>
          </.table>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end
end
