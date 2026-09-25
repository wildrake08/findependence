defmodule RI01.Baseline do
  @moduledoc """
  The artifact store as committed at git `HEAD`, used for history checks (I-001, I-016).

  Read-only: uses `git ls-tree` and `git show` only. Returns `nil` when there is no
  usable git history, which makes the dependent checks indeterminate rather than passing.
  """

  def load(root) do
    with {:ok, listing} <- git(root, ["ls-tree", "-r", "--name-only", "HEAD", "--", "project"]) do
      artifacts =
        listing
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.ends_with?(&1, ".yaml"))
        |> Enum.reject(&(Path.basename(&1) in RI01.Store.non_artifact_documents()))
        |> Enum.flat_map(&committed_artifacts(root, &1))

      %{artifacts: artifacts, by_id: Map.new(artifacts, &{&1["id"], &1})}
    else
      _ -> nil
    end
  end

  defp committed_artifacts(root, rel) do
    with {:ok, source} <- git(root, ["show", "HEAD:" <> rel]),
         {:ok, list} <- RI01.Store.parse_document(source, rel) do
      list
    else
      _ -> []
    end
  end

  defp git(root, args) do
    case System.cmd("git", ["-C", root | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, out}
    end
  rescue
    e in ErlangError -> {:error, Exception.message(e)}
  end
end
