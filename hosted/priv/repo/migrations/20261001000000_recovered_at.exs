defmodule FindependenceHosted.Repo.Migrations.RecoveredAt do
  @moduledoc """
  WI-080 (REQ-184 AC-7, CP-025): when an account was last recovered with a recovery key, so its signed-in owner
  can see a recovery they didn't make. A time only; nothing about who recovered or from where.
  """
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :recovered_at, :utc_datetime
    end
  end
end
