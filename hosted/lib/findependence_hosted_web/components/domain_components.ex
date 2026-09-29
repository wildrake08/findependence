defmodule FindependenceHostedWeb.DomainComponents do
  @moduledoc """
  Components the domain pages share (WI-075): a household-changing form carrying its one-time token (REQ-165)
  and the page it returns to, and a table header cell that aligns with numeric columns (UX-003 C2).
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
end
