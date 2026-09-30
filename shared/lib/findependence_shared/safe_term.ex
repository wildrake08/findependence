defmodule FindependenceShared.SafeTerm do
  @moduledoc """
  WI-079 (FND-02): decoding stored bytes into plain data only.

  `:erlang.binary_to_term(bin, [:safe])` refuses to create new atoms, but it still returns functions (and
  pids, ports, and references) encoded in the bytes, and a function reached by ordinary code such as
  `Enum.filter/2` is called. Everything this code stores is plain data: binaries, numbers, atoms, lists,
  tuples, and maps (MapSets are maps). `decode!/1` walks the decoded term and refuses the whole of it if any
  part is executable or process-bound, the same class `Plug.Crypto.non_executable_binary_to_term/2` refuses
  (this project does not depend on it), including inside map keys, improper lists, and tuples.
  """

  defmodule UnsafeTermError do
    @moduledoc "Stored bytes decoded to a term holding a function, pid, port, or reference."
    defexception message: "stored data holds a function, pid, port, or reference; refused"
  end

  @doc "Decodes `bin` with `[:safe]` and refuses any function, pid, port, or reference in it."
  def decode!(bin) when is_binary(bin) do
    term = :erlang.binary_to_term(bin, [:safe])
    check!(term)
    term
  end

  @doc "Raises `UnsafeTermError` if `term` holds a function, pid, port, or reference anywhere."
  def check!(term) do
    if plain?(term), do: :ok, else: raise(UnsafeTermError)
  end

  @doc "Whether `term` is plain data all the way down."
  def plain?(term) when is_list(term), do: plain_list?(term)

  def plain?(term) when is_tuple(term), do: plain_tuple?(term, tuple_size(term))

  def plain?(term) when is_map(term),
    do: Enum.all?(:maps.to_list(term), fn {k, v} -> plain?(k) and plain?(v) end)

  def plain?(term)
      when is_function(term) or is_pid(term) or is_port(term) or is_reference(term),
      do: false

  def plain?(_term), do: true

  # proper and improper lists alike, without building anything
  defp plain_list?([]), do: true
  defp plain_list?([h | t]) when is_list(t), do: plain?(h) and plain_list?(t)
  defp plain_list?([h | t]), do: plain?(h) and plain?(t)

  defp plain_tuple?(_t, 0), do: true
  defp plain_tuple?(t, n), do: plain?(:erlang.element(n, t)) and plain_tuple?(t, n - 1)
end
