defmodule FindependenceApp.Portability do
  @moduledoc """
  Domain context Portability (DP-001 section 2; CAP-009, MEC-012, MEC-022): the member's export, and
  bringing an export in: checked, previewed, then confirmed (REQ-155..159, REQ-164, REQ-169).
  """

  alias FindependenceApp.{Operation, Scope}
  alias Findependence.{Exit, Import}

  @doc "What the member takes away (REQ-169)."
  def export(%Scope{member: m, household: h}), do: Exit.export(h, m)

  @doc """
  Checks a file before anything is saved (REQ-157, REQ-159). Returns `{:ok, %{bundle:, fingerprint:,
  summary:}}` for the preview, or `{:error, category, problem}` with problem `{:already_imported, on}`,
  `:not_json`, or `{:problems, list}`. The size limit is the transport's, checked before reading.
  """
  def check(%Scope{member: m, household: h}, bytes) do
    fingerprint = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    with {:new, nil} <- {:new, Import.imported_on(h, m, fingerprint)},
         {:json, {:ok, data}} <- {:json, decode_json(bytes)},
         {:checked, {:ok, bundle}} <- {:checked, Import.check(data)} do
      {:ok, %{bundle: bundle, fingerprint: fingerprint, summary: Import.summary(bundle)}}
    else
      {:new, on} -> {:error, :conflict, {:already_imported, on}}
      {:json, _} -> {:error, :validation, :not_json}
      {:checked, {:error, problems}} -> {:error, :validation, {:problems, problems}}
    end
  end

  # The file is untrusted: any failure to decode is "not an export", never a crash.
  defp decode_json(bytes) do
    {:ok, :json.decode(bytes)}
  rescue
    _ -> :error
  end

  @doc "Brings a checked file in as new entries the member owns alone (REQ-156)."
  def bring_in(%Scope{member: m} = scope, bundle, fingerprint, today),
    do:
      Operation.run(
        scope,
        &Import.apply(&1, m, bundle, fn -> Operation.new_id() end, fingerprint, today)
      )

  @doc "The saved file's data, format version 2 (REQ-155)."
  defdelegate to_data(export), to: Import
end
