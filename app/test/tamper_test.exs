defmodule FindependenceApp.TamperTest do
  @moduledoc """
  WI-020 self-review: attacks by a household member who can EDIT the vault file on a shared
  device (the plaintext structure is not authenticated). Each test states the attack and what an
  honest member's session must do.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.{Session, Vault}
  alias FindependenceShared.Crypto
  alias Findependence.Household

  @opts [iterations: 1_000, unsafe_test: true]

  defp vault, do: Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)

  defp act(v, m, fun) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
    end
  end

  # Can `m` open item `id`'s key with their own real secrets?
  defp can_open?(v, m, id) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)
    sealed = v.items[id].keys[m]

    sealed != nil and
      match?({:ok, _}, Crypto.open(s.pub, s.priv, sealed, Vault.aad(v.hid, {:item_key, id, m})))
  end

  describe "ACL tampering: attacker adds themselves as a reader in the plaintext structure" do
    test "an honest owner's later save does not seal the item key to them" do
      v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{note: "therapy"}))
      # cy edits the file: lists themselves as a grantee (no key, since they can't create one)
      v = update_in(v, [:items, "i1", :grantees], &Enum.sort(["cy" | &1]))
      refute can_open?(v, "cy", "i1")

      # ana, unaware, shares i1 with ben: an operation that re-seals the item's keys
      v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
      assert can_open?(v, "ben", "i1")
      refute can_open?(v, "cy", "i1"), "tampered reader list made an honest save grant access"
    end

    test "the honest session reports the tampering" do
      v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{note: "x"}))
      v = update_in(v, [:items, "i1", :owners], &Enum.sort(["cy" | &1]))
      {:ok, s} = Session.open(v, "ana", "pw-ana")
      assert {:reader_without_key, "i1", "cy"} in Session.integrity_issues(s)
    end

    test "ledger entries, old or new, are not sealed to a tampered-in owner either" do
      v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{note: "x"}))
      v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
      v = update_in(v, [:items, "i1", :owners], &Enum.sort(["cy" | &1]))

      # revoking needs no one else's consent, so it writes a NEW history entry despite the tampering
      v = act(v, "ana", &Household.revoke_grant(&1, "ana", "i1", "ben"))
      assert length(v.items["i1"].ledger) == 3
      refute Enum.any?(v.items["i1"].ledger, &Map.has_key?(&1.keys, "cy"))
    end
  end

  describe "key substitution: attacker replaces a member's public key with their own" do
    test "sealing uses the pinned key, so the attacker cannot open what is shared with the victim" do
      v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{note: "x"}))
      {evil_pub, evil_priv} = Crypto.keypair()
      v = put_in(v, [:members, "ben", :pub], evil_pub)

      # ana shares with "ben"; the key must NOT be openable with the attacker's substituted key
      v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
      sealed = v.items["i1"].keys["ben"]

      assert :error ==
               Crypto.open(
                 evil_pub,
                 evil_priv,
                 sealed,
                 Vault.aad(v.hid, {:item_key, "i1", "ben"})
               )
    end

    test "the substitution is reported to every other member at login" do
      {evil_pub, _} = Crypto.keypair()
      v = put_in(vault(), [:members, "ben", :pub], evil_pub)
      {:ok, s} = Session.open(v, "ana", "pw-ana")
      assert {:public_key_changed, "ben"} in Session.integrity_issues(s)
    end
  end

  test "an untampered vault reports no integrity issues" do
    v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{note: "x"}))
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
    {:ok, s} = Session.open(v, "ben", "pw-ben")
    assert Session.integrity_issues(s) == []
  end
end

defmodule FindependenceApp.TamperBannerTest do
  use ExUnit.Case, async: true
  alias FindependenceApp.Web.Html

  test "the interface warns when the file shows signs of tampering, and says nothing otherwise" do
    assert Html.integrity_banner([]) == ""
    banner = Html.integrity_banner([{:public_key_changed, "ben"}])
    assert banner =~ "may have been changed outside Findependence"
    assert banner =~ ~s(role="alert")
  end
end
