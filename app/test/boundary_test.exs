defmodule FindependenceApp.BoundaryTest do
  @moduledoc """
  ARCH-003 4, 5, and 36 (WI-066, CP-020 U3): the local-first interface is a transport adapter over the
  public context API. Its router (web.ex) and rendering (web/html.ex) reach the domain only through the
  contexts: they name no core module, and neither the Store, the persistence coordination, the session's
  internals, nor the vault. Money's decoding (parse) and display (format) are the transport's; its name
  rule is the domain's and is reached through the contexts.
  """
  use ExUnit.Case, async: true

  @adapter ["lib/findependence_app/web.ex", "lib/findependence_app/web/html.ex"]

  # modules the adapter may not name: persistence and session internals
  @forbidden [
    [:FindependenceApp, :Store],
    [:FindependenceApp, :Operation],
    [:FindependenceApp, :Session],
    [:FindependenceApp, :Vault],
    [:Store],
    [:Operation],
    [:Session],
    [:Vault]
  ]

  # domain rules the adapter may not call directly
  @forbidden_calls [{[:FindependenceApp, :Money], :name}, {[:Money], :name}]

  test "the router and rendering name no core module and no persistence or session internals" do
    for file <- @adapter do
      assert violations(File.read!(file)) == [],
             "#{file}: #{inspect(violations(File.read!(file)))}"
    end
  end

  test "the check finds a planted core call, a planted Store call, and a planted name-rule call" do
    planted = """
    defmodule Planted do
      def a(h, m), do: Findependence.View.visible_items(h, m)
      def b(s), do: FindependenceApp.Store.refresh(s)
      def c(t), do: FindependenceApp.Money.name(t)
      def d, do: &Findependence.Plans.money?/1
      def ok(t), do: FindependenceApp.Money.parse(t, "in")
    end
    """

    found = violations(planted)
    assert {:module, [:Findependence, :View]} in found
    assert {:module, [:FindependenceApp, :Store]} in found
    assert {:call, [:FindependenceApp, :Money], :name} in found
    assert {:module, [:Findependence, :Plans]} in found
    refute Enum.any?(found, &match?({:call, _, :parse}, &1))
  end

  # Every module alias in the source (calls, captures, aliases, structs) that is a core module or a
  # forbidden one, and every forbidden call.
  defp violations(source) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, mod}, fun]}, _, _} = node, acc when is_atom(fun) ->
          acc = if {mod, fun} in @forbidden_calls, do: [{:call, mod, fun} | acc], else: acc
          {node, acc}

        {:__aliases__, _, [:Findependence | _] = mod} = node, acc ->
          {node, [{:module, Enum.take(mod, 2)} | acc]}

        {:__aliases__, _, mod} = node, acc ->
          if mod in @forbidden, do: {node, [{:module, mod} | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found |> Enum.reverse() |> Enum.uniq()
  end
end
