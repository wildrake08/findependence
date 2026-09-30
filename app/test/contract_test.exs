defmodule FindependenceApp.ContractForm do
  @moduledoc """
  The local-first form for the contract cases (REQ-188 AC-1, WI-074): a household in a vault file in a
  temporary directory, its Store, and each member unlocked with their passphrase.
  """
  @behaviour FindependenceShared.Contract.Form

  import ExUnit.Callbacks, only: [start_supervised!: 1]
  alias FindependenceApp.{Session, Store, Vault}
  alias FindependenceShared.Scope

  @impl true
  def household(names) do
    dir = Path.join(System.tmp_dir!(), "fv-contract-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, "household.vault")

    names
    |> Enum.map(&{&1, pass(&1)})
    |> Vault.create(iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    Map.new(names, &{&1, %{name: &1, path: path}})
  end

  @impl true
  def scope(%{name: name}) do
    {:ok, s} = Session.open(Store.vault(), name, pass(name))
    Scope.new(s)
  end

  @impl true
  def member(%{name: name}), do: name

  @impl true
  def stored(_), do: Store.vault()

  @impl true
  def stored_bytes(%{path: path}), do: [File.read!(path)]

  @impl true
  def fixed_membership?, do: true

  defp pass(name), do: name <> " passphrase 1"
end

defmodule FindependenceApp.ContractTest do
  @moduledoc "REQ-188 AC-1 (WI-074): the contract cases on the local-first form."
  use ExUnit.Case, async: false

  @form FindependenceApp.ContractForm
  import FindependenceShared.Contract.Helpers

  use FindependenceShared.Contract
end
