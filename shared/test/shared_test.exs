defmodule FindependenceShared.SharedTest do
  @moduledoc """
  WI-072: the shared layer on its own, with an in-memory persistence standing in for a form's. The contexts'
  rules are tested through both forms' own suites; these tests cover what shared/ adds: the dispatch to a
  form's persistence, that a read scope cannot change anything, the failure categories, and the name rule.
  """
  use ExUnit.Case, async: false

  alias Findependence.Household
  alias FindependenceShared.{Failure, Items, Names, Persistence, Scope}

  # A form's persistence, in memory: the household lives in the scope's session.
  defmodule Memory do
    @behaviour FindependenceShared.Persistence
    alias FindependenceShared.{Failure, Scope}

    @impl true
    def run(%Scope{session: %{} = s}, fun) do
      case fun.(s.household) do
        {:error, reason} -> {:error, Failure.category(reason), reason, s}
        ok -> {:ok, %{s | household: elem(ok, 1)}}
      end
    end

    @impl true
    def refresh(%Scope{} = scope), do: scope
  end

  setup do
    previous = Application.get_env(:findependence_shared, :persistence)
    on_exit(fn -> Application.put_env(:findependence_shared, :persistence, previous) end)
    :ok
  end

  defp session(member), do: %{member: member, household: Household.new(["ana", "ben"])}

  test "with a form's persistence configured, a context changes the household through it" do
    Application.put_env(:findependence_shared, :persistence, Memory)
    scope = Scope.new(session("ana"))

    input = %{note: "Rent", amount: {:ok, -145_000}, frequency: {:every, 1, :month}, on: ""}
    assert {:ok, saved} = Items.add_item(scope, input)
    assert [item] = Items.visible(Scope.new(saved))
    assert item.attrs.note == "Rent"
    assert Enum.to_list(item.owners) == ["ana"]
  end

  test "without a configured persistence, a change is refused loudly, not silently dropped" do
    Application.delete_env(:findependence_shared, :persistence)

    assert_raise RuntimeError, ~r/no persistence configured/, fn ->
      Persistence.run(Scope.new(session("ana")), &{:ok, &1})
    end
  end

  test "a read scope cannot change anything" do
    Application.put_env(:findependence_shared, :persistence, Memory)
    read = Scope.read(Household.new(["ana"]), "ana")
    assert read.session == nil
    assert_raise FunctionClauseError, fn -> Items.relinquish(read, "x") end
  end

  test "a validation problem is reported before anything is run" do
    Application.put_env(:findependence_shared, :persistence, Memory)
    scope = Scope.new(session("ana"))
    input = %{note: "", amount: {:ok, 100}, frequency: nil, on: ""}
    assert {:error, :validation, {:note, "Give it a name."}} = Items.add_item(scope, input)
  end

  test "failure categories: an unseen item is not found, never unauthorized" do
    assert Failure.category(:not_found) == :not_found
    assert Failure.category(:not_owner) == :unauthorized
    assert Failure.category(:file_changed) == :conflict
    assert Failure.category(:something_new) == :permanent_domain_rejection
  end

  test "the name rule" do
    assert Names.name("  Rent ") == {:ok, "Rent"}
    assert Names.name("") == {:error, "Give it a name."}
    assert Names.name(String.duplicate("a", 201)) == {:error, "Use 200 characters or fewer."}
  end
end
