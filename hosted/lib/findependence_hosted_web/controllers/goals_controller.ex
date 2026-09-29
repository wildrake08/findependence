defmodule FindependenceHostedWeb.GoalsController do
  @moduledoc """
  Goals and set-asides (REQ-146, REQ-147) and retirement (REQ-150..154, REQ-174), as the local form's routes
  have them (WI-076). The domain is reached only through the shared contexts; decoding is the shared Decode's,
  and every rule (ranges included) is the Planning context's.
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHostedWeb.DomainWeb
  alias FindependenceShared.{Balances, Decode, Planning}

  def index(conn, _params), do: render_goals(conn, 200, nil)

  def retirement(conn, _params), do: render_retirement(conn, 200, nil, %{})

  # REQ-146: a whole number of months, or empty to clear; its range is core's.
  def fund_goal(conn, _params) do
    conn = returning(conn, "/goals")

    months =
      case Decode.int(conn.body_params["months"]) do
        {:ok, n} -> n
        :error -> :invalid
      end

    DomainWeb.act(conn, "fund_goal", &Planning.set_fund_goal(&1, months),
      refused: &goals_refused/2
    )
  end

  # REQ-147: decoding only: the rate's range is core's (Plans.set_aside/4).
  def set_aside(conn, _params) do
    conn = returning(conn, "/goals")
    p = conn.body_params
    raw = String.trim(p["rate"] || "")

    bp =
      case {raw, Decode.rate(raw)} do
        {"", _} -> nil
        {_, {:ok, bp}} -> bp
        {_, :error} -> :invalid
      end

    DomainWeb.act(conn, "set_aside", &Planning.set_aside(&1, p["value"], bp),
      refused: &goals_refused/2
    )
  end

  # REQ-150: every assumption in one form, checked by the Planning context so errors appear at the field with
  # what was typed kept; saved together, and an empty field clears its assumption.
  def save_retirement(conn, _params) do
    # what was typed, read before the form's return path is set: the return field is also named "return"
    p = conn.body_params
    conn = returning(conn, "/retirement")
    accounts = Balances.retirement_account_ids(DomainWeb.scope(conn))

    input = %{
      birth_year: Decode.int(p["birth_year"]),
      retire_age: Decode.int(p["retire_age"]),
      return_bp: Decode.return(p["return"]),
      ss_monthly: Decode.monthly_money(p["ss"]),
      target_monthly: Decode.monthly_money(p["target"]),
      contributions: for(id <- accounts, do: {id, Decode.monthly_money(p["contribution_" <> id])})
    }

    DomainWeb.act(conn, "retirement", &Planning.save_retirement(&1, input),
      refused: fn conn, message -> render_retirement(conn, 422, {:error, message}, %{}) end,
      invalid: fn conn, errors ->
        render_retirement(conn, 422, nil, %{values: p, errors: Map.new(errors, &field/1)})
      end
    )
  end

  # The form's field for each assumption the Planning context names (the local form's @retirement_fields).
  @fields %{
    birth_year: "birth_year",
    retire_age: "retire_age",
    return_bp: "return",
    ss_monthly: "ss",
    target_monthly: "target"
  }

  defp field({{:contribution, id}, message}), do: {"contribution_" <> id, message}
  defp field({key, message}), do: {@fields[key], message}

  defp goals_refused(conn, message), do: render_goals(conn, 422, {:error, message})

  # These forms go back to their own page (DomainWeb.return_to/2, as the local form's router).
  defp returning(conn, path), do: Map.update!(conn, :body_params, &Map.put(&1, "return", path))

  defp render_goals(conn, status, message) do
    scope = DomainWeb.scope(conn)

    conn
    |> put_status(status)
    |> render(:index,
      page_title: "Goals",
      scope: scope,
      message: message,
      waiting: DomainWeb.waiting(scope)
    )
  end

  defp render_retirement(conn, status, message, form) do
    scope = DomainWeb.scope(conn)

    conn
    |> put_status(status)
    |> render(:retirement,
      page_title: "Retirement",
      scope: scope,
      today: DomainWeb.today(),
      message: message,
      form: form,
      waiting: DomainWeb.waiting(scope)
    )
  end
end
