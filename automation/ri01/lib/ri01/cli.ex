defmodule RI01.CLI do
  @moduledoc "Command-line entry point for scripts/check."

  alias RI01.{Check, Invariants}

  @scope """
  Scope: PASS means only that no applicable deterministic invariant failed. It does not
  establish semantic, causal, normative, Capability, Outcome, Purpose, or Telos truth,
  and passing this check does not satisfy any higher-level gate.\
  """

  def main(argv) do
    {opts, _, invalid} = OptionParser.parse(argv, strict: [root: :string, explain: :boolean])

    cond do
      invalid != [] ->
        IO.puts(:stderr, "usage: scripts/check [--explain]")
        System.halt(2)

      opts[:explain] ->
        explain()
        System.halt(0)

      true ->
        run(opts[:root] || File.cwd!())
    end
  end

  defp run(root) do
    check = Check.run(root)
    s = check.store

    IO.puts("RI-01 check  framework: canonical-software-system-lifecycle-bootstrap v1")
    IO.puts("root: #{s.root}")
    IO.puts("artifacts: #{length(s.artifacts)} from #{length(s.files)} files; git baseline: #{baseline(s)}\n")

    line("store", "artifact store loads", check.store_outcome, length(s.files), s.load_errors)

    for {inv, {outcome, n, messages}} <- check.results,
        do: line(inv["id"], inv["name"], outcome, n, messages)

    IO.puts("\nRESULT: #{label(check.overall)}\n#{@scope}")
    System.halt(Check.exit_code(check.overall))
  rescue
    e ->
      IO.puts(:stderr, "check: engine error: #{Exception.message(e)}")
      System.halt(2)
  end

  defp line(id, name, outcome, n, messages) do
    note = if outcome == :pass and n == 0, do: " (vacuous: no applicable artifacts)", else: ""
    IO.puts(String.pad_trailing("#{label(outcome)}", 14) <> String.pad_trailing(id, 7) <> "#{name} [#{n}]#{note}")
    for m <- messages, do: IO.puts("                     - #{m}")
  end

  defp label(:pass), do: "PASS"
  defp label(:fail), do: "FAIL"
  defp label(:indeterminate), do: "INDETERMINATE"

  defp baseline(%{baseline: nil}), do: "unavailable"
  defp baseline(%{baseline: b}), do: "HEAD (#{length(b.artifacts)} committed artifacts)"

  defp explain do
    IO.puts("Rule interpretations (REQ-005). core.yaml defines invariants by name only; see ASM-011.\n")

    for {id, text} <- Enum.sort(Invariants.interpretations()),
        do: IO.puts("#{id}  #{text}\n")
  end
end
