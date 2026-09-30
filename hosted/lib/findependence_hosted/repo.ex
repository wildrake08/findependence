defmodule FindependenceHosted.Repo do
  @moduledoc "The hosted form's canonical state: PostgreSQL through Ecto (ARCH-003 12; REV-098)."
  use Ecto.Repo, otp_app: :findependence_hosted, adapter: Ecto.Adapters.Postgres
end
