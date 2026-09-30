defmodule FindependenceHostedWeb.AccountHTML do
  @moduledoc "Pages for signing up, in, and out, recovery, and changing a passphrase (WI-073)."
  use FindependenceHostedWeb, :html

  # SYS-001 as REV-079 restated it: members are told this before they sign up (REQ-180)
  @disclosure "Findependence is run by an operator. While you're signed in, the operator's server can read your information, so you trust the operator with your finances. When you're signed out, your information is stored encrypted and can't be read without your passphrase or your recovery key. Other members of your household see only what you choose to share with them."

  @lost_both "If you've lost both your passphrase and your recovery key, there is no way back into that account: nobody can reset it, the operator included. Create a new account and ask to be invited to your household again."

  def disclosure, do: @disclosure
  def lost_both, do: @lost_both

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>Create an account</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.alert variant="soft" color="info" heading="Before you sign up" label={disclosure()} />
          <.form for={@form} action={~p"/sign-up"} method="post" class="max-w-md">
            <.field
              field={@form[:disclosure]}
              type="checkbox"
              label="I've read how my information is handled"
              required
            />
            <.field
              field={@form[:email]}
              type="email"
              label="Email address"
              autocomplete="email"
              required
            />
            <.field
              field={@form[:passphrase]}
              type="password"
              label="Passphrase"
              autocomplete="new-password"
              help_text="At least 12 characters. It also unlocks your information: nobody can reset it."
              required
            />
            <.field
              field={@form[:passphrase_confirmation]}
              type="password"
              label="Passphrase again"
              autocomplete="new-password"
              required
            />
            <.button type="submit" label="Create account" />
          </.form>
          <.p>Already have an account? <.link href={~p"/sign-in"}>Sign in</.link></.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # shown after sign-up; after a recovery (`replaced: :recovered`), and after replacing the key (`:replaced`),
  # the old key has stopped working (REQ-184 AC-5, AC-6; WI-079)
  def recovery_key(assigns) do
    assigns = Map.put_new(assigns, :replaced, nil)

    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>{if @replaced, do: "Your new recovery key", else: "Your recovery key"}</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.p :if={@replaced == :recovered}>
            Your passphrase is changed. The recovery key you used no longer works; this one replaces it.
          </.p>
          <.p :if={@replaced == :replaced}>
            Your old recovery key no longer works, and you're signed out everywhere else.
          </.p>
          <.alert
            variant="soft"
            color="warning"
            heading="Keep this somewhere safe"
            label="It is shown only this once. If you forget your passphrase, this key is the only way back into your account and your information. Nobody can show it to you again, the operator included."
          />
          <p
            id="recovery-key"
            class="font-mono text-xl tracking-wider break-all"
          >
            {@recovery_key}
          </p>
          <.p :if={@replaced != :replaced}>
            When you've saved it, <.link href={~p"/sign-in"}>sign in</.link>.
          </.p>
          <.p :if={@replaced == :replaced}>
            When you've saved it, <.link href={~p"/"}>go back to your household</.link>.
          </.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  # REQ-184 AC-5 (WI-079): replacing the recovery key, after the passphrase
  def new_recovery_key(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>Get a new recovery key</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.p>
            Your current recovery key will stop working, and a new one is shown once. Do this if someone else
            may have seen your key.
          </.p>
          <.form for={@form} action={~p"/recovery-key"} method="post" class="max-w-md">
            <.field
              field={@form[:current]}
              type="password"
              label="Your passphrase"
              autocomplete="current-password"
              required
            />
            <.button type="submit" label="Get a new recovery key" />
          </.form>
          <.p><.link href={~p"/"}>Back to your household</.link></.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  def sign_in(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>Sign in</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.alert :if={@message} variant="soft" color="danger" label={@message} />
          <.form for={@form} action={~p"/sign-in"} method="post" class="max-w-md">
            <.field
              field={@form[:email]}
              type="email"
              label="Email address"
              autocomplete="email"
              required
            />
            <.field
              field={@form[:passphrase]}
              type="password"
              label="Passphrase"
              autocomplete="current-password"
              required
            />
            <.button type="submit" label="Sign in" />
          </.form>
          <.p>
            New here? <.link href={~p"/sign-up"}>Create an account</.link>.
            Forgot your passphrase? <.link href={~p"/recover"}>Use your recovery key</.link>.
          </.p>
          <.p class="text-sm">{lost_both()}</.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  def recover(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>Set a new passphrase with your recovery key</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.alert :if={@message} variant="soft" color="danger" label={@message} />
          <.form for={@form} action={~p"/recover"} method="post" class="max-w-md">
            <.field
              field={@form[:email]}
              type="email"
              label="Email address"
              autocomplete="email"
              required
            />
            <.field
              field={@form[:recovery_key]}
              type="text"
              label="Recovery key"
              autocomplete="off"
              help_text="As it was shown when you signed up; dashes and case don't matter."
              required
            />
            <.field
              field={@form[:passphrase]}
              type="password"
              label="New passphrase"
              autocomplete="new-password"
              help_text="At least 12 characters."
              required
            />
            <.field
              field={@form[:passphrase_confirmation]}
              type="password"
              label="New passphrase again"
              autocomplete="new-password"
              required
            />
            <.button type="submit" label="Set new passphrase" />
          </.form>
          <.p class="text-sm">{lost_both()}</.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  def delete(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>Delete your account</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.alert :if={@message} variant="soft" color="danger" label={@message} />
          <.p>
            Your account and its keys are removed. What remains is a record, with no names or content, that
            the account existed and when it was deleted. This can't be undone.
          </.p>
          <.form for={@form} action={~p"/account/delete"} method="post" class="max-w-md">
            <.field
              field={@form[:passphrase]}
              type="password"
              label="Your passphrase, to confirm"
              autocomplete="current-password"
              required
            />
            <.button type="submit" color="danger" label="Delete my account" />
          </.form>
          <.p><.link href={~p"/"}>Back</.link></.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end

  def passphrase(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.h1>Change your passphrase</.h1>
      <.card>
        <.card_content class="space-y-4">
          <.form for={@form} action={~p"/passphrase"} method="post" class="max-w-md">
            <.field
              field={@form[:current]}
              type="password"
              label="Current passphrase"
              autocomplete="current-password"
              required
            />
            <.field
              field={@form[:passphrase]}
              type="password"
              label="New passphrase"
              autocomplete="new-password"
              help_text="At least 12 characters. You'll be signed out everywhere else."
              required
            />
            <.field
              field={@form[:passphrase_confirmation]}
              type="password"
              label="New passphrase again"
              autocomplete="new-password"
              required
            />
            <.button type="submit" label="Change passphrase" />
          </.form>
          <.p><.link href={~p"/"}>Back to your household</.link></.p>
        </.card_content>
      </.card>
    </Layouts.app>
    """
  end
end
