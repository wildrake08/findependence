defmodule FindependenceHostedWeb.Layouts do
  @moduledoc """
  The page shell for the hosted edition. Generic primitives come from Petal Components;
  this module owns only the product's layout (ARCH-001 4.1).
  """
  use FindependenceHostedWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the app shell: a header, the page, and flash and connection notices.

      <Layouts.app flash={@flash}>
        ...
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current, :map, default: nil, doc: "the signed-in session, if any (WI-073)"

  attr :waiting, :integer,
    default: 0,
    doc: "changes waiting for the member's answer (UX-001 R7, WI-075)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900">
      <div class="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-3">
        <a href={~p"/"} class="text-lg font-semibold tracking-tight text-gray-900 dark:text-gray-100">
          Findependence
        </a>
        <div class="flex flex-wrap items-center gap-3">
          <.badge variant="soft" color="gray" label="Hosted edition · not in service" />
          <.link :if={@waiting > 0} href="/#waiting" class="text-sm font-semibold">
            {@waiting} waiting for you
          </.link>
          <span :if={@current && @current.membership} class="text-sm">{@current.membership.display_name}</span>
          <.form :if={@current} for={%{}} action={~p"/sign-out"} method="post">
            <.button type="submit" variant="outline" size="sm" label="Sign out" />
          </.form>
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-5xl space-y-6 px-4 py-8">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end

  @doc """
  Shows flash messages and the notices LiveView raises when the connection drops.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" aria-live="polite" class="space-y-3">
      <.alert variant="soft" color="info" label={Phoenix.Flash.get(@flash, :info)} />
      <.alert variant="soft" color="danger" label={Phoenix.Flash.get(@flash, :error)} />

      <div
        id="client-error"
        hidden
        phx-disconnected={JS.remove_attribute("hidden", to: ".phx-client-error #client-error")}
        phx-connected={JS.set_attribute({"hidden", ""}, to: "#client-error")}
      >
        <.notice
          id="client-error-notice"
          color="warning"
          heading="Connection lost"
          label="Trying to reconnect. Nothing you do now is saved until it's back."
        />
      </div>

      <div
        id="server-error"
        hidden
        phx-disconnected={JS.remove_attribute("hidden", to: ".phx-server-error #server-error")}
        phx-connected={JS.set_attribute({"hidden", ""}, to: "#server-error")}
      >
        <.notice
          id="server-error-notice"
          color="danger"
          heading="Something went wrong"
          label="Trying to reconnect. Nothing you do now is saved until it's back."
        />
      </div>
    </div>
    """
  end

  # The connection notices, as Petal's soft alert renders them but with fixed ids, so a page is the same
  # from one request to the next apart from its form tokens (REQ-106 AC-2; WI-075).
  attr :id, :string, required: true
  attr :color, :string, required: true
  attr :heading, :string, required: true
  attr :label, :string, required: true

  defp notice(assigns) do
    ~H"""
    <div
      id={@id}
      class={"pc-alert-base-classes pc-alert--#{@color}-soft"}
      role="alert"
      aria-labelledby={"#{@id}-heading"}
      aria-describedby={"#{@id}-label"}
    >
      <div class="pc-alert">
        <div class="pc-alert__inner">
          <div>
            <h2 id={"#{@id}-heading"} class="pc-alert__heading">{@heading}</h2>
            <div id={"#{@id}-label"} class="pc-alert__label">{@label}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
