defmodule RI01.Store do
  @moduledoc """
  Read-only view of the framework definitions and the project artifact store (REQ-004, REQ-006).

  Every `*.yaml` file under `project/` except `manifest.yaml` and `bootstrap.yaml` is an
  artifact document with a top-level `artifacts` list.
  """

  @non_artifact_documents ~w(manifest.yaml bootstrap.yaml)

  defstruct [
    :root,
    :types,
    :relationships,
    :machines,
    :invariants,
    :policies,
    :manifest,
    :baseline,
    artifacts: [],
    by_id: %{},
    files: [],
    load_errors: []
  ]

  def non_artifact_documents, do: @non_artifact_documents

  def load(root) do
    root = Path.expand(root)
    vocab = read!(root, "framework/vocabulary/artifacts.yaml")

    types =
      (Enum.flat_map(vocab["foundational"], fn {_, ts} -> ts end) ++ vocab["derived"])
      |> MapSet.new()

    {files, artifacts, errors} = load_artifacts(root)

    %__MODULE__{
      root: root,
      types: types,
      relationships: read!(root, "framework/vocabulary/relationships.yaml")["relationships"],
      machines: read!(root, "framework/states/machines.yaml"),
      invariants: read!(root, "framework/invariants/core.yaml")["invariants"],
      policies: read!(root, "automation/policies/authority.yaml")["policies"],
      manifest: read_optional(root, "project/manifest.yaml"),
      baseline: RI01.Baseline.load(root),
      files: files,
      artifacts: artifacts,
      by_id: Map.new(artifacts, &{&1["id"], &1}),
      load_errors: errors
    }
  end

  def artifact_files(root) do
    Path.wildcard(Path.join(root, "project/**/*.yaml"))
    |> Enum.reject(&(Path.basename(&1) in @non_artifact_documents))
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.sort()
  end

  @doc "Parses one artifact document. Returns `{:ok, artifacts}` or `{:error, message}`."
  def parse_document(source, rel) do
    case YamlElixir.read_from_string(source) do
      {:ok, %{"artifacts" => list}} when is_list(list) ->
        if Enum.all?(list, &is_map/1),
          do: {:ok, Enum.map(list, &Map.put(&1, "__file", rel))},
          else: {:error, "#{rel}: every entry of 'artifacts' must be a mapping"}

      {:ok, _} ->
        {:error, "#{rel}: not an artifact document (no top-level 'artifacts' list)"}

      {:error, %{message: msg}} ->
        {:error, "#{rel}: YAML parse error: #{msg}"}
    end
  end

  defp load_artifacts(root) do
    files = artifact_files(root)

    {artifacts, errors} =
      Enum.reduce(files, {[], []}, fn rel, {arts, errs} ->
        case parse_document(File.read!(Path.join(root, rel)), rel) do
          {:ok, list} -> {arts ++ list, errs}
          {:error, msg} -> {arts, errs ++ [msg]}
        end
      end)

    {files, artifacts, errors}
  end

  defp read!(root, rel), do: YamlElixir.read_from_file!(Path.join(root, rel))

  defp read_optional(root, rel) do
    path = Path.join(root, rel)
    if File.exists?(path), do: YamlElixir.read_from_file!(path), else: nil
  end
end
