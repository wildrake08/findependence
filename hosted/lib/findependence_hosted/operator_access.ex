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

    if Application.get_env(:findependence_hosted, :console_audit, false),
      do: record_console(Node.alive?())

    {:ok, nil}
  end

  @doc """
  REQ-193 AC-2 (WI-084): a production server started with its remote console on (OPERATOR_CONSOLE=on, so
  distribution is on) writes one audit record saying so, channel release_boot. With the console off (the default),
  distribution is off and nothing is written. Returns whether a record was written.

  REQ-193 AC-3 (WI-085; ASSESS-002 FND-203): the record names the approved request's reference
  (OPERATOR_CONSOLE_APPROVAL, which rel/env.sh requires before the console can be turned on), as
  `console_enabled:<reference>`.
  """
  def record_console(distributed?, approval \\ System.get_env("OPERATOR_CONSOLE_APPROVAL")) do
    if distributed? do
      Audit.record("operator_access", :ok, %{
        resource_id: "console_enabled:" <> approval_reference(approval),
        channel: "release_boot"
      })

      true
    else
      false
    end
  end

  # a reference as env.sh accepts it; anything else (a node started without env.sh) is recorded as unapproved
  defp approval_reference(ref) when is_binary(ref) do
    if Regex.match?(~r/\A[A-Za-z0-9._-]{1,64}\z/, ref), do: ref, else: "unapproved"
  end

  defp approval_reference(_), do: "unapproved"

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
