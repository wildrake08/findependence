defmodule FindependenceShared.Contract.Form do
  @moduledoc """
  REQ-188 AC-1 (WI-074): what a form provides so one set of contract tests runs the shared contexts against it.
  Each form's test suite implements this and uses the contract cases (`FindependenceShared.Contract.*`).

  A household's members are given by short names ("ana", "ben"); each form maps a name to its own member id
  (the local form uses the name itself; the hosted form, a membership id).
  """

  @typedoc "A form's handle on one member of a test household."
  @type handle :: term()

  @doc "Makes a household with these members and returns a handle per name. Runs in the test process."
  @callback household([String.t()]) :: %{String.t() => handle()}

  @doc "A scope that can read and change, for the member, on the latest state."
  @callback scope(handle()) :: FindependenceShared.Scope.t()

  @doc "The member's id inside the domain rules."
  @callback member(handle()) :: String.t()

  @doc "The household's sealed state as stored, in the local vault's shape (FindependenceShared.Envelope)."
  @callback stored(handle()) :: map()

  @doc "Every stored value of the household, as binaries: the vault file, or every column of every row."
  @callback stored_bytes(handle()) :: [binary()]

  @doc "Whether this form keeps the household with every member from the start (the local form's setup)."
  @callback fixed_membership?() :: boolean()
end
