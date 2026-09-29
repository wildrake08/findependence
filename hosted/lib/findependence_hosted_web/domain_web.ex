defmodule FindependenceHostedWeb.DomainWeb do
  @moduledoc """
  What the hosted form's domain pages share (WI-075): the member's trusted scope, how members are named, today's
  date, and the flow of a household-changing form (`act/4`), as the local form's router has them. The domain is
  reached only through the shared contexts and `Tenancy.scope/1` (REQ-188 AC-2).
  """
  import Plug.Conn
  import Phoenix.Controller

  alias FindependenceHosted.Tenancy
  alias FindependenceHostedWeb.FormGuard
  alias FindependenceShared.{Items, Messages, Scope, Words}

  @doc "The signed-in member's scope on the latest state of their household."
  def scope(conn), do: Tenancy.scope(conn.assigns.current)

  @doc """
  How a member is named on a page: their display name in the household (REV-097 F1), or "someone who left"
  for a member no longer in it.
  """
  def name_of(conn) do
    names = Tenancy.names(conn.assigns.current)
    fn id -> Map.get(names, id, "someone who left") end
  end

  @doc "Today, or the date the configuration sets (tests)."
  def today, do: Application.get_env(:findependence_hosted, :today) || Date.utc_today()

  @doc "How many changes are waiting for this member's answer (UX-001 R7, shown in the header)."
  def waiting(%Scope{household: h, member: m}),
    do: Items.pending(Scope.read(h, m)) |> Enum.count(&(m not in &1.consents))

  @doc """
  Runs a household-changing form, as the local form's `act`: on success, says what happened
  (`Words.outcome/6`) and goes back to where the form came from; on a refusal, `refused.(conn, message)`
  renders the page again with the refusal's message (status 422); a field mistake goes to `invalid.(detail)`.
  """
  def act(conn, action, op, opts \\ []) do
    scope = scope(conn)
    params = conn.body_params
    invalid = opts[:invalid]

    case op.(scope) do
      {:ok, saved} ->
        message =
          Words.outcome(
            action,
            params,
            scope.household,
            saved.household,
            scope.member,
            name_of(conn)
          )

        conn
        |> FormGuard.changed()
        |> put_flash(:info, message)
        |> redirect(to: return_to(params["return"], Scope.new(saved)))

      {:error, :validation, detail} when is_function(invalid) ->
        conn |> put_status(422) |> invalid.(detail)

      {:error, _category, reason, _view} ->
        refused = opts[:refused] || (&FindependenceHostedWeb.HomeController.refused/2)
        conn |> put_status(422) |> refused.(Messages.error_text(reason))
    end
  end

  @doc "Where a form returns: an item's page while the member can still see it, else home (as the local form)."
  def return_to("/items/" <> id = path, scope),
    do: if(Items.visible?(scope, id), do: path, else: "/")

  def return_to(_, _scope), do: "/"

  @doc "The words shared with the local form, for templates."
  defdelegate title(i), to: Words
end
