defmodule FindependenceHostedWeb.HomeController do
  @moduledoc """
  The household page (WI-075, the local form's home): everything the member can see, what is waiting for them,
  and adding an item. A member without a household is shown how to start or join one.
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceHostedWeb.HouseholdController

  def index(conn, params) do
    case conn.assigns.current.membership do
      nil -> HouseholdController.home(conn, params)
      _ -> render_home(conn, 200, nil, %{})
    end
  end

  @doc "The home page again with a refusal's message (DomainWeb.act/4)."
  def refused(conn, message), do: render_home(conn, conn.status || 422, {:error, message}, %{})

  defp render_home(conn, status, _message, _form) do
    conn |> put_status(status) |> text("home (WI-075 in progress)")
  end
end
