defmodule FindependenceHostedWeb.BoundaryTest do
  @moduledoc """
  REQ-188 AC-2 (WI-074), as app/test/boundary_test.exs for the local form: the hosted form's web layer is a
  transport adapter over the public context API. It names no core module, and none of the storage: the Repo, the
  schemas, the domain storage and persistence (Domain, Operation), or the shared envelope and persistence.
  """
  use ExUnit.Case, async: true

  # modules the web layer may not name: storage, persistence, and envelope internals
  @forbidden [
    [:FindependenceHosted, :Repo],
    [:FindependenceHosted, :Schemas],
    [:FindependenceHosted, :Domain],
    [:FindependenceHosted, :Operation],
    [:FindependenceShared, :Envelope],
    [:FindependenceShared, :Persistence],
    [:Repo],
    [:Schemas],
    [:Domain],
    [:Operation],
    [:Envelope],
    [:Persistence],
    [:Ecto]
  ]

  test "the web layer names no core module and no storage or persistence internals" do
    for file <- Path.wildcard("lib/findependence_hosted_web/**/*.ex") do
      assert violations(File.read!(file)) == [],
             "#{file}: #{inspect(violations(File.read!(file)))}"
    end
  end

  test "the check finds a planted core call, a planted Repo call, and a planted storage call" do
    planted = """
    defmodule Planted do
      def a(h, m), do: Findependence.View.visible_items(h, m)
      def b, do: FindependenceHosted.Repo.all(X)
      def c(s), do: FindependenceHosted.Domain.view(s)
      def d(v), do: FindependenceShared.Envelope.build(v)
      def ok(s), do: FindependenceShared.Households.leave(s)
    end
    """

    found = violations(planted)
    assert {:module, [:Findependence, :View]} in found
    assert {:module, [:FindependenceHosted, :Repo]} in found
    assert {:module, [:FindependenceHosted, :Domain]} in found
    assert {:module, [:FindependenceShared, :Envelope]} in found
    refute {:module, [:FindependenceShared, :Households]} in found
  end

  defp violations(source) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_, found} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, _, [:Findependence | _] = mod} = node, acc ->
          {node, [{:module, Enum.take(mod, 2)} | acc]}

        {:__aliases__, _, mod} = node, acc when is_list(mod) ->
          if Enum.take(mod, 2) in @forbidden or Enum.take(mod, 1) in @forbidden,
            do: {node, [{:module, Enum.take(mod, 2)} | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found |> Enum.reverse() |> Enum.uniq()
  end
end
