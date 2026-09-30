defmodule FindependenceHostedWeb.AccountController do
  @moduledoc """
  The transport for the Identity context (WI-073): decoding forms, calling `FindependenceHosted.Accounts`, and
  showing the outcome. No rule is decided here (ARCH-003 5, 7).
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHosted.Accounts
  alias FindependenceHostedWeb.Auth

  @fields ~w(email passphrase passphrase_confirmation disclosure current recovery_key)

  def new(conn, _params), do: render(conn, :new, form: form(%{}, []))

  def create(conn, %{"account" => params}) do
    params = Map.take(params, @fields)

    case Accounts.sign_up(params) do
      {:ok, _id, recovery_key} ->
        # shown once, in this response only (REQ-184 AC-1)
        render(conn, :recovery_key, recovery_key: recovery_key)

      {:error, :validation, {field, message}} ->
        conn
        |> put_status(422)
        |> render(:new,
          form: form(Map.drop(params, ~w(passphrase passphrase_confirmation)), [{field, message}])
        )
    end
  end

  def sign_in_page(conn, _params), do: render(conn, :sign_in, form: form(%{}, []), message: nil)

  def sign_in(conn, %{"account" => params}) do
    case Accounts.sign_in(params["email"], params["passphrase"], Auth.client(conn)) do
      {:ok, token} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:token, token)
        |> redirect(to: ~p"/")

      {:error, :unauthenticated, _} ->
        refuse_sign_in(conn, params, "That email address and passphrase don't match an account.")

      {:error, :rate_limited, _} ->
        refuse_sign_in(conn, params, "Too many attempts. Try again in 15 minutes.")
    end
  end

  defp refuse_sign_in(conn, params, message) do
    conn
    |> put_status(401)
    |> render(:sign_in, form: form(Map.take(params, ["email"]), []), message: message)
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
      :ok ->
        conn
        |> put_flash(:info, "Your passphrase is changed. Sign in with the new one.")
        |> redirect(to: ~p"/sign-in")

      {:error, :validation, {field, message}} ->
        conn
        |> put_status(422)
        |> render(:recover,
          form: form(Map.take(params, ["email"]), [{field, message}]),
          message: nil
        )

      {:error, :unauthenticated, _} ->
        recover_refused(
          conn,
          params,
          "That email address and recovery key don't match an account."
        )

      {:error, :rate_limited, _} ->
        recover_refused(conn, params, "Too many attempts. Try again in 15 minutes.")
    end
  end

  defp recover_refused(conn, params, message) do
    conn
    |> put_status(401)
    |> render(:recover, form: form(Map.take(params, ["email"]), []), message: message)
  end

  def passphrase_page(conn, _params), do: render(conn, :passphrase, form: form(%{}, []))

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
