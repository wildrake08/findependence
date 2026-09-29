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

  # DEF-058 (WI-068): the router decodes; a domain value's range or limit is core's or a context's. So
  # web.ex holds no integer range literal, and compares a number with no literal but zero, except an HTTP
  # status, which is the transport's own.
  test "the router decides no range or limit of a domain value" do
    assert range_rules(File.read!("lib/findependence_app/web.ex")) == []
  end

  test "the range check finds a planted range, a planted limit, and not an HTTP status or zero" do
    planted = """
    defmodule Planted do
      def a(n), do: n in 1900..2100
      def b(bp), do: bp <= 10_000
      def c(conn), do: conn.status >= 400
      def d(n), do: n > 0
      def e(bp), do: bp in -500..1_500
    end
    """

    assert [{:range, 1900, 2100}, {:compare, :<=, 10_000}, {:range, -500, 1500}] =
             range_rules(planted)
  end

  defp range_rules(source) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_, found} =
      Macro.prewalk(ast, [], fn
        {:.., _, [a, b]} = node, acc ->
          case {literal(a), literal(b)} do
            {a, b} when is_integer(a) and is_integer(b) -> {node, [{:range, a, b} | acc]}
            _ -> {node, acc}
          end

        {op, _, [x, y]} = node, acc when op in [:<, :<=, :>, :>=] ->
          lit = Enum.find([literal(x), literal(y)], &(is_integer(&1) and &1 != 0))
          status? = Enum.any?([x, y], &match?({{:., _, [{:conn, _, _}, :status]}, _, _}, &1))
          {node, if(lit && not status?, do: [{:compare, op, lit} | acc], else: acc)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  # an integer literal, including a negative one (written as a unary minus)
  defp literal(n) when is_integer(n), do: n
  defp literal({:-, _, [n]}) when is_integer(n), do: -n
  defp literal(_), do: nil

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
