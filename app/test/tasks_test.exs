defmodule FindependenceApp.TasksTest do
  @moduledoc "WI-015: the setup and serve tasks (setup crashed before this fix)."
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias FindependenceApp.{Session, Vault}

  defp tmp(name),
    do: Path.join(System.tmp_dir!(), "fv-task-#{System.unique_integer([:positive])}-#{name}")

  test "setup creates a vault each member can unlock, re-asking on a mismatch or a short passphrase" do
    path = tmp("setup.vault")
    on_exit(fn -> File.rm(path) end)

    input =
      "short\nshort\nana passphrase 1\nnot the same one\nana passphrase 1\nana passphrase 1\nben passphrase 2\nben passphrase 2\n"

    out = capture_io(input, fn -> Mix.Tasks.Findependence.Setup.run([path, "Ana", "Ben"]) end)
    assert out =~ "Too short"
    assert out =~ "did not match"
    refute out =~ "ana passphrase 1"
    # REV-035: the alpha rule is printed before anyone types a passphrase
    assert out =~ "Alpha: use made-up data only."
    assert :binary.match(out, "Alpha:") < :binary.match(out, "please type your passphrase")

    vault = Vault.read!(path)
    assert vault.iterations >= 600_000
    assert {:ok, _} = Session.open(vault, "Ana", "ana passphrase 1")
    assert {:ok, _} = Session.open(vault, "Ben", "ben passphrase 2")
  end

  test "setup stops cleanly, creating nothing, when input runs out" do
    path = tmp("empty.vault")

    assert_raise Mix.Error, ~r/No passphrase was entered/, fn ->
      capture_io("", fn -> Mix.Tasks.Findependence.Setup.run([path, "Ana"]) end)
    end

    refute File.exists?(path)
  end

  test "setup refuses to overwrite an existing household" do
    path = tmp("exists.vault")
    File.write!(path, "x")
    on_exit(fn -> File.rm(path) end)

    assert_raise Mix.Error, ~r/already exists/, fn ->
      Mix.Tasks.Findependence.Setup.run([path, "Ana"])
    end
  end

  test "serve explains how to create a missing household instead of crashing" do
    assert_raise Mix.Error, ~r/No household file.*mix findependence.setup/s, fn ->
      Mix.Tasks.Findependence.Serve.run([tmp("missing.vault"), "4999"])
    end
  end
end
