ExUnit.start()
run_dir = Path.join(System.tmp_dir!(), "ri01-test-#{:os.getpid()}")
ExUnit.after_suite(fn _ -> File.rm_rf!(run_dir) end)

defmodule RI01.Fixture do
  @moduledoc """
  Builds a throwaway repository containing the real framework definitions and a
  minimal valid artifact store. Artifacts are written as JSON, which is valid YAML.
  """

  @repo_root Path.expand("../../..", __DIR__)

  def prov, do: %{"created_by" => "ACT-002", "inputs" => ["fixture"]}
  def rel(type, to), do: %{"type" => type, "to" => to}
  def h(from, to, by, authority \\ "REV-001"), do: %{"from" => from, "to" => to, "by" => by, "authority" => authority}

  def specified_history,
    do: [h(nil, "proposed", "ACT-002"), h("proposed", "coherent", "ACT-001"), h("coherent", "specified", "ACT-001")]

  @doc "A minimal store in which every invariant passes (I-016 needs `git: true`)."
  def valid_store do
    %{
      "project/governance/actors.yaml" => [
        %{"id" => "ACT-001", "type" => "Actor", "kind" => "human", "provenance" => prov()},
        %{"id" => "ACT-002", "type" => "Actor", "kind" => "ai_agent", "provenance" => prov()}
      ],
      "project/semantic/foundation.yaml" => [
        %{"id" => "SUBJ-001", "type" => "Subject", "state" => "proposed", "statement" => "s", "provenance" => prov()},
        %{
          "id" => "TEL-001",
          "type" => "Telos",
          "state" => "specified",
          "statement" => "t",
          "history" => specified_history(),
          "relationships" => [rel("concerns", "SUBJ-001")],
          "provenance" => prov()
        },
        %{"id" => "CON-001", "type" => "Constraint", "state" => "proposed", "provenance" => prov()}
      ],
      "project/realization/realization.yaml" => [
        %{
          "id" => "REQ-001",
          "type" => "Requirement",
          "state" => "specified",
          "accepted_by" => %{"actor" => "ACT-001"},
          "history" => specified_history(),
          "relationships" => [rel("derived_from", "CON-001")],
          "provenance" => prov()
        },
        %{
          "id" => "IE-001",
          "type" => "ImplementationElement",
          "work_item" => "WI-001",
          "paths" => ["src/a.ex"],
          "relationships" => [rel("satisfies", "REQ-001")],
          "provenance" => prov()
        },
        %{
          "id" => "WI-001",
          "type" => "WorkItem",
          "status" => "in_progress",
          "authority" => "REV-001",
          "allowed_files" => ["src/**"],
          "canonical_inputs" => [%{"path" => "framework/invariants/core.yaml", "sha256" => core_sha()}],
          "provenance" => prov()
        }
      ],
      "project/assurance/assurance.yaml" => [
        %{"id" => "CLM-001", "type" => "Claim", "state" => "proposed", "provenance" => prov()},
        %{
          "id" => "EVC-001",
          "type" => "Evidence",
          "stage" => "candidate",
          "integrity" => "untrusted",
          "applicability" => "applicable",
          "proposed_bindings" => ["CLM-001"],
          "provenance" => prov()
        }
      ],
      "project/change/changes.yaml" => [
        %{"id" => "CHG-001", "type" => "ChangeEvent", "impact_analysis" => "additive", "provenance" => prov()}
      ]
    }
  end

  @doc "Applies `fun` to the artifact with `id`."
  def update(store, id, fun) do
    Map.new(store, fn {file, arts} ->
      {file, Enum.map(arts, fn a -> if a["id"] == id, do: fun.(a), else: a end)}
    end)
  end

  def add(store, file, artifact), do: Map.update(store, file, [artifact], &(&1 ++ [artifact]))

  @doc "Writes `store` into a fresh repository and returns its root."
  def write(store, opts \\ []) do
    root = Path.join([System.tmp_dir!(), "ri01-test-#{:os.getpid()}", "#{System.unique_integer([:positive])}"])
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "automation"))
    File.cp_r!(Path.join(@repo_root, "framework"), Path.join(root, "framework"))
    File.cp_r!(Path.join(@repo_root, "automation/policies"), Path.join(root, "automation/policies"))
    File.write!(Path.join(root, "project/manifest.yaml") |> tap(&File.mkdir_p!(Path.dirname(&1))), manifest(opts))

    for {file, arts} <- store do
      path = Path.join(root, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, encode(%{"version" => 1, "artifacts" => arts}))
    end

    if opts[:git], do: commit(root)
    root
  end

  def commit(root) do
    git = fn args -> {_, 0} = System.cmd("git", ["-C", root, "-c", "user.name=t", "-c", "user.email=t@t" | args], stderr_to_stdout: true) end
    unless File.dir?(Path.join(root, ".git")), do: git.(["init", "-q"])
    git.(["add", "-A"])
    git.(["commit", "-q", "--allow-empty", "-m", "fixture"])
    root
  end

  def rewrite(root, store) do
    for {file, arts} <- store, do: File.write!(Path.join(root, file), encode(%{"version" => 1, "artifacts" => arts}))
    root
  end

  def check(store, opts \\ []), do: RI01.Check.run(write(store, opts))

  def outcome(check, id) do
    {_, result} = Enum.find(check.results, fn {inv, _} -> inv["id"] == id end)
    result
  end

  defp manifest(opts) do
    foundation = Map.merge(%{"subject" => nil, "telos" => nil, "purpose" => nil}, opts[:canonical_foundation] || %{})
    encode(%{"canonical_foundation" => foundation, "lifecycle" => %{"project_state" => "orienting"}})
  end

  defp core_sha,
    do: :crypto.hash(:sha256, File.read!(Path.join(@repo_root, "framework/invariants/core.yaml"))) |> Base.encode16(case: :lower)

  defp encode(term), do: term |> nulls() |> :json.encode() |> IO.iodata_to_binary()

  defp nulls(nil), do: :null
  defp nulls(m) when is_map(m), do: Map.new(m, fn {k, v} -> {k, nulls(v)} end)
  defp nulls(l) when is_list(l), do: Enum.map(l, &nulls/1)
  defp nulls(v), do: v
end
