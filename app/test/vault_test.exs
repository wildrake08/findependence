defmodule FindependenceApp.VaultTest do
  use ExUnit.Case, async: true

  alias FindependenceApp.{Crypto, Session, Vault}
  alias Findependence.{Alignment, Exit, Household, Ledger, View}

  @opts [iterations: 1_000, unsafe_test: true]
  @members ["ana", "ben", "cy"]

  defp vault, do: Vault.create(Enum.map(@members, &{&1, "pw-" <> &1}), @opts)

  # Runs one core operation as `member` through an encrypted session; returns the new vault.
  defp act(vault, member, fun) do
    {:ok, s} = Session.open(vault, member, "pw-" <> member)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
      {:error, _} = e -> flunk("#{member}: #{inspect(e)}")
    end
  end

  defp view(vault, member) do
    {:ok, s} = Session.open(vault, member, "pw-" <> member)
    s.household
  end

  # Every sealed key in the vault a member could open with their own secrets.
  defp openable(vault, member) do
    {:ok, s} = Session.open(vault, member, "pw-" <> member)

    for {id, rec} <- vault.items,
        {r, sealed} <- rec.keys,
        match?(
          {:ok, _},
          Crypto.open(s.pub, s.priv, sealed, Vault.aad(vault.hid, {:item_key, id, r}))
        ),
        do: id
  end

  test "REQ-118: a wrong passphrase or unknown member fails and reveals nothing" do
    v = vault()
    assert {:error, :bad_credentials} = Session.open(v, "ana", "wrong")
    assert {:error, :bad_credentials} = Session.open(v, "zed", "pw-zed")
    assert {:ok, %Session{}} = Session.open(v, "ana", "pw-ana")
  end

  test "the vault file is readable by its owner only" do
    path = Path.join(System.tmp_dir!(), "fv-perm-#{System.unique_integer([:positive])}.vault")
    on_exit(fn -> File.rm(path) end)
    Vault.write!(vault(), path)
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
  end

  test "REQ-118: the default vault uses at least 600,000 PBKDF2 iterations" do
    assert Vault.create([{"a", "p"}], unsafe_test: false, iterations: Crypto.min_iterations()).iterations >=
             600_000

    assert_raise ArgumentError, fn -> Vault.create([{"a", "p"}], iterations: 1_000) end
  end

  test "REQ-119: only readers can decrypt an item; a grant adds a reader and revocation removes one" do
    v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{note: "rent", amount: 100}))
    assert {:ok, %{attrs: %{note: "rent"}}} = View.get(view(v, "ana"), "ana", "i1")
    assert view(v, "ben").items["i1"].attrs == %{}
    assert openable(v, "ben") == []

    v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
    assert {:ok, %{attrs: %{note: "rent"}}} = View.get(view(v, "ben"), "ben", "i1")

    v = act(v, "ana", &Household.revoke_grant(&1, "ana", "i1", "ben"))
    assert view(v, "ben").items["i1"].attrs == %{}
    assert openable(v, "ben") == []
    assert Map.keys(v.items["i1"].keys) == ["ana"]
  end

  test "REQ-120: ledger entries are readable by owners only, and re-sealed for new owners" do
    v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{note: "x"}))
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "cy"))
    assert {:error, :not_found} = Ledger.read(view(v, "cy"), "cy", "i1")
    assert Enum.all?(view(v, "cy").ledger["i1"], &(&1 == :sealed))

    v = act(v, "ana", &Household.propose_owners(&1, "ana", "i1", ["ana", "ben"]))
    {:ok, entries} = Ledger.read(view(v, "ben"), "ben", "i1")
    assert Enum.map(entries, & &1.event) == [:created, :granted, :owners_changed]
  end

  test "REQ-119/120 with REQ-115: a prospective joiner can read a value only after every owner consents" do
    v = act(vault(), "ana", &Alignment.add_value(&1, "ana", "v1", "a home that feels safe"))
    v = act(v, "ana", &Household.propose_owners(&1, "ana", "v1", ["ana", "ben"]))
    v = act(v, "ben", &Household.consent(&1, "ben", 1))
    # ana and ben now share v1; ana proposes adding cy
    v = act(v, "ana", &Household.propose_owners(&1, "ana", "v1", ["ana", "ben", "cy"]))
    assert Household.pending(view(v, "cy"), "cy") == []
    assert openable(v, "cy") == []

    v = act(v, "ben", &Household.consent(&1, "ben", 2))
    assert [%{attrs: %{label: "a home that feels safe"}}] = Household.pending(view(v, "cy"), "cy")
    v = act(v, "cy", &Household.consent(&1, "cy", 2))
    {:ok, entries} = Ledger.read(view(v, "cy"), "cy", "v1")
    assert length(entries) == 3
  end

  test "REQ-121: links and deletion records are private to their member" do
    v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{amount: 5}))
    v = act(v, "ana", &Alignment.add_value(&1, "ana", "v1", "learning"))
    v = act(v, "ana", &Alignment.link(&1, "ana", "i1", "v1"))
    v = act(v, "ana", &Exit.delete(&1, "ana", "v1"))

    assert Ledger.deletions(view(v, "ana"), "ana") == [%{seq: 1, item_id: "v1"}]
    assert Ledger.deletions(view(v, "ben"), "ben") == []
    assert Map.keys(v.personal) == ["ana"]
  end

  test "REQ-122: no attribute, label, link, or ledger detail appears in plaintext in the stored file" do
    path = Path.join(System.tmp_dir!(), "fv-#{System.unique_integer([:positive])}.vault")
    on_exit(fn -> File.rm(path) end)

    v =
      act(
        vault(),
        "ana",
        &Household.add_item(&1, "ana", "i1", %{
          note: "MARK-therapy-copay",
          amount: 4242,
          unit: :cents
        })
      )

    v = act(v, "ana", &Alignment.add_value(&1, "ana", "v1", "MARK-label-freedom"))
    v = act(v, "ana", &Alignment.link(&1, "ana", "i1", "v1"))
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
    Vault.write!(v, path)

    bytes = File.read!(path)

    for marker <- [
          "MARK-therapy-copay",
          "MARK-label-freedom",
          "note",
          "label",
          "granted",
          "owners_changed"
        ],
        do: refute(String.contains?(bytes, marker), "plaintext #{marker} in vault file")

    # The ledger detail key `grantee`, as opposed to the structural field `grantees` (ASM-020).
    refute Regex.match?(~r/grantee(?!s)/, bytes), "plaintext ledger detail in vault file"

    assert View.get(view(Vault.read!(path), "ben"), "ben", "i1") |> elem(1) |> Map.get(:attrs) ==
             %{note: "MARK-therapy-copay", amount: 4242, unit: :cents}
  end

  test "REQ-125: withdrawing a value invitation removes the access the joiner was given in advance" do
    v = act(vault(), "ana", &Alignment.add_value(&1, "ana", "v1", "a home that feels safe"))
    v = act(v, "ana", &Household.propose_owners(&1, "ana", "v1", ["ana", "ben"]))
    assert "v1" in openable(v, "ben")
    assert [%{attrs: %{label: _}}] = Household.pending(view(v, "ben"), "ben")

    v = act(v, "ana", &Household.withdraw(&1, "ana", 1))
    assert openable(v, "ben") == []
    assert Household.pending(view(v, "ben"), "ben") == []
    assert Map.keys(v.items["v1"].keys) == ["ana"]
    assert Enum.all?(v.items["v1"].ledger, &(Map.keys(&1.keys) == ["ana"]))
  end

  test "departure removes the leaver's keys and personal record" do
    v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{}))
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "cy"))
    v = act(v, "cy", &Exit.leave(&1, "cy"))
    refute Map.has_key?(v.members, "cy")
    assert Map.keys(v.items["i1"].keys) == ["ana"]
    {:ok, entries} = Ledger.read(view(v, "ana"), "ana", "i1")
    assert %{event: :grantee_departed} = List.last(entries)
  end
end
