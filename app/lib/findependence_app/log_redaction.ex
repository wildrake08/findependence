defmodule FindependenceApp.LogRedaction do
  @moduledoc """
  WI-079 (the security assessment's FND-05): a crash report prints the crashing process's state, its last
  message, and the arguments of the function that failed. Here those are a member's decrypted household, their
  keys, or the passphrase they typed, and they reached the terminal on the shared device. This filter, added
  to the logger when the server starts, replaces the details of every crash report with one line naming only
  the kind of error, so nothing a member typed or can read is written. The app's own log lines (the refusal
  lines, which hold only a method, a path, a status, and a reason code) pass unchanged.
  """

  @id :findependence_withhold_crash_details

  @withheld "An error occurred; its details are withheld so that no household information is written to the log."

  @doc "Adds the filter to the logger (idempotent)."
  def install do
    _ = :logger.remove_primary_filter(@id)
    :ok = :logger.add_primary_filter(@id, {&filter/2, nil})
  end

  @doc false
  def filter(%{meta: meta, msg: msg} = event, _extra) do
    if crash?(meta, msg),
      do: %{
        event
        | msg: {:string, @withheld <> kind(meta)},
          meta: Map.drop(meta, [:crash_reason])
      },
      else: event
  end

  # a report from OTP (a process, GenServer, or supervisor that crashed), or any event carrying a crash reason
  defp crash?(meta, msg) do
    Map.has_key?(meta, :crash_reason) or match?([:otp | _], Map.get(meta, :domain)) or
      match?({:report, %{label: _}}, msg) or match?({:report, %{report: _}}, msg)
  end

  defp kind(%{crash_reason: {%{__struct__: mod}, _stack}}), do: " (#{inspect(mod)})"
  defp kind(%{crash_reason: {kind, _stack}}) when is_atom(kind), do: " (#{kind})"
  defp kind(_), do: ""
end
