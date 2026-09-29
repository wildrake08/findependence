defmodule FindependenceApp.CryptoPropertiesTest do
  @moduledoc """
  WI-055 (VV-001 F-05): the encryption properties VV-001 found untested, checked against known answers and
  against the bytes of the stored file. REQ-118, REQ-119, REQ-121, REQ-122, REQ-133.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.{Session, Vault}
  alias FindependenceShared.Crypto
  alias Findependence.{Alignment, Balances, Exit, Household}

  @opts [iterations: 1_000, unsafe_test: true]

  defp vault, do: Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)

  defp act(v, m, fun) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
      {:error, _} = e -> flunk("#{m}: #{inspect(e)}")
    end
  end

  defp session(v, m) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)
    s
  end

  # The bytes that would be written to disk.
  defp file_bytes(v) do
    path = Path.join(System.tmp_dir!(), "fv-props-#{System.unique_integer([:positive])}.vault")
    Vault.write!(v, path)
    bytes = File.read!(path)
    File.rm(path)
    bytes
  end

  defp absent?(bytes, pattern), do: :binary.match(bytes, pattern) == :nomatch
  defp strip(<<131, rest::binary>>), do: rest

  describe "REQ-118: passphrase key derivation" do
    # RFC 7914 section 11 test vectors for PBKDF2-HMAC-SHA256; derive_key returns the first 32 bytes.
    test "derive_key is PBKDF2-HMAC-SHA256 (RFC 7914 known answers)" do
      assert Crypto.derive_key("passwd", "salt", 1, unsafe_test: true) ==
               Base.decode16!("55AC046E56E3089FEC1691C22544B605F94185216DDE0465E68B9D57C20DACBC")

      assert Crypto.derive_key("Password", "NaCl", 80_000, unsafe_test: true) ==
               Base.decode16!("4DDCD8F60B98BE21830CEE5EF22701F9641A4418D04C0414AEFF08876B34AB56")
    end

    test "each member's secret on disk opens under PBKDF2-HMAC-SHA256 of their passphrase, and only that" do
      v = vault()

      for m <- ["ana", "ben", "cy"] do
        %{salt: salt, secret: box} = v.members[m]
        aad = Vault.aad(v.hid, {:member, m})
        kek = :crypto.pbkdf2_hmac(:sha256, "pw-" <> m, salt, v.iterations, 32)
        assert {:ok, _} = Crypto.decrypt(kek, box, aad)
        wrong = :crypto.pbkdf2_hmac(:sha256, "pw-" <> m, salt, v.iterations + 1, 32)
        assert Crypto.decrypt(wrong, box, aad) == :error
      end
    end

    test "every member has a 16-byte salt, different from every other member's and vault's" do
      salts = for v <- [vault(), vault()], {_, %{salt: s}} <- v.members, do: s
      assert Enum.all?(salts, &(byte_size(&1) == 16))
      assert length(Enum.uniq(salts)) == length(salts)
    end

    test "no private key or personal key appears in the stored file" do
      v = act(vault(), "ana", &Household.add_item(&1, "ana", "i1", %{amount: 5}))
      bytes = file_bytes(v)

      for m <- ["ana", "ben", "cy"] do
        s = session(v, m)
        assert absent?(bytes, s.priv), "#{m}'s private key is in the file"
        assert absent?(bytes, s.personal), "#{m}'s personal key is in the file"
      end
    end
  end

  test "REQ-119: each item has its own key, and one item's key can't open another's content" do
    v =
      Enum.reduce(["i1", "i2", "i3"], vault(), fn id, v ->
        act(v, "ana", &Household.add_item(&1, "ana", id, %{amount: 5}))
      end)

    keys = session(v, "ana").item_keys
    assert map_size(keys) == 3
    assert length(Enum.uniq(Map.values(keys))) == 3

    for {id, k} <- keys, {other, _} <- keys, other != id do
      assert Crypto.decrypt(k, v.items[other].content, Vault.aad(v.hid, {:content, other})) ==
               :error
    end
  end

  describe "REQ-121 and REQ-122: personal records and what reaches the file" do
    test "a deletion record, an amount, a date, and a frequency are not in the file in plaintext" do
      v =
        vault()
        |> act(
          "ana",
          &Household.add_item(&1, "ana", "i1", %{
            amount: 987_654_321,
            on: "2031-07-19",
            frequency: {:every, 7, :week}
          })
        )
        |> act("ana", &Household.add_item(&1, "ana", "MARK-deleted-item", %{amount: 1}))
        |> act("ana", &Exit.delete(&1, "ana", "MARK-deleted-item"))

      bytes = file_bytes(v)
      assert absent?(bytes, "MARK-deleted-item")
      assert absent?(bytes, "2031-07-19")
      assert absent?(bytes, <<98, 987_654_321::32>>)

      # a term inside a stored plaintext would appear as its encoding without the leading version byte
      assert absent?(bytes, strip(:erlang.term_to_binary({:every, 7, :week})))
      # the record is there, readable by Ana
      assert [%{item_id: "MARK-deleted-item"}] =
               Findependence.Ledger.deletions(session(v, "ana").household, "ana")
    end

    test "another member's secrets can't open a member's personal record (links and deletions)" do
      v =
        vault()
        |> act("ana", &Household.add_item(&1, "ana", "i1", %{amount: 5}))
        |> act("ana", &Alignment.add_value(&1, "ana", "v1", "learning"))
        |> act("ana", &Alignment.link(&1, "ana", "i1", "v1"))

      # the link itself (item and value together) is not in the file in plaintext
      assert absent?(file_bytes(v), strip(:erlang.term_to_binary({"i1", "v1"})))
      box = v.personal["ana"]

      assert {:ok, _} =
               Crypto.decrypt(
                 session(v, "ana").personal,
                 box,
                 Vault.aad(v.hid, {:personal, "ana"})
               )

      for m <- ["ben", "cy"] do
        s = session(v, m)
        assert Crypto.decrypt(s.personal, box, Vault.aad(v.hid, {:personal, "ana"})) == :error
        assert Crypto.decrypt(s.personal, box, Vault.aad(v.hid, {:personal, m})) == :error
      end
    end
  end

  describe "REQ-133: reading keys" do
    defp account(v) do
      v
      |> act("ana", &Balances.add_account(&1, "ana", "chk", "Checking", :checking))
      |> act(
        "ana",
        &Balances.add_reading(&1, "ana", "chk", %{on: "2026-08-01", balance: 100_000})
      )
      |> act("ana", &Balances.add_reading(&1, "ana", "chk", %{on: "2026-09-01", balance: 90_000}))
      |> act("ana", &Balances.add_reading(&1, "ana", "chk", %{on: "2026-09-27", balance: 85_000}))
    end

    test "each reading has its own key" do
      keys = session(account(vault()), "ana").reading_keys
      assert map_size(keys) == 3
      assert length(Enum.uniq(Map.values(keys))) == 3
    end

    test "a member who becomes an owner gets every earlier reading's key; one who relinquishes loses them" do
      v =
        account(vault())
        |> act("ana", &Household.propose_owners(&1, "ana", "chk", ["ana", "ben"]))

      assert Enum.sort(Map.keys(session(v, "ben").reading_keys)) == [
               {"chk", 1},
               {"chk", 2},
               {"chk", 3}
             ]

      assert Enum.all?(v.items["chk"].readings, &Map.has_key?(&1.keys, "ben"))

      v = act(v, "ben", &Household.relinquish(&1, "ben", "chk"))
      refute Enum.any?(v.items["chk"].readings, &Map.has_key?(&1.keys, "ben"))
      assert session(v, "ben").reading_keys == %{}
    end
  end
end
