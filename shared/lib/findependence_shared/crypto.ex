defmodule FindependenceShared.Crypto do
  @moduledoc """
  Thin wrappers over vetted Erlang `:crypto` primitives (OpenSSL). No primitive is implemented here.

  - Passphrase key derivation: PBKDF2-HMAC-SHA256 (REQ-118).
  - Symmetric encryption: AES-256-GCM with a random 96-bit nonce and associated data.
  - Sealing to a member: an X25519 ephemeral key agreement, HKDF-SHA256 (RFC 5869; a composition
    of HMAC, checked against the RFC test vectors), then AES-256-GCM.
  - Signing (WI-079, FND-04): Ed25519, with each member's signing key derived from their X25519 private
    key, so it needs no storage of its own: seed = HKDF-SHA256(ikm = X25519 private key, salt = "",
    info = "findependence signing v1", 32 bytes).
  - Seal commitments (WI-079, FND-01): HMAC-SHA256 under the sealed key over the recipient, so a reader
    can check that a seal to someone else was written by a holder of the same key.
  """

  @min_iterations 600_000
  @seal_info "findependence seal v1"
  @signing_info "findependence signing v1"
  @commit_label "findependence seal-commit v1"

  def min_iterations, do: @min_iterations

  @doc "Derives a 32-byte key from a passphrase. Fewer than 600,000 iterations requires `unsafe_test: true`."
  def derive_key(passphrase, salt, iterations, opts \\ []) do
    if iterations < @min_iterations and not Keyword.get(opts, :unsafe_test, false),
      do: raise(ArgumentError, "PBKDF2 iterations below #{@min_iterations}")

    :crypto.pbkdf2_hmac(:sha256, passphrase, salt, iterations, 32)
  end

  def random_key, do: :crypto.strong_rand_bytes(32)
  def random_salt, do: :crypto.strong_rand_bytes(16)
  def keypair, do: :crypto.generate_key(:ecdh, :x25519)

  @doc "AES-256-GCM. Returns `%{n: nonce, c: ciphertext, t: tag}`."
  def encrypt(key, plaintext, aad) when byte_size(key) == 32 do
    nonce = :crypto.strong_rand_bytes(12)
    {c, t} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, aad, true)
    %{n: nonce, c: c, t: t}
  end

  @doc "Returns `{:ok, plaintext}`, or `:error` on a wrong key, wrong associated data, or tampering."
  def decrypt(key, %{n: n, c: c, t: t}, aad) when byte_size(key) == 32 do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, n, c, aad, t, false) do
      :error -> :error
      plaintext -> {:ok, plaintext}
    end
  end

  def decrypt(_, _, _), do: :error

  @doc "Seals `plaintext` so that only the holder of the private key for `recipient_pub` can open it."
  def seal(recipient_pub, plaintext, aad) do
    {eph_pub, eph_priv} = keypair()

    key =
      seal_key(
        :crypto.compute_key(:ecdh, recipient_pub, eph_priv, :x25519),
        eph_pub,
        recipient_pub
      )

    Map.put(encrypt(key, plaintext, aad), :e, eph_pub)
  end

  def open(recipient_pub, recipient_priv, %{e: eph_pub} = sealed, aad) do
    shared = :crypto.compute_key(:ecdh, eph_pub, recipient_priv, :x25519)
    decrypt(seal_key(shared, eph_pub, recipient_pub), sealed, aad)
  rescue
    _ -> :error
  end

  defp seal_key(shared, eph_pub, recipient_pub),
    do: hkdf(shared, eph_pub <> recipient_pub, @seal_info, 32)

  @doc "The Ed25519 key pair `{public, private}` derived from an X25519 private key (WI-079)."
  def signing_keypair(x25519_priv) when byte_size(x25519_priv) == 32 do
    seed = hkdf(x25519_priv, "", @signing_info, 32)
    :crypto.generate_key(:eddsa, :ed25519, seed)
  end

  @doc "An Ed25519 signature of `message` (64 bytes)."
  def sign(signing_priv, message),
    do: :crypto.sign(:eddsa, :none, message, [signing_priv, :ed25519])

  @doc "Whether `signature` is `signing_pub`'s Ed25519 signature of `message`; false for any malformed input."
  def verify(signing_pub, message, signature)
      when is_binary(signing_pub) and byte_size(signing_pub) == 32 and is_binary(signature) and
             byte_size(signature) == 64 and is_binary(message) do
    :crypto.verify(:eddsa, :none, message, signature, [signing_pub, :ed25519])
  rescue
    _ -> false
  end

  def verify(_, _, _), do: false

  @doc """
  The commitment stored beside a seal of `key` to `recipient` (WI-079): only a holder of `key` can write
  it, and only for that recipient.
  """
  def commit(key, recipient) when byte_size(key) == 32,
    do: :crypto.mac(:hmac, :sha256, key, @commit_label <> :erlang.term_to_binary(recipient))

  @doc "Whether `commitment` is `commit(key, recipient)`, compared in constant time."
  def commitment_valid?(key, recipient, commitment)
      when is_binary(key) and byte_size(key) == 32 and is_binary(commitment) and
             byte_size(commitment) == 32,
      do: :crypto.hash_equals(commit(key, recipient), commitment)

  def commitment_valid?(_, _, _), do: false

  @doc "HKDF-SHA256 (RFC 5869): extract, then expand."
  def hkdf(ikm, salt, info, length) do
    prk = hkdf_extract(salt, ikm)
    hkdf_expand(prk, info, length)
  end

  def hkdf_extract(salt, ikm), do: :crypto.mac(:hmac, :sha256, salt, ikm)

  def hkdf_expand(prk, info, length) when length <= 255 * 32 do
    {okm, _} =
      Enum.reduce(1..ceil(length / 32)//1, {<<>>, <<>>}, fn i, {acc, prev} ->
        t = :crypto.mac(:hmac, :sha256, prk, prev <> info <> <<i>>)
        {acc <> t, t}
      end)

    binary_part(okm, 0, length)
  end
end
