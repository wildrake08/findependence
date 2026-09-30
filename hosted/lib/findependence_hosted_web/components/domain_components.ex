defmodule FindependenceHostedWeb.DomainComponents do
  @moduledoc """
  Components the domain pages share (WI-075): a household-changing form carrying its one-time token (REQ-165)
  and the page it returns to, and a card's section heading.
  """
  use Phoenix.Component
  import PetalComponents.Button

  @doc """
  A form that changes the household: posts to `action` with a one-time form token, a `return` path, and any
  hidden `fields`, and holds the slot (fields and buttons). With `button`, it is a single button.
  """
  attr :action, :string, required: true
  attr :return, :string, default: nil
  attr :fields, :list, default: [], doc: "hidden fields as {name, value}"
  attr :button, :string, default: nil
  attr :aria, :string, default: nil
  attr :danger, :boolean, default: false
  attr :class, :any, default: nil
  attr :id, :string, default: nil
  slot :inner_block

  def act_form(assigns) do
    assigns = assign(assigns, :form_token, FindependenceHosted.Forms.new_token())

    ~H"""
    <.form for={%{}} action={@action} method="post" class={@class} id={@id}>
      <input type="hidden" name="_form" value={@form_token} />
      <input :if={@return} type="hidden" name="return" value={@return} />
      <input :for={{name, value} <- @fields} type="hidden" name={name} value={value} />
      {render_slot(@inner_block)}
      <.button
        :if={@button}
        type="submit"
        size="sm"
        variant={if @danger, do: "outline", else: "solid"}
        color={if @danger, do: "danger", else: "primary"}
        label={@button}
        aria-label={@aria}
      />
    </.form>
    """
  end

  @doc """
  Petal's card header, with the title as a heading, so each section is in the page's outline under its h1
  (axe heading-order, WI-073). The same classes as Petal's, so the same look.
  """
  attr :title, :string, required: true
  attr :description, :string, default: nil

  def section_header(assigns) do
    ~H"""
    <div class="pc-card__header">
      <div class="pc-card__header-titles">
        <h2 class="pc-card__title">{@title}</h2>
        <div :if={@description} class="pc-card__description">{@description}</div>
      </div>
    </div>
    """
  end
end
