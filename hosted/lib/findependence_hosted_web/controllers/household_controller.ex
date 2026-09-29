defmodule FindependenceHostedWeb.HouseholdController do
  @moduledoc """
  The transport for the Tenancy context (WI-073): the household page, creating a household, joining with a
  code, and invitation codes. The household always comes from the signed-in session (REQ-186).
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHosted.{Audit, Tenancy}
  alias FindependenceHostedWeb.Auth
  alias FindependenceShared.{Households, Messages}

  def home(conn, _params), do: show(conn, 200, %{})

  def create(conn, %{"household" => %{"display_name" => name}}) do
    case Tenancy.create_household(conn.assigns.token, conn.assigns.current, name) do
      {:ok, _m} ->
        conn |> put_flash(:info, "Your household is ready.") |> redirect(to: ~p"/")

      {:error, :validation, {_f, message}} ->
        show(conn, 422, %{create_error: message, create_name: name})

      {:error, _, :already_member} ->
        redirect(conn, to: ~p"/")
    end
  end

  def join(conn, %{"join" => %{"code" => code, "display_name" => name}}) do
    case Tenancy.join(conn.assigns.token, conn.assigns.current, code, name, Auth.client(conn)) do
      {:ok, _m} ->
        conn |> put_flash(:info, "You've joined the household.") |> redirect(to: ~p"/")

      {:error, :validation, {field, message}} ->
        show(conn, 422, %{join_error: {field, message}, join_name: name})

      {:error, :rate_limited, _} ->
        show(conn, 429, %{
          join_error: {:code, "Too many attempts. Try again in 15 minutes."},
          join_name: name
        })

      {:error, _, :already_member} ->
        redirect(conn, to: ~p"/")
    end
  end

  def invite(conn, _params) do
    case Tenancy.create_invitation(conn.assigns.current) do
      # shown once, in this response only (REQ-185 AC-2)
      {:ok, code, _invitation} ->
        show(conn, 200, %{new_code: code})

      {:error, :rate_limited, _} ->
        show(conn, 422, %{invite_error: "You have 5 open codes. Withdraw one first."})
    end
  end

  def withdraw(conn, %{"id" => id}) do
    case Tenancy.withdraw_invitation(conn.assigns.current, id) do
      :ok ->
        conn |> put_flash(:info, "Code withdrawn.") |> redirect(to: ~p"/")

      {:error, :not_found, _} ->
        show(conn, 404, %{invite_error: "That code isn't one of yours, or it's no longer open."})
    end
  end

  # Leaving (REQ-110, REQ-189 AC-2), through the shared Households context. The full checklist of what the
  # member owns comes with the domain pages (WI-075); a member who still owns anything is refused, with the
  # local form's message.
  def leave_page(conn, _params), do: leave_page(conn, 200, nil)

  def leave(conn, _params) do
    current = conn.assigns.current

    case current |> Tenancy.scope() |> Households.leave() do
      {:ok, _} ->
        # a second click on Leave says it was already done (REQ-165 AC-3)
        FindependenceHosted.Forms.left(conn.body_params["_form"])

        Audit.record("leave", :ok, %{
          account_id: current.account_id,
          household_id: current.membership.household_id
        })

        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_flash(
          :info,
          "You've left the household. Sign in to start or join another, or to delete your account."
        )
        |> redirect(to: ~p"/sign-in")

      {:error, _category, :still_owner, _view} ->
        Audit.record("leave", :refused, %{
          account_id: current.account_id,
          household_id: current.membership.household_id
        })

        leave_page(conn, 422, Messages.error_text(:still_owner))
    end
  end

  defp leave_page(conn, status, message) do
    case conn.assigns.current.membership do
      nil -> redirect(conn, to: ~p"/")
      _ -> conn |> put_status(status) |> render(:leave, message: message)
    end
  end

  defp show(conn, status, extra) do
    current = Map.put(conn.assigns.current, :membership, current_membership(conn))

    assigns =
      if current.membership,
        do: %{
          members: Tenancy.member_names(current),
          invitations: Tenancy.my_open_invitations(current)
        },
        else: %{}

    conn
    |> assign(:current, current)
    |> put_status(status)
    |> render(
      if(current.membership, do: :home, else: :setup),
      Map.merge(
        Map.merge(
          %{
            new_code: nil,
            invite_error: nil,
            create_error: nil,
            create_name: "",
            join_error: nil,
            join_name: ""
          },
          assigns
        ),
        extra
      )
    )
  end

  # the session's view after this request's own change (the plug fetched it before)
  defp current_membership(conn) do
    case FindependenceHosted.Sessions.fetch(conn.assigns.token) do
      {:ok, s} -> s.membership
      _ -> nil
    end
  end
end
