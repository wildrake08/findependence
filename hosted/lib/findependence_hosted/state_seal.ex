defmodule FindependenceHosted.StateSeal do
  @moduledoc """
  A code over a household's records (REQ-198, WI-085; ASSESS-002 FND-201): HMAC-SHA256, under a key held outside
  the database (HOUSEHOLD_STATE_KEY), of the household's identifier and a canonical encoding of everything
  `FindependenceHosted.Domain` loads for it (members, every item's owners, grantees, content, sealed keys, history
  and readings, the requests and their agreements, the request counter, and the personal records) and of the
  members' display names. Members' public keys are left out: pinning already detects a changed one (REV-099 G4).

  The service writes the code at every change and checks it at every read, so rows changed by anyone who can
  write only the database (a leaked database password, a tampered backup, an administrator who isn't the
  operator) are detected and the household is refused, not acted on. It does not detect a whole earlier copy
  of a household restored with its own code (rollback), nor anything the operator does through the service:
  the operator is trusted (REV-111).

  The encoding is this module's own, not the external term format, so it doesn't change with the runtime.
  """

  @doc """
  The code for a household's loaded state, its members' display names, and its change counter (WI-086; the
  counter is also kept outside the database, `FindependenceHosted.StateLedger`).
  """
  def mac(household_id, version, state, names) do
    :crypto.mac(:hmac, :sha256, key(), [
      "findependence household state v2",
      enc(Ecto.UUID.dump!(household_id)),
      enc(version),
      enc(subject(state, names))
    ])
  end

  @doc "Whether `stored` is the code for this state, compared in constant time."
  def valid?(household_id, version, state, names, stored) when is_binary(stored),
    do: Plug.Crypto.secure_compare(mac(household_id, version, state, names), stored)

  def valid?(_household_id, _version, _state, _names, _stored), do: false

  # what the code covers: the loaded state without public keys, and the display names
  defp subject(state, names) do
    members = Map.new(state.members, fn {m, _keys} -> {m, true} end)
    {Map.put(state, :members, members), names}
  end

  @doc false
  # A canonical, self-delimiting encoding: each value is a type tag and a length-prefixed body; map entries
  # and set members are sorted by their own encoding.
  def enc(b) when is_binary(b), do: frame("b", b)
  def enc(i) when is_integer(i), do: frame("i", Integer.to_string(i))
  def enc(a) when is_atom(a), do: frame("a", Atom.to_string(a))

  def enc(%MapSet{} = s),
    do: frame("s", s |> Enum.map(&enc/1) |> Enum.sort() |> IO.iodata_to_binary())

  def enc(%{} = m) do
    body =
      m
      |> Map.to_list()
      |> Enum.map(fn {k, v} -> [enc(k), enc(v)] |> IO.iodata_to_binary() end)
      |> Enum.sort()

    frame("m", IO.iodata_to_binary(body))
  end

  def enc(l) when is_list(l), do: frame("l", l |> Enum.map(&enc/1) |> IO.iodata_to_binary())
  def enc(t) when is_tuple(t), do: frame("t", t |> Tuple.to_list() |> enc())

  defp frame(tag, body), do: [tag, <<byte_size(body)::32>>, body] |> IO.iodata_to_binary()

  defp key, do: Application.fetch_env!(:findependence_hosted, :household_state_key)
end

defmodule FindependenceHosted.HouseholdTampered do
  @moduledoc """
  Raised when a household's records don't carry a valid code (REQ-198): they were changed other than through
  the service, so nothing is shown or changed until the operator restores them.
  """
  defexception [
    :household_id,
    plug_status: 409,
    message: "a household's records were changed outside the service"
  ]
end
