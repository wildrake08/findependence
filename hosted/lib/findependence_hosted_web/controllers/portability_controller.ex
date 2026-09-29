defmodule FindependenceHostedWeb.PortabilityController do
  @moduledoc "WI-076 (in progress): leaving still goes through HouseholdController's minimal page."
  use FindependenceHostedWeb, :controller

  alias FindependenceHostedWeb.HouseholdController

  def leave_page(conn, params),
    do:
      conn
      |> put_view(html: FindependenceHostedWeb.HouseholdHTML)
      |> HouseholdController.leave_page(params)

  def leave(conn, params),
    do:
      conn
      |> put_view(html: FindependenceHostedWeb.HouseholdHTML)
      |> HouseholdController.leave(params)
end
