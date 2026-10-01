defmodule FindependenceHostedWeb.HouseholdHTML do
  @moduledoc "The household page and the first steps into a household (WI-073)."
  use FindependenceHostedWeb, :html

  # REQ-184 AC-7 (WI-080): a recovery the owner didn't make is visible to them
  attr :at, :any, required: true

  def last_recovery(assigns) do
    ~H"""
    <.p :if={@at} id="last-recovery">
      Your account was last recovered with a recovery key on {FindependenceShared.Words.date_text(
        Date.to_iso8601(DateTime.to_date(@at)),
        Date.utc_today()
      )}. If that wasn't you, <.link href={~p"/recovery-key"}>get a new recovery key</.link>
      and <.link href={~p"/passphrase"}>change your passphrase</.link>.
    </.p>
    """
  end

  # WI-081: the member's account number, which they sign in with, decrypted for their own session
  attr :number, :any, required: true

  def account_number(assigns) do
    ~H"""
    <.p :if={@number} id="your-account-number">
      Your account number: <span class="font-mono">{@number}</span>. You sign in with it.
    </.p>
    """
  end

  def setup(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>Your household</.h1>
      <.p>You're not in a household yet. Start one, or join one with a code from someone in it.</.p>
      <.account_number number={@account_number} />
      <.last_recovery at={@recovered_at} />
      <.p>
        <.link href={~p"/account/delete"}>Delete your account</.link>
      </.p>

      <.card>
        <.section_header title="Start a household" description="You'll be its first member." />
        <.card_content>
          <.form
            for={
              to_form(%{"display_name" => @create_name},
                as: :household,
                errors: errors(@create_error)
              )
            }
            action={~p"/household"}
            method="post"
            class="max-w-md"
          >
            <.field
              field={f(:household, %{"display_name" => @create_name}, @create_error)[:display_name]}
              label="Your name in the household"
              help_text="What the others will see, 1 to 200 characters."
              required
            />
            <.button type="submit" label="Start household" />
          </.form>
        </.card_content>
      </.card>

      <.card>
        <.section_header
          title="Join a household"
          description="Ask someone in it to make you a code. Codes work once, for 72 hours."
        />
        <.card_content>
          <.form
            for={join_form(@join_name, @join_error)}
            action={~p"/join"}
            method="post"
            class="max-w-md"
          >
            <.field
              field={join_form(@join_name, @join_error)[:code]}
              label="Code"
              autocomplete="off"
              required
            />
            <.field
              field={join_form(@join_name, @join_error)[:display_name]}
              label="Your name in the household"
              help_text="What the others will see, 1 to 200 characters."
              required
            />
            <.button type="submit" label="Join household" />
          </.form>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  def home(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>Your household</.h1>

      <.card>
        <.section_header
          title="Members"
          description="Invitation gives membership, not access: each person shares only what they choose."
        />
        <.card_content>
          <ul id="members" class="space-y-1">
            <li :for={name <- @members}>{name}</li>
          </ul>
        </.card_content>
      </.card>

      <.card>
        <.section_header
          title="Invite someone"
          description="A code works once, for 72 hours. Pass it on yourself: nothing is emailed."
        />
        <.card_content class="space-y-4">
          <.alert :if={@invite_error} variant="soft" color="danger" label={@invite_error} />
          <div :if={@new_code} class="space-y-2">
            <.alert variant="soft" color="success" label="Here is the code. It is shown only now." />
            <p id="new-code" class="font-mono text-xl tracking-wider">
              {@new_code}
            </p>
          </div>
          <.form for={%{}} action={~p"/invitations"} method="post">
            <.button type="submit" label="Make a code" />
          </.form>
          <div :if={@invitations != []}>
            <.h3>Your open codes</.h3>
            <ul class="space-y-2">
              <li :for={i <- @invitations} class="flex flex-wrap items-center gap-3">
                <span>Expires {Calendar.strftime(i.expires_at, "%A, %B %-d at %H:%M UTC")}</span>
                <.form for={%{}} action={~p"/invitations/#{i.id}/withdraw"} method="post">
                  <.button type="submit" variant="outline" color="danger" size="sm" label="Withdraw" />
                </.form>
              </li>
            </ul>
          </div>
        </.card_content>
      </.card>

      <.account_number number={@account_number} />
      <.last_recovery at={@recovered_at} />
      <.p><.link href={~p"/passphrase"}>Change your passphrase</.link></.p>
      <.p><.link href={~p"/recovery-key"}>Get a new recovery key</.link></.p>
      <.p><.link href={~p"/leave"}>Leave the household</.link></.p>
    </Layouts.app>
    """
  end

  defp errors(nil), do: []
  defp errors(message), do: [display_name: {message, []}]

  defp f(as, params, error), do: to_form(params, as: as, errors: errors(error))

  defp join_form(name, nil), do: to_form(%{"display_name" => name}, as: :join)

  defp join_form(name, {field, message}),
    do:
      to_form(Map.put_new(%{"display_name" => name}, to_string(field), ""),
        as: :join,
        errors: [{field, {message, []}}]
      )
end
