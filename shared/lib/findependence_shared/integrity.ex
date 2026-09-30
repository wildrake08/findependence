defmodule FindependenceShared.Integrity do
  @moduledoc """
  What a member's view found wrong with the stored household, and which parts of an item were saved before
  signing began (WI-079), for the web layers of both forms, over a scope built from the member's session
  (`FindependenceShared.Scope.new/1`). A read scope without a session has nothing to report.
  """

  alias FindependenceShared.{Envelope, Scope}

  @doc "The integrity issues of the scope's view (`FindependenceShared.Envelope.integrity_issues/1`)."
  def issues(%Scope{session: %{integrity: _} = view}), do: Envelope.integrity_issues(view)
  def issues(%Scope{}), do: []

  @doc "Which parts of item `id` were accepted as saved before signing began: `:content`, `:history`, `:readings`."
  def written_before_signing(%Scope{session: %{} = view}, id),
    do: Envelope.written_before_signing(view, id)

  def written_before_signing(%Scope{}, _id), do: []
end
