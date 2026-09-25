defmodule RI01.TraceCLI do
  @moduledoc "Command-line entry point for scripts/trace (REQ-010, REQ-011)."

  alias RI01.{Check, Store, Trace}

  @scope """
  Scope: PASS means only that the required justification and realization paths exist. It does
  not establish that any justification is sound or that any implementation is effective.\
  """

  def main(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: [root: :string])
    root = opts[:root] || File.cwd!()

    case {invalid, args} do
      {[], []} -> gate(root)
      {[], [id]} -> query(root, id)
      _ -> usage()
    end
  rescue
    e ->
      IO.puts(:stderr, "trace: engine error: #{Exception.message(e)}")
      System.halt(2)
  end

  defp usage do
    IO.puts(:stderr, "usage: scripts/trace [ARTIFACT-ID]")
    System.halt(2)
  end

  defp gate(root) do
    t = Trace.run(root)
    s = t.store

    IO.puts("RI-01 trace  root: #{s.root}")
    IO.puts("artifacts: #{length(s.artifacts)} from #{length(s.files)} files\n")

    if t.store_outcome == :fail do
      IO.puts("FAIL  store")
      for e <- s.load_errors, do: IO.puts("      - #{e}")
    end

    IO.puts("Upward: ImplementationElement -> justification root [#{length(t.upward)}]")
    for {id, result} <- t.upward, do: upward_line(id, result)

    IO.puts("\nDownward: accepted responsibility -> realization [#{length(t.downward)}]")
    for {id, result} <- t.downward, do: downward_line(id, result)

    IO.puts("\nRESULT: #{label(t.overall)}\n#{@scope}")
    System.halt(Check.exit_code(t.overall))
  end

  defp upward_line(id, {:pass, paths}) do
    kinds = paths |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.join(", ")
    {first, _} = hd(paths)
    IO.puts("PASS  #{id}  #{length(paths)} path(s), root: #{kinds}; e.g. #{Enum.join(first, " -> ")}")
  end

  defp upward_line(id, {:fail, messages}) do
    IO.puts("FAIL  #{id}")
    for m <- messages, do: IO.puts("      - #{m}")
  end

  defp downward_line(id, {:pass, {:realized, ies}}), do: IO.puts("PASS  #{id}  realized by #{Enum.join(ies, ", ")}")
  defp downward_line(id, {:pass, {:disposed, ids}}), do: IO.puts("PASS  #{id}  explicit disposition on #{Enum.join(ids, ", ")}")

  defp downward_line(id, {:fail, messages}) do
    IO.puts("FAIL  #{id}")
    for m <- messages, do: IO.puts("      - #{m}")
  end

  defp query(root, id) do
    s = Store.load(root)

    case s.by_id[id] do
      nil ->
        IO.puts(:stderr, "trace: unknown artifact #{id}")
        System.halt(2)

      a ->
        IO.puts("#{id}  #{a["type"]}  state: #{a["state"] || a["status"] || "-"}\n")
        IO.puts("Upward paths:")

        for p <- Trace.upward_paths(s, id) do
          tail = Trace.root_kind(s, List.last(p))
          suffix = if tail, do: "  [#{tail} root]", else: "  [no root]"
          IO.puts("  " <> Enum.map_join(p, " -> ", &describe(s, &1)) <> suffix)
        end

        IO.puts("\nDownward realization:")
        print_tree(s, Trace.downward_tree(s, id), 1)
        System.halt(0)
    end
  end

  defp print_tree(s, {id, children}, depth) do
    IO.puts(String.duplicate("  ", depth) <> describe(s, id))
    for c <- children, do: print_tree(s, c, depth + 1)
  end

  defp describe(s, id) do
    a = s.by_id[id]
    "#{id}(#{a["type"]}#{if a["disposition"], do: ", disposition", else: ""})"
  end

  defp label(:pass), do: "PASS"
  defp label(:fail), do: "FAIL"
end
