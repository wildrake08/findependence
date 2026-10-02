defmodule FindependenceHostedWeb.AccountController do
  @moduledoc """
  The transport for the Identity context (WI-073): decoding forms, calling `FindependenceHosted.Accounts`, and
  showing the outcome. No rule is decided here (ARCH-003 5, 7).
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHosted.Accounts
  alias FindependenceHostedWeb.Auth

  @fields ~w(account_number passphrase passphrase_confirmation disclosure current recovery_key)

  def new(conn, _params), do: render(conn, :new, form: form(%{}, []))

  def create(conn, %{"account" => params}) do
    params = Map.take(params, @fields)
    client = Auth.client(conn)

    result =
      if Accounts.sign_up_allowed?(client),
        do: Accounts.sign_up(params),
        else: {:error, :rate_limited, :too_many_attempts}

    Accounts.count_sign_up(client)

    case result do
      {:ok, _id, account_number, recovery_key} ->
        # shown once, in this response only (REQ-184 AC-1)
        render(conn, :recovery_key, recovery_key: recovery_key, account_number: account_number)

      {:error, :validation, {field, message}} ->
        conn
        |> put_status(422)
        |> render(:new,
          form: form(Map.drop(params, ~w(passphrase passphrase_confirmation)), [{field, message}])
        )

      {:error, :rate_limited, _} ->
        conn
        |> put_status(429)
        |> render(:new,
          form:
            form(Map.drop(params, ~w(passphrase passphrase_confirmation)), [
              {:passphrase, "Too many sign-ups from here. Try again in 15 minutes."}
            ])
        )
    end
  end

  def sign_in_page(conn, _params), do: render(conn, :sign_in, form: form(%{}, []), message: nil)

  def sign_in(conn, %{"account" => params}) do
    device = FindependenceHostedWeb.DeviceCookie.account_id(conn)

    case Accounts.sign_in(
           params["account_number"],
           params["passphrase"],
           Auth.client(conn),
           device
         ) do
      {:ok, token} ->
        {:ok, %{account_id: account_id}} = FindependenceHosted.Sessions.fetch(token)

        conn
        |> configure_session(renew: true)
        |> put_session(:token, token)
        # this browser is now a device the account has used (WI-080)
        |> FindependenceHostedWeb.DeviceCookie.put(account_id)
        |> redirect(to: ~p"/")

      # FND-211 (WI-086): only someone whose passphrase opened a key gets here
      {:error, :unauthenticated, :account_changed} ->
        refuse_sign_in(
          conn,
          params,
          "This account's records were changed outside this service, so it can't be opened. This has been recorded for the service's operator."
        )

      {:error, :unauthenticated, _} ->
        refuse_sign_in(conn, params, "That account number and passphrase don't match an account.")

      {:error, :rate_limited, _} ->
        refuse_sign_in(conn, params, "Too many attempts. Try again in 15 minutes.")
    end
  end

  defp refuse_sign_in(conn, params, message) do
    conn
    |> put_status(401)
    |> render(:sign_in, form: form(Map.take(params, ["account_number"]), []), message: message)
  end

  def sign_out(conn, _params) do
    Accounts.sign_out(conn.assigns.token, conn.assigns.current.account_id)

    conn
    |> clear_session()
    |> configure_session(renew: true)
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/sign-in")
  end

  def recover_page(conn, _params), do: render(conn, :recover, form: form(%{}, []), message: nil)

  def recover(conn, %{"account" => params}) do
    params = Map.take(params, @fields)

    case Accounts.recover(params, Auth.client(conn)) do
      # the used key stops working; its replacement is shown once, here (REQ-184 AC-6, WI-079)
      {:ok, recovery_key} ->
        render(conn, :recovery_key, recovery_key: recovery_key, replaced: :recovered)

      {:error, :validation, {field, message}} ->
        conn
        |> put_status(422)
        |> render(:recover,
          form: form(Map.take(params, ["account_number"]), [{field, message}]),
          message: nil
        )

      {:error, :unauthenticated, :account_changed} ->
        recover_refused(
          conn,
          params,
          "This account's records were changed outside this service, so it can't be opened. This has been recorded for the service's operator."
        )

      {:error, :unauthenticated, _} ->
        recover_refused(
          conn,
          params,
          "That account number and recovery key don't match an account."
        )

      {:error, :rate_limited, _} ->
        recover_refused(conn, params, "Too many attempts. Try again in 15 minutes.")
    end
  end

  defp recover_refused(conn, params, message) do
    conn
    |> put_status(401)
    |> render(:recover, form: form(Map.take(params, ["account_number"]), []), message: message)
  end

  def passphrase_page(conn, _params), do: render(conn, :passphrase, form: form(%{}, []))

  # REQ-184 AC-5 (WI-079): a new recovery key, after the passphrase; the old one stops working
  def recovery_key_page(conn, _params), do: render(conn, :new_recovery_key, form: form(%{}, []))

  def replace_recovery_key(conn, %{"account" => params}) do
    account_id = conn.assigns.current.account_id

    case Accounts.replace_recovery_key(account_id, conn.assigns.token, params["current"]) do
      {:ok, recovery_key} ->
        render(conn, :recovery_key, recovery_key: recovery_key, replaced: :replaced)

      {:error, :validation, error} ->
        conn |> put_status(422) |> render(:new_recovery_key, form: form(%{}, [error]))
    end
  end

  def change_passphrase(conn, %{"account" => params}) do
    params = Map.take(params, @fields)

    case Accounts.change_passphrase(conn.assigns.current.account_id, conn.assigns.token, params) do
      :ok ->
        conn
        |> put_flash(:info, "Your passphrase is changed. You're signed out everywhere else.")
        |> redirect(to: ~p"/")

      {:error, :validation, {field, message}} ->
        conn |> put_status(422) |> render(:passphrase, form: form(%{}, [{field, message}]))
    end
  end

  # A field with an error is marked as used with an empty value, so its message shows (Petal shows errors
  # only for used inputs) without echoing a passphrase or key back.
  # Account deletion (REQ-189 AC-1): only once the person has left their household.
  def delete_page(conn, _params), do: delete_page(conn, 200, [], nil)

  def delete(conn, %{"account" => params}) do
    case Accounts.delete_account(conn.assigns.current.account_id, params["passphrase"]) do
      :ok ->
        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_flash(:info, "Your account is deleted.")
        |> redirect(to: ~p"/sign-up")

      {:error, :validation, error} ->
        delete_page(conn, 422, [error], nil)

      {:error, _, :still_member} ->
        delete_page(conn, 422, [], "Leave your household before you delete your account.")
    end
  end

  defp delete_page(conn, status, errors, message) do
    conn |> put_status(status) |> render(:delete, form: form(%{}, errors), message: message)
  end

  defp form(params, errors) do
    params = Enum.reduce(errors, params, fn {f, _}, acc -> Map.put_new(acc, to_string(f), "") end)

    Phoenix.Component.to_form(params,
      as: :account,
      errors: Enum.map(errors, fn {f, m} -> {f, {m, []}} end)
    )
  end
end
