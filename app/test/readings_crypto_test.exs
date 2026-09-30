defmodule FindependenceApp.ReadingsCryptoTest do
  @moduledoc """
  CAP-010 readings at the encryption layer (REQ-132, REQ-133, CP-013 A), checked against the file
  itself: who holds a key to which reading, after sharing, a new reading, stopping sharing, and
  tampering with the plaintext reader lists.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.{Session, Vault}
  alias FindependenceShared.Crypto
  alias Findependence.{Balances, Household}

  @opts [iterations: 1_000, unsafe_test: true]

  defp vault, do: Vault.create([{"mom", "pw-mom"}, {"dad", "pw-dad"}, {"kid", "pw-kid"}], @opts)

  defp act(v, m, fun) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
    end
  end

  defp view(v, m) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)
    s
  end

  # Can `m` open reading `seq` of `id` with their own secrets, from the file alone?
  defp can_open?(v, m, id, seq) do
    s = view(v, m)
    r = Enum.find(v.items[id].readings, &(&1.seq == seq))
    sealed = r && r.keys[m]

    sealed != nil and
      match?(
        {:ok, _},
        Crypto.open(s.pub, s.priv, sealed, Vault.aad(v.hid, {:reading_key, id, seq, m}))
      )
  end

  defp reading(on, bal), do: %{on: on, balance: bal}

  # Dad owns a card; two readings; shares it with Mom.
  defp card do
    vault()
    |> act("dad", &Balances.add_debt(&1, "dad", "visa", "Visa", :card))
    |> act(
      "dad",
      &Balances.add_reading(&1, "dad", "visa", %{
        on: "2026-08-27",
        balance: 540_000,
        rate_bp: 2199,
        min_payment: 16_000
      })
    )
    |> act(
      "dad",
      &Balances.add_reading(&1, "dad", "visa", %{
        on: "2026-09-27",
        balance: 520_000,
        rate_bp: 2199,
        min_payment: 15_000
      })
    )
    |> act("dad", &Household.propose_grant(&1, "dad", "visa", "mom"))
  end

  test "owners hold every reading's key; someone it's shared with only the latest; nobody else any" do
    v = card()
    assert can_open?(v, "dad", "visa", 1) and can_open?(v, "dad", "visa", 2)
    refute can_open?(v, "mom", "visa", 1)
    assert can_open?(v, "mom", "visa", 2)
    refute can_open?(v, "kid", "visa", 1) or can_open?(v, "kid", "visa", 2)

    assert Balances.readings(view(v, "mom").household, "mom", "visa") ==
             {:ok,
              [
                %{
                  seq: 2,
                  by: "dad",
                  on: "2026-09-27",
                  balance: 520_000,
                  rate_bp: 2199,
                  min_payment: 15_000
                }
              ]}

    assert {:ok, [_, _]} = Balances.readings(view(v, "dad").household, "dad", "visa")
  end

  test "when a newer reading arrives, the grantee's key to the old latest is removed" do
    v =
      act(
        card(),
        "dad",
        &Balances.add_reading(&1, "dad", "visa", %{
          on: "2026-10-27",
          balance: 500_000,
          rate_bp: 2199,
          min_payment: 15_000
        })
      )

    refute Map.has_key?(Enum.at(v.items["visa"].readings, 1).keys, "mom")
    assert can_open?(v, "mom", "visa", 3)
    refute can_open?(v, "mom", "visa", 2)
  end

  test "a joint owner can add a reading and the other owner can read every reading" do
    v =
      vault()
      |> act("mom", &Balances.add_account(&1, "mom", "chk", "Joint checking", :checking))
      |> act("mom", &Household.propose_owners(&1, "mom", "chk", ["mom", "dad"]))
      |> act("dad", &Balances.add_reading(&1, "dad", "chk", reading("2026-09-27", 124_000)))
      |> act("mom", &Balances.add_reading(&1, "mom", "chk", reading("2026-09-28", 98_000)))

    for m <- ["mom", "dad"], seq <- [1, 2], do: assert(can_open?(v, m, "chk", seq))
    assert Session.integrity_issues(view(v, "mom")) == []
  end

  test "someone who stops being able to see it loses their keys, and never gets later readings" do
    v = card()
    old_copy = v
    v = act(v, "dad", &Household.revoke_grant(&1, "dad", "visa", "mom"))
    refute can_open?(v, "mom", "visa", 2)

    v =
      act(
        v,
        "dad",
        &Balances.add_reading(&1, "dad", "visa", %{
          on: "2026-10-27",
          balance: 1,
          rate_bp: 0,
          min_payment: 0
        })
      )

    refute can_open?(v, "mom", "visa", 3)
    # even with a copy of the file from before, Mom's secrets hold no key to the new reading
    assert Enum.all?(v.items["visa"].readings, &(not Map.has_key?(&1.keys, "mom")))
    assert old_copy.items["visa"].readings |> length() == 2
  end

  test "a reader written into the file by editing it is never sealed a reading, and it's reported" do
    v = card()
    # the kid edits the file to list themselves as a grantee
    v = update_in(v, [:items, "visa", :grantees], &Enum.sort(["kid" | &1]))

    v =
      act(
        v,
        "dad",
        &Balances.add_reading(&1, "dad", "visa", %{
          on: "2026-10-27",
          balance: 2,
          rate_bp: 0,
          min_payment: 0
        })
      )

    refute can_open?(v, "kid", "visa", 3)

    assert {:reader_without_reading_key, "visa", "kid"} in Session.integrity_issues(
             view(v, "dad")
           )
  end

  test "readings are not in the file in plaintext" do
    path = Path.join(System.tmp_dir!(), "fv-readings-#{System.unique_integer([:positive])}.vault")
    on_exit(fn -> File.rm(path) end)

    v =
      vault()
      |> act("mom", &Balances.add_account(&1, "mom", "chk", "Checking", :checking))
      |> act("mom", &Balances.add_reading(&1, "mom", "chk", reading("2031-07-19", 7_777_777)))

    Vault.write!(v, path)
    bytes = File.read!(path)
    refute bytes =~ "2031-07-19"
    refute bytes =~ "Checking"
    refute :binary.match(bytes, :erlang.term_to_binary(7_777_777)) != :nomatch
  end
end
