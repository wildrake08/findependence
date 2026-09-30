defmodule FindependenceHostedWeb.ItemController do
  @moduledoc """
  One page per thing (UX-001 R1; WI-075), as the local form's `get "/items/:id"`: an item, a value, an
  account, or a debt, for a member who can see it; adding a balance (REQ-131), with a field's mistake shown at
  the field with what was typed kept; and the confirmation pages for deleting and stopping owning (REQ-166).
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHostedWeb.{DomainWeb, HomeController, ItemHTML}
  alias FindependenceShared.{Balances, Decode, Items, Money, Words}

  def show(conn, %{"id" => id}) do
    conn |> put_status(200) |> render_item(id, nil, %{query: conn.query_params})
  end

  # REQ-131: a reading, decoded here; the rules are the Balances context's (WI-068).
  def add_reading(conn, _params) do
    p = conn.body_params

    input = %{
      balance: Decode.balance(p["balance"]),
      on: Decode.date(p["on"]),
      rate: Decode.rate(p["rate"]),
      min_payment: Money.parse(p["min_payment"] || "", "in")
    }

    DomainWeb.act(conn, "add_reading", &Balances.add_reading(&1, p["item"], input),
      refused: &refused/2,
      invalid: fn conn, {field, message} ->
        form = %{
          balance: p["balance"],
          rate: p["rate"],
          min_payment: p["min_payment"],
          on: p["on"],
          error: message,
          error_field: field
        }

        render_item(conn, p["item"], nil, form, &HomeController.refused(&1, not_found()))
      end
    )
  end

  # Irreversible actions go through a confirmation page first (REQ-166).
  def confirm(conn, %{"action" => action}) when action in ["delete", "relinquish"] do
    scope = DomainWeb.scope(conn)
    item = conn.body_params["item"] || ""
    name_of = DomainWeb.name_of(conn)
    what = Words.names(scope.household, scope.member)[item] || ""
    keepers = Items.co_owners(scope, item)

    {heading, body, yes} =
      ItemHTML.confirm_words(action, what, %{
        people: Words.people(keepers, nil, "No one", name_of),
        count: length(keepers)
      })

    conn
    |> put_view(ItemHTML)
    |> render(:confirm,
      heading: heading,
      body: body,
      yes: yes,
      action: action,
      fields: [{"item", item}],
      waiting: DomainWeb.waiting(scope)
    )
  end

  # a confirmation this form doesn't have (deleting a plan comes with the plan pages)
  def confirm(conn, _params) do
    conn |> put_status(404) |> render_not_found(DomainWeb.scope(conn))
  end

  @doc """
  A refused household-changing form (`DomainWeb.act/4`): the item's page it came from, with the message, or
  home.
  """
  def refused(conn, message) do
    case DomainWeb.return_to(conn.body_params["return"], DomainWeb.scope(conn)) do
      "/items/" <> id ->
        render_item(conn, id, {:error, message}, %{}, &HomeController.refused(&1, message))

      _ ->
        HomeController.refused(conn, message)
    end
  end

  # The item's page, if the member can see it; else `otherwise` (by default the not-found page, 404).
  defp render_item(conn, id, message, form, otherwise \\ nil) do
    scope = DomainWeb.scope(conn)

    case Items.get(scope, id) do
      {:ok, i} ->
        page = ItemHTML.page(scope, i, DomainWeb.name_of(conn), DomainWeb.today(), message, form)

        conn
        |> put_view(ItemHTML)
        |> render(:show, page: page, waiting: DomainWeb.waiting(scope))

      _ when is_function(otherwise) ->
        otherwise.(conn)

      _ ->
        conn |> put_status(404) |> render_not_found(scope)
    end
  end

  defp render_not_found(conn, scope) do
    conn |> put_view(ItemHTML) |> render(:not_found, waiting: DomainWeb.waiting(scope))
  end

  defp not_found, do: FindependenceShared.Messages.error_text(:not_found)
end
