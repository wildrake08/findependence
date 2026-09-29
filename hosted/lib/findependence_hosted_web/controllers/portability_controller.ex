defmodule FindependenceHostedWeb.PortabilityController do
  @moduledoc """
  The export (REQ-155, REQ-169), bringing a saved export in (CAP-009, REQ-156..159), and the leave checklist
  with its one choice per owned item and Leave itself (UX-001 R8, REQ-110, REQ-166 AC-5), as the local form's
  routes have them (WI-076). The domain is reached only through the shared contexts; the words are
  `FindependenceShared.PortabilityWords` and `Words`. Export and bring-in each write one content-free audit
  record (REQ-191 AC-1). A checked file waits in the session's memory only, until it is confirmed, cancelled,
  or the member goes to another page (REQ-158, `FormGuard.leave_bring_in/2`).
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHosted.{Audit, Forms, Sessions}
  alias FindependenceHostedWeb.{BodyParsers, DomainWeb, FormGuard}

  alias FindependenceShared.{
    Decode,
    Households,
    Items,
    Messages,
    Portability,
    PortabilityWords,
    Words
  }

  # ---------------------------------------------------------------------------
  # The export

  def export(conn, _params) do
    scope = DomainWeb.scope(conn)

    render(conn, :export,
      page_title: "What you'd take with you",
      export: Portability.export(scope),
      names: Words.names(scope.household, scope.member),
      name_of: DomainWeb.name_of(conn),
      today: DomainWeb.today(),
      waiting: DomainWeb.waiting(scope)
    )
  end

  # the saved file: members named by display name, never by id
  def export_json(conn, _params) do
    scope = DomainWeb.scope(conn)
    body = PortabilityWords.export_json(Portability.export(scope), DomainWeb.name_of(conn))
    audit(conn, "export", :ok)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="findependence-export.json")
    )
    |> send_resp(200, body)
  end

  # ---------------------------------------------------------------------------
  # Bringing in: check, preview, then confirm or cancel

  def bring_in(conn, _params), do: bring_in_page(conn, 200, nil)

  # REQ-157: at most 1 MB (a larger upload is refused by BodyParsers before it is read), then checked by the
  # Portability context; REQ-158: nothing is saved while the preview is shown.
  def check_file(conn, _params) do
    scope = DomainWeb.scope(conn)
    max = BodyParsers.max_upload()

    with {:file, %Plug.Upload{path: path, filename: name}} <- {:file, conn.body_params["file"]},
         {:size, size} when size <= max <- {:size, File.stat!(path).size},
         {:checked, {:ok, checked}} <- {:checked, Portability.check(scope, File.read!(path))} do
      Sessions.put_pending(conn.assigns.token, %{
        bundle: checked.bundle,
        fingerprint: checked.fingerprint,
        name: name
      })

      render(conn, :preview,
        page_title: "What would be brought in",
        summary: checked.summary,
        name: name,
        waiting: DomainWeb.waiting(scope)
      )
    else
      {:file, _} -> refuse_file(conn, :no_file)
      {:size, _} -> refuse_file(conn, :too_large)
      {:checked, {:error, _category, problem}} -> refuse_file(conn, problem)
    end
  end

  def confirm_bring_in(conn, _params) do
    case Sessions.take_pending(conn.assigns.token) do
      nil ->
        conn
        |> put_flash(:info, "Nothing is waiting to be brought in. Choose the file again.")
        |> redirect(to: ~p"/bring-in")

      %{bundle: bundle, fingerprint: fingerprint} ->
        # as the local form: what was brought in is said at home
        conn = %{conn | body_params: Map.put(conn.body_params, "return", "/")}

        DomainWeb.act(conn, "bring_in", fn scope ->
          result = Portability.bring_in(scope, bundle, fingerprint, DomainWeb.today())
          audit(conn, "bring_in", if(match?({:ok, _}, result), do: :ok, else: :refused))
          result
        end)
    end
  end

  def cancel_bring_in(conn, _params) do
    Sessions.take_pending(conn.assigns.token)
    conn |> put_flash(:info, "Nothing was brought in.") |> redirect(to: ~p"/bring-in")
  end

  # a file that isn't brought in: the page again, saying why; one audit record for the refused bring-in
  defp refuse_file(conn, problem) do
    audit(conn, "bring_in", :refused)
    bring_in_page(conn, 422, problem)
  end

  defp bring_in_page(conn, status, problem) do
    scope = DomainWeb.scope(conn)

    conn
    |> put_status(status)
    |> render(:bring_in,
      page_title: "Bring in your record",
      problem: problem,
      today: DomainWeb.today(),
      waiting: DomainWeb.waiting(scope)
    )
  end

  # ---------------------------------------------------------------------------
  # The leave checklist (UX-001 R8): it is also the confirmation

  def leave_page(conn, _params), do: leave_page(conn, 200, nil)

  # A sole owner's one choice for an item (REQ-166 AC-5): give it to someone, or delete it; with nothing
  # chosen, nothing is deleted. On success, back to the checklist saying what happened; a refusal is shown
  # there (as the local form's return_to for "/leave").
  def let_go(conn, _params) do
    p = conn.body_params
    scope = DomainWeb.scope(conn)

    case Items.let_go(scope, p["item"], Decode.let_go_choice(p["to"])) do
      {:ok, saved} ->
        message =
          Words.outcome(
            "let_go",
            p,
            scope.household,
            saved.household,
            scope.member,
            DomainWeb.name_of(conn)
          )

        conn
        |> FormGuard.changed()
        |> put_flash(:info, message)
        |> redirect(to: ~p"/leave")

      {:error, _category, reason, _view} ->
        leave_page(conn, 422, Messages.error_text(reason))
    end
  end

  # Leaving (REQ-110, REQ-189 AC-2), through the shared Households context; a member who still owns anything
  # is refused, with the local form's message.
  def leave(conn, _params) do
    case conn |> DomainWeb.scope() |> Households.leave() do
      {:ok, _} ->
        # a second click on Leave says it was already done (REQ-165 AC-3)
        Forms.left(conn.body_params["_form"])
        audit(conn, "leave", :ok)

        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_flash(
          :info,
          "You've left the household. Sign in to start or join another, or to delete your account."
        )
        |> redirect(to: ~p"/sign-in")

      {:error, _category, reason, _view} ->
        audit(conn, "leave", :refused)
        leave_page(conn, 422, Messages.error_text(reason))
    end
  end

  defp leave_page(conn, status, message) do
    scope = DomainWeb.scope(conn)

    conn
    |> put_status(status)
    |> render(:leave,
      page_title: "Leave the household",
      scope: scope,
      name_of: DomainWeb.name_of(conn),
      message: message,
      waiting: DomainWeb.waiting(scope)
    )
  end

  # the checklist's choice, read as the local form reads it
  # REQ-191 AC-1: content-free: the account and the household, the operation, and the outcome
  defp audit(conn, operation, outcome) do
    current = conn.assigns.current

    Audit.record(operation, outcome, %{
      account_id: current.account_id,
      household_id: current.membership.household_id
    })
  end
end
