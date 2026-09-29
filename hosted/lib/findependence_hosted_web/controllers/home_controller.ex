defmodule FindependenceHostedWeb.HomeController do
  @moduledoc """
  The household page (WI-075, the local form's home): everything the member can see, what is waiting for them,
  and adding an item. A member without a household is shown how to start or join one.
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHostedWeb.{DomainWeb, HouseholdController}
  alias FindependenceShared.{Decode, Items, Money}

  def index(conn, params) do
    case conn.assigns.current.membership do
      nil -> HouseholdController.home(conn, params)
      _ -> render_home(conn, 200, nil, %{})
    end
  end

  @doc "The home page again with a refusal's message (DomainWeb.act/4)."
  def refused(conn, message), do: render_home(conn, conn.status || 422, {:error, message}, %{})

  # UX-001 R2: an unclear amount is rejected before anything is saved, with the input kept. Decoding only,
  # as the local form's router; the rules (REQ-129, REQ-136, REQ-157) are the Items context's.
  def add_item(conn, _params) do
    p = conn.body_params

    input = %{
      note: p["note"],
      amount: Money.parse(p["amount"], p["direction"] || "out"),
      frequency: Decode.frequency(p["frequency"]),
      on: p["on"]
    }

    DomainWeb.act(conn, "add_item", &Items.add_item(&1, input),
      invalid: fn conn, {field, message} ->
        form = %{
          note: p["note"],
          amount: p["amount"],
          direction: p["direction"],
          frequency: p["frequency"],
          on: p["on"],
          error: message,
          error_field: field
        }

        render_home(conn, 422, nil, form)
      end
    )
  end

  defp render_home(conn, status, message, form) do
    scope = DomainWeb.scope(conn)

    conn
    |> put_status(status)
    |> render(:home,
      scope: scope,
      name_of: DomainWeb.name_of(conn),
      today: DomainWeb.today(),
      waiting: DomainWeb.waiting(scope),
      message: message,
      form: form
    )
  end
end
