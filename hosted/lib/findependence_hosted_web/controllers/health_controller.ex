defmodule FindependenceHostedWeb.HealthController do
  @moduledoc """
  Liveness and readiness, kept separate (ARCH-001 9.14). The app has no dependencies to
  check yet, so both answer as soon as the endpoint serves; readiness gains checks as
  dependencies arrive, liveness never does.
  """
  use FindependenceHostedWeb, :controller

  def live(conn, _params), do: text(conn, "ok")

  def ready(conn, _params), do: text(conn, "ok")
end
