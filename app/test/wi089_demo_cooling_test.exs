defmodule FindependenceApp.WI089DemoCoolingTest do
  @moduledoc """
  WI-089: `mix findependence.demo` with the real 72-hour cooling-off (REQ-201) set, as testers run it. The demo's
  agreements are made-up history, so it builds with the wait off, marks the requests it leaves as past it, and puts
  the setting back. Without that, the real setting refused the demo's own agreements (found by the v0.8.4 captures).
  Not async: it changes the cooling-off for the whole VM while it runs.
  """
  use ExUnit.Case, async: false

  alias FindependenceApp.{Session, Vault}
  alias Mix.Tasks.Findependence.Demo

  test "the demo builds with the 72-hour setting, every member opens cleanly, and the setting is restored" do
    path =
      Path.join(System.tmp_dir!(), "fv-demo-cool-#{System.unique_integer([:positive])}.vault")

    before = Application.get_env(:findependence_shared, :cooling_seconds)
    Application.put_env(:findependence_shared, :cooling_seconds, 72 * 3600)

    on_exit(fn ->
      Application.put_env(:findependence_shared, :cooling_seconds, before)
      File.rm(path)
    end)

    :ok = Demo.build(path, iterations: 1_000, unsafe_test: true, today: ~D[2026-09-27])
    assert Application.get_env(:findependence_shared, :cooling_seconds) == 72 * 3600

    v = Vault.read!(path)

    for {m, pw} <- Demo.members() do
      {:ok, s} = Session.open(v, m, pw)
      assert Session.integrity_issues(s) == [], m
    end

    # Dad and Mom co-own the household's bills, as the demo describes
    {:ok, mom} = Session.open(v, "Mom", "mom demo passphrase")
    assert MapSet.new(["Dad", "Mom"]) == mom.household.items["mortgage"].owners
  end
end
