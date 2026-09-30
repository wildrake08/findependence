defmodule FindependenceHosted.Repo.Migrations.AuditAppendOnly do
  @moduledoc """
  WI-079 (the security assessment's FND-13): audit records are only ever added (REQ-191). The database refuses
  to change or remove one, whichever role asks, so a compromised application can't rewrite what the audit
  recorded of it.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION audit_events_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'audit records are only ever added (REQ-191)';
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER audit_events_append_only
    BEFORE UPDATE OR DELETE OR TRUNCATE ON audit_events
    FOR EACH STATEMENT EXECUTE FUNCTION audit_events_append_only()
    """)
  end

  def down do
    execute("DROP TRIGGER audit_events_append_only ON audit_events")
    execute("DROP FUNCTION audit_events_append_only()")
  end
end
