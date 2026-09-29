defmodule FindependenceHostedWeb.PlanController do
  @moduledoc """
  Plans and plan requests (REQ-142, REQ-143, REQ-148, REQ-166; WI-076), as the local form's routes have them:
  the member's plans, one plan with its comparison, a plan someone asks the member to share, and the forms
  that start, change, share, and delete a plan. Decoding only, as the local form's router; the rules are the
  Planning context's, and the words are `FindependenceShared.Words` and `FindependenceShared.PlanWords`.

  A plan's forms return to the plans list or to the plan's page, which `DomainWeb.return_to/2` doesn't know,
  so this controller runs them as `DomainWeb.act/4` does, returning as the local form's `return_to` does.
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHostedWeb.{DomainWeb, FormGuard, ItemController}
  alias FindependenceShared.{Decode, Items, Messages, Money, Planning, PlanWords, Scope, Words}

  # ---------------------------------------------------------------------------
  # Pages

  def index(conn, _params), do: plans_page(conn, nil)

  def show(conn, %{"id" => id}), do: plan_page(conn, id, nil, &not_found(&1, :plan))

  # REQ-148: a plan someone asks this member to share, before they agree.
  def request(conn, %{"id" => pid}) do
    scope = DomainWeb.scope(conn)

    case Enum.find(Items.pending(scope), &plan_request?(&1, pid)) do
      nil ->
        not_found(conn, :request)

      p ->
        render(conn, :request,
          page_title: p.attrs[:label] || "",
          scope: scope,
          name_of: DomainWeb.name_of(conn),
          today: DomainWeb.today(),
          request: p,
          waiting: DomainWeb.waiting(scope)
        )
    end
  end

  # REQ-166: a plan is deleted only after the member sees its name and how many steps go with it.
  def confirm_delete(conn, _params) do
    scope = DomainWeb.scope(conn)
    id = conn.body_params["plan"] || ""

    case Planning.plan(scope, id) do
      nil ->
        conn |> put_flash(:info, "That plan no longer exists.") |> redirect(to: ~p"/plans")

      plan ->
        {heading, body, yes} = PlanWords.confirm_delete(plan.name, length(plan.steps))

        render(conn, :confirm,
          page_title: heading,
          heading: heading,
          body: body,
          yes: yes,
          id: id,
          waiting: DomainWeb.waiting(scope)
        )
    end
  end

  # ---------------------------------------------------------------------------
  # Forms

  def new_plan(conn, _params) do
    id = Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
    conn = put_return(conn, "/plans/" <> id)
    act(conn, "new_plan", &Planning.new_plan(&1, id, conn.body_params["name"]))
  end

  def share_plan(conn, _params) do
    p = conn.body_params
    conn = put_return(conn, "/plans/" <> to_string(p["plan"]))
    act(conn, "share_plan", &Planning.share_plan(&1, p["plan"], List.wrap(p["members"])))
  end

  # REQ-142: a plan step, decoded here; the step's rules are Planning's (REQ-142, REQ-129, REQ-157).
  def plan_step(conn, _params) do
    p = conn.body_params
    conn = put_return(conn, "/plans/" <> to_string(p["plan"]))

    input = %{
      kind: p["kind"],
      items: List.wrap(p["items"]),
      from: p["from"],
      note: p["note"],
      amount: Money.parse(p["amount"], p["direction"] || "out"),
      frequency: Decode.frequency(p["frequency"]),
      borrow: Decode.borrow(p)
    }

    act(conn, "plan_step", &Planning.add_step(&1, p["plan"], input),
      invalid: fn conn, message ->
        error = {:error, message}
        plan_page(conn, p["plan"], error, &plans_page(&1, error))
      end
    )
  end

  # REQ-166 AC-6: removing one step doesn't ask.
  def remove_step(conn, _params) do
    p = conn.body_params
    act(conn, "remove_step", &Planning.remove_step(&1, p["plan"], step_number(p["n"])))
  end

  def delete_plan(conn, _params),
    do: act(conn, "delete_plan", &Planning.delete_plan(&1, conn.body_params["plan"]))

  # ---------------------------------------------------------------------------
  # Running a form, as DomainWeb.act/4, returning as the local form's return_to

  defp act(conn, action, op, opts \\ []) do
    scope = DomainWeb.scope(conn)
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
            DomainWeb.name_of(conn)
          )

        conn
        |> FormGuard.changed()
        |> put_flash(:info, message)
        |> redirect(to: return_to(params["return"], Scope.new(saved)))

      {:error, :validation, detail} when is_function(invalid) ->
        conn |> put_status(422) |> invalid.(detail)

      {:error, _category, reason, _view} ->
        conn |> put_status(422) |> refused(Messages.error_text(reason))
    end
  end

  # A refused form: the page it returns to, with the message.
  defp refused(conn, message) do
    error = {:error, message}

    case return_to(conn.body_params["return"], DomainWeb.scope(conn)) do
      "/plans/" <> id -> plan_page(conn, id, error, &plans_page(&1, error))
      "/plans" -> plans_page(conn, error)
      _ -> ItemController.refused(conn, message)
    end
  end

  # As the local form's return_to: the plans list, a plan's page only for a plan this member has (plans are
  # private, so this can't reveal anything), else where DomainWeb.return_to/2 allows.
  defp return_to("/plans", _scope), do: "/plans"

  defp return_to("/plans/" <> id = path, scope),
    do: if(Planning.plan(scope, id) != nil, do: path, else: "/plans")

  defp return_to(path, scope), do: DomainWeb.return_to(path, scope)

  defp put_return(conn, path),
    do: %{conn | body_params: Map.put(conn.body_params, "return", path)}

  # Step numbers are whole numbers, as the local form's to_int: anything else matches no step.
  defp step_number(raw) do
    case Decode.int(if is_binary(raw), do: raw, else: nil) do
      {:ok, n} when is_integer(n) and n > 0 -> n
      _ -> 0
    end
  end

  # ---------------------------------------------------------------------------
  # Rendering

  defp plans_page(conn, message) do
    scope = DomainWeb.scope(conn)

    render(conn, :index,
      page_title: "Plans",
      scope: scope,
      name_of: DomainWeb.name_of(conn),
      message: message,
      waiting: DomainWeb.waiting(scope)
    )
  end

  defp plan_page(conn, id, message, otherwise) do
    scope = DomainWeb.scope(conn)
    id = to_string(id)

    case Planning.plan(scope, id) do
      nil ->
        otherwise.(conn)

      plan ->
        render(conn, :show,
          page_title: plan.name,
          scope: scope,
          name_of: DomainWeb.name_of(conn),
          today: DomainWeb.today(),
          id: id,
          plan: plan,
          message: message,
          waiting: DomainWeb.waiting(scope)
        )
    end
  end

  defp not_found(conn, what) do
    conn
    |> put_status(404)
    |> render(:not_found, what: what, waiting: DomainWeb.waiting(DomainWeb.scope(conn)))
  end

  defp plan_request?(p, pid),
    do: to_string(p.id) == pid and is_map(p[:attrs]) and p.attrs[:kind] == :plan
end
