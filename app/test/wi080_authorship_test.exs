defmodule FindependenceApp.WI080AuthorshipTest do
  @moduledoc """
  WI-080 (REV-107; ASSESS-001 FND-04 as the assessment recommended): a balance or an item's details count only
  if their author owned the item when they were written. Before, anyone the history showed as having owned the
  item at any time was accepted, so a former co-owner who can edit the vault file could add a balance, signed
  with their own valid key, that the remaining owner's view accepted as genuine.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.{Session, Vault}
  alias FindependenceShared.{Crypto, Envelope}
  alias Findependence.{Balances, Household}

  @opts [iterations: 1_000, unsafe_test: true]

  defp session(v, m) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)
    s
  end

  defp act(v, m, fun) do
    s = session(v, m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
      {:error, _} = e -> flunk("#{m}: #{inspect(e)}")
    end
  end

  defp reading(on, balance), do: %{on: on, balance: balance, rate_bp: 600, min_payment: 30_000}

  # Ana and Ben co-own the car loan (`joint`); Ben adds a balance while he owns it, then gives it up.
  defp joint do
    Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}], @opts)
    |> act("ana", &Balances.add_debt(&1, "ana", "loan", "Car loan", :loan))
    |> act("ana", &Household.propose_owners(&1, "ana", "loan", ["ana", "ben"]))
  end

  defp after_leaving(joint) do
    joint
    |> act("ana", &Balances.add_reading(&1, "ana", "loan", reading("2026-08-01", 1_200_000)))
    |> act("ben", &Balances.add_reading(&1, "ben", "loan", reading("2026-09-01", 1_150_000)))
    |> act("ben", &Household.relinquish(&1, "ben", "loan"))
  end

  defp car_loan, do: after_leaving(joint())

  # Ben signs with his own, valid, pinned signing key
  defp ben_signs(v, box, ctx) do
    {_, signing} = Crypto.signing_keypair(session(v, "ben").priv)

    Map.merge(box, %{
      a: "ben",
      s: Crypto.sign(signing, Envelope.signed_message(v.hid, ctx, "ben", box))
    })
  end

  test "a balance written while its author owned the item is accepted after they give it up" do
    s = session(car_loan(), "ana")
    assert Session.integrity_issues(s) == []

    assert {:ok, [%{balance: 1_200_000}, %{balance: 1_150_000}]} =
             Balances.readings(s.household, "ana", "loan")
  end

  test "a former co-owner's new balance, signed with their own valid key, is reported and not shown" do
    v = car_loan()
    seq = length(v.items["loan"].readings) + 1
    rk = Crypto.random_key()
    fake = Map.merge(reading("2026-09-30", 0), %{seq: seq, by: "ben"})
    ctx = {:reading, "loan", seq}
    box = Crypto.encrypt(rk, Vault.encode(fake), Vault.aad(v.hid, ctx))

    forged = %{
      seq: seq,
      box: ben_signs(v, box, ctx),
      keys: %{
        "ana" =>
          Crypto.seal(
            v.members["ana"].pub,
            rk,
            Vault.aad(v.hid, {:reading_key, "loan", seq, "ana"})
          )
      }
    }

    v = update_in(v, [:items, "loan", :readings], &(&1 ++ [forged]))
    s = session(v, "ana")

    assert {:signer_not_entitled, "loan", {:reading, seq}} in Session.integrity_issues(s)
    # the latest balance shown is not the forged "paid off" one
    refute match?(%{balance: 0}, Balances.latest(s.household, "ana", "loan"))
  end

  test "a former co-owner can't rewrite the item's details, though they still know its key" do
    joint = joint()
    # the item key Ben could read while he owned the loan, and kept
    key = session(joint, "ben").item_keys["loan"]
    v = after_leaving(joint)
    ctx = {:content, "loan"}

    box =
      Crypto.encrypt(
        key,
        Vault.encode(%{kind: :debt, label: "Car loan (paid off)", debt_type: :loan}),
        Vault.aad(v.hid, ctx)
      )

    v = put_in(v, [:items, "loan", :content], ben_signs(v, box, ctx))
    s = session(v, "ana")

    assert {:signer_not_entitled, "loan", :content} in Session.integrity_issues(s)
    refute s.household.items["loan"].attrs[:label] == "Car loan (paid off)"
  end
end
