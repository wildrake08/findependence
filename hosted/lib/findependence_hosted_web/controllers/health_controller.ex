defmodule FindependenceHostedWeb.HealthController do
  @moduledoc """
  Liveness and readiness, kept separate (ARCH-001 9.14). Liveness answers as soon as the endpoint serves and never
  depends on anything else. Readiness depends on the database (REQ-196, WI-084): it answers 200 only when a trivial
  query succeeds, and 503 otherwise, so a load balancer sends no member to a server that can't reach its data.
  """
  use FindependenceHostedWeb, :controller

  def live(conn, _params), do: text(conn, "ok")

  def ready(conn, _params) do
    if FindependenceHosted.Health.database_reachable?(),
      do: text(conn, "ok"),
      else: conn |> put_status(503) |> text("database unreachable")
  end
end
