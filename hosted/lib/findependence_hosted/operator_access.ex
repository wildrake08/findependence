defmodule FindependenceHosted.OperatorAccess do
  @moduledoc """
  REQ-191 AC-1 (WI-077): operator access to the running system is audited. An operator reaches a running release
  through a remote console or rpc, each of which connects a node to this one; each node that connects writes one
  content-free audit record (operation operator_access, channel remote_console, the connecting node's name as
  the resource). Release commands record themselves (`FindependenceHosted.Release`). The release keeps
  distribution on the loopback interface (rel/env.sh.eex), so only an operator on the machine can connect.
  """
  use GenServer

  alias FindependenceHosted.Audit

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    # works before distribution starts too, so a node that becomes distributed later is still watched
    :ok = :net_kernel.monitor_nodes(true, node_type: :all)
    {:ok, nil}
  end

  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    # when distribution starts after this subscribed, the node itself is reported first; it is no access
    if node != Node.self() do
      Audit.record("operator_access", :ok, %{
        resource_id: Atom.to_string(node),
        channel: "remote_console"
      })
    end

    {:noreply, state}
  end

  def handle_info({:nodedown, _node, _info}, state), do: {:noreply, state}
end
