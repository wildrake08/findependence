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
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900">
      <div class="mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3">
        <a href={~p"/"} class="text-lg font-semibold tracking-tight text-gray-900 dark:text-gray-100">
          Findependence
        </a>
        <.badge color="gray" label="Hosted edition · not in service" />
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
      <.alert color="info" label={Phoenix.Flash.get(@flash, :info)} />
      <.alert color="danger" label={Phoenix.Flash.get(@flash, :error)} />

      <div
        id="client-error"
        hidden
        phx-disconnected={JS.remove_attribute("hidden", to: ".phx-client-error #client-error")}
        phx-connected={JS.set_attribute({"hidden", ""}, to: "#client-error")}
      >
        <.alert
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
        <.alert
          color="danger"
          heading="Something went wrong"
          label="Trying to reconnect. Nothing you do now is saved until it's back."
        />
      </div>
    </div>
    """
  end
end
