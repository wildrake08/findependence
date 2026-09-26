defmodule FindependenceApp.Secret do
  @moduledoc """
  Reads a passphrase without showing it on screen (WI-015).

  `:io.get_password/0` is not supported under `mix` (it returns `{:error, :enotsup}`, even on a
  terminal), and commands started from Erlang have no controlling terminal, so `stty < /dev/tty`
  fails. Instead:

  1. If stdin is a terminal device (found through `/proc/<pid>/fd/0` on Linux), turn its echo off
     with `stty -F <device>` and always turn it back on.
  2. Otherwise, when on a terminal without that access, keep overwriting the line while the user
     types, so typed characters don't stay visible (the approach the Hex package tool takes).
  3. Piped input (as in tests) is read as-is.

  Returns `{:ok, passphrase}` or `{:error, :no_input}`.
  """

  def read(prompt \\ "") do
    case :io.get_password() do
      chars when is_list(chars) ->
        {:ok, to_string(chars)}

      _ ->
        case terminal_device() do
          {:ok, dev} -> read_with_stty(dev, prompt)
          :none -> read_masked(prompt)
        end
    end
  end

  @doc false
  def terminal_device do
    case File.read_link("/proc/#{System.pid()}/fd/0") do
      {:ok, "/dev/pts/" <> _ = dev} -> {:ok, dev}
      {:ok, "/dev/tty" <> _ = dev} -> {:ok, dev}
      _ -> :none
    end
  end

  defp read_with_stty(dev, prompt) do
    if stty(dev, "-echo") do
      try do
        finish(IO.gets(prompt))
      after
        stty(dev, "echo")
        IO.write("\n")
      end
    else
      read_masked(prompt)
    end
  end

  # Overwrites the line every millisecond while waiting for input; harmless when input is piped.
  defp read_masked(prompt) do
    parent = self()
    ref = make_ref()
    masker = spawn_link(fn -> mask(prompt, parent, ref) end)
    line = IO.gets(prompt)
    send(masker, {:done, ref})

    receive do
      {:masked, ^ref} -> :ok
    end

    finish(line)
  end

  defp mask(prompt, parent, ref) do
    receive do
      {:done, ^ref} ->
        IO.write("\e[2K\r")
        send(parent, {:masked, ref})
    after
      1 ->
        IO.write("\e[2K\r" <> prompt)
        mask(prompt, parent, ref)
    end
  end

  defp finish(text) when is_binary(text), do: {:ok, String.trim_trailing(text, "\n")}
  defp finish(_), do: {:error, :no_input}

  defp stty(dev, setting) do
    match?({_, 0}, System.cmd("stty", ["-F", dev, setting], stderr_to_stdout: true))
  rescue
    _ -> false
  end
end
