defmodule FindependenceHosted.OperatorAccessTest do
  @moduledoc """
  REQ-191 AC-1 (WI-077): operator access to production writes one audit record. A real node connects to this one,
  as an operator's remote console does; a release command runs, as an operator runs a migration.
  """
  use FindependenceHostedWeb.ConnCase, async: false

  import Ecto.Query
  alias FindependenceHosted.Repo
  alias FindependenceHosted.Schemas.AuditEvent

  defp operator_records,
    do:
      Repo.all(
        from e in AuditEvent,
          where: e.operation == "operator_access",
          order_by: e.id
      )

  defp eventually(fun, tries \\ 40) do
    case fun.() do
      [] when tries > 0 ->
        Process.sleep(50)
        eventually(fun, tries - 1)

      result ->
        result
    end
  end

  # This VM as a distributed node, as a release runs; epmd is started on the loopback interface if it isn't
  # running (a VM started by mix doesn't start it).
  defp distribute do
    if Node.alive?() do
      false
    else
      epmd = System.find_executable("epmd") || flunk("epmd is needed to test a connecting node")
      {_, 0} = System.cmd(epmd, ["-daemon"], env: [{"ERL_EPMD_ADDRESS", "127.0.0.1"}])

      {:ok, _} =
        Node.start(:"fh_test_#{System.unique_integer([:positive])}@localhost", :shortnames)

      true
    end
  end

  test "a node connecting to the running system (a remote console) writes one record" do
    started = distribute()
    on_exit(fn -> if started, do: Node.stop() end)

    name = :"fh_operator_#{System.unique_integer([:positive])}"
    {:ok, peer, node} = :peer.start(%{name: name, host: ~c"localhost"})
    on_exit(fn -> :peer.stop(peer) end)
    assert Node.connect(node)

    records =
      eventually(fn ->
        Enum.filter(operator_records(), &(&1.resource_id == Atom.to_string(node)))
      end)

    assert [r] = records
    assert r.channel == "remote_console" and r.outcome == "ok" and r.at
    assert r.account_id == nil and r.household_id == nil
    # the node itself, reported when distribution starts, is not access
    refute Enum.any?(operator_records(), &(&1.resource_id == Atom.to_string(Node.self())))
  end

  test "a release command writes one record, naming the command" do
    assert FindependenceHosted.Release.migrate() == []
    assert [r] = Enum.filter(operator_records(), &(&1.channel == "release_command"))
    assert r.resource_id == "migrate" and r.outcome == "ok"
  end

  test "operator access is one of the audited operations, and its records hold no content" do
    assert "operator_access" in FindependenceHosted.Audit.operations()

    assert AuditEvent.__schema__(:fields) == [
             :id,
             :at,
             :account_id,
             :household_id,
             :operation,
             :resource_id,
             :channel,
             :outcome
           ]
  end
end
