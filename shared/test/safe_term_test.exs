defmodule FindependenceShared.SafeTermTest do
  @moduledoc "WI-079 (FND-02): stored bytes decode to plain data only, in both forms."
  use ExUnit.Case, async: true

  alias FindependenceShared.{Envelope, SafeTerm}

  @doc false
  def called(pid), do: send(pid, :called)

  test "plain data decodes as it was" do
    for term <- [
          %{v: 1, items: %{"i" => %{owners: ["a"], keys: %{}}}},
          [1, 2 | 3],
          {:grant, "b"},
          MapSet.new(["a", "b"]),
          <<1, 2, 3>>,
          -7,
          1.5
        ],
        do: assert(Envelope.decode(:erlang.term_to_binary(term)) == term)
  end

  test "a function, pid, port, or reference anywhere is refused, and a function is never called" do
    me = self()
    local = fn -> called(me) end
    {:ok, port} = :gen_udp.open(0)
    on_exit(fn -> :gen_udp.close(port) end)

    for bad <- [
          local,
          &__MODULE__.called/1,
          %{member_order: local},
          %{local => 1},
          [1 | local],
          {1, {2, [self()]}},
          [make_ref()],
          %{a: MapSet.new([port])}
        ] do
      assert_raise SafeTerm.UnsafeTermError, fn ->
        Envelope.decode(:erlang.term_to_binary(bad))
      end
    end

    refute_received :called
  end

  test "an unknown atom is still refused ([:safe])" do
    bin = <<131, 119, 20, "wi079_never_an_atom_">>
    assert_raise ArgumentError, fn -> Envelope.decode(bin) end
  end
end
