defmodule FindependenceApp.CryptoTest do
  use ExUnit.Case, async: true
  alias FindependenceShared.Crypto

  defp hex(s), do: Base.decode16!(s, case: :lower)

  test "HKDF-SHA256 matches RFC 5869 test case 1" do
    ikm = :binary.copy(<<0x0B>>, 22)
    salt = hex("000102030405060708090a0b0c")
    info = hex("f0f1f2f3f4f5f6f7f8f9")

    assert Crypto.hkdf_extract(salt, ikm) ==
             hex("077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5")

    assert Crypto.hkdf(ikm, salt, info, 42) ==
             hex(
               "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
             )
  end

  test "AES-GCM round-trips and rejects a wrong key, wrong associated data, and tampering" do
    k = Crypto.random_key()
    box = Crypto.encrypt(k, "secret", "aad")
    assert {:ok, "secret"} = Crypto.decrypt(k, box, "aad")
    assert :error = Crypto.decrypt(Crypto.random_key(), box, "aad")
    assert :error = Crypto.decrypt(k, box, "other")

    assert :error =
             Crypto.decrypt(
               k,
               %{box | c: :crypto.exor(box.c, :binary.copy(<<1>>, byte_size(box.c)))},
               "aad"
             )
  end

  test "seal opens only with the recipient's private key" do
    {pa, sa} = Crypto.keypair()
    {pb, sb} = Crypto.keypair()
    sealed = Crypto.seal(pa, "item key", "ctx")
    assert {:ok, "item key"} = Crypto.open(pa, sa, sealed, "ctx")
    assert :error = Crypto.open(pb, sb, sealed, "ctx")
    assert :error = Crypto.open(pa, sa, sealed, "other ctx")
  end

  test "key derivation refuses fewer than 600,000 iterations unless explicitly unsafe" do
    assert Crypto.min_iterations() >= 600_000
    assert_raise ArgumentError, fn -> Crypto.derive_key("pw", Crypto.random_salt(), 1000) end
    assert byte_size(Crypto.derive_key("pw", Crypto.random_salt(), 1000, unsafe_test: true)) == 32
  end
end
