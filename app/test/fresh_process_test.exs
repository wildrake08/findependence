defmodule FindependenceApp.FreshProcessTest do
  @moduledoc """
  WI-016: a vault must be readable and unlockable by a freshly started BEAM, where no app or core
  module has been loaded yet, so no atom they define exists until the Vault module loads.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.{Session, Vault}
  alias Findependence.{Alignment, Exit, Household}

  defp act(v, m, fun) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
    end
  end

  test "a fresh process reads and unlocks a vault holding every kind of content" do
    v =
      Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}],
        iterations: 1_000,
        unsafe_test: true
      )

    v = act(v, "ana", &Household.add_item(&1, "ana", "i1", %{note: "rent", amount: -100}))
    v = act(v, "ana", &Household.add_item(&1, "ana", "i2", %{note: "gone", amount: 1}))

    # REQ-127: every frequency must decode in a fresh process
    v =
      for {f, n} <- Enum.with_index(Alignment.frequencies()), reduce: v do
        v ->
          attrs = %{note: "f#{n}", amount: -(n + 1) * 100, unit: :cents, frequency: f}
          act(v, "ana", &Household.add_item(&1, "ana", "f#{n}", attrs))
      end

    v = act(v, "ana", &Alignment.add_value(&1, "ana", "v1", "home"))
    v = act(v, "ana", &Alignment.link(&1, "ana", "i1", "v1"))
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
    v = act(v, "ana", &Household.revoke_grant(&1, "ana", "i1", "ben"))
    v = act(v, "ana", &Exit.delete(&1, "ana", "i2"))
    v = act(v, "ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "cy"]))
    v = act(v, "cy", &Household.relinquish(&1, "cy", "i1"))
    v = act(v, "ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "ben"]))
    v = act(v, "ana", &Household.propose_owners(&1, "ana", "v1", ["ana", "ben"]))
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "v1", "cy"))
    assert map_size(v.proposals) >= 1

    path = Path.join(System.tmp_dir!(), "fv-fresh-#{System.unique_integer([:positive])}.vault")
    Vault.write!(v, path)
    on_exit(fn -> File.rm(path) end)

    paths =
      Path.wildcard(Path.join(Mix.Project.build_path(), "lib/*/ebin"))
      |> Enum.flat_map(&["-pa", &1])

    script = """
    v = FindependenceApp.Vault.read!(#{inspect(path)})
    for m <- ["ana", "ben"] do
      {:ok, s} = FindependenceApp.Session.open(v, m, "pw-" <> m)
      h = s.household
      IO.puts("\#{m} visible=\#{length(Findependence.View.visible_items(h, m))} pending=\#{length(Findependence.Household.pending(h, m))} links=\#{length(Findependence.Alignment.links(h, m))} deletions=\#{length(Findependence.Ledger.deletions(h, m))} dist=\#{(fn d -> "\#{d.count} \#{d.per_month.in} \#{d.per_month.out} \#{d.one_off.in} \#{d.one_off.out}" end).(Findependence.Alignment.distribution(h, m).unlinked)}")
    end
    """

    {out, status} = System.cmd("elixir", paths ++ ["-e", script], stderr_to_stdout: true)
    assert status == 0, "fresh process failed:\n" <> out
    # the fresh process must see exactly what this (warm) process sees. Totals are printed in a
    # fixed order: `inspect` of a map can order keys differently in another VM (ASM-019).
    dist = fn d ->
      "#{d.count} #{d.per_month.in} #{d.per_month.out} #{d.one_off.in} #{d.one_off.out}"
    end

    expected =
      for m <- ["ana", "ben"], into: "" do
        {:ok, s} = Session.open(v, m, "pw-" <> m)
        h = s.household

        "#{m} visible=#{length(Findependence.View.visible_items(h, m))} pending=#{length(Household.pending(h, m))} links=#{length(Alignment.links(h, m))} deletions=#{length(Findependence.Ledger.deletions(h, m))} dist=#{dist.(Alignment.distribution(h, m).unlinked)}\n"
      end

    assert out == expected, "fresh process saw:\n" <> out
    assert expected =~ "pending=1"
    # REQ-128 presets in order: one-off -100; weekly -200 -> -867; every 2 weeks -300 -> -650;
    # monthly -400; every 2 months -500 -> -250; every 3 months -600 -> -200; twice a year
    # -700 -> -117; yearly -800 -> -67; irregular -900 a year -> -75. Per month: -2626
    # count, per month in, per month out, one-off in, one-off out
    assert expected =~ "ana visible=11 pending=1 links=1 deletions=1 dist=9 0 -2626 0 -100\n"
  end
end
