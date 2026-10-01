defmodule FindependenceHosted.Accounts do
  @moduledoc """
  Platform context Identity for the hosted form (DP-001 section 2; ARCH-003 16; WI-073): sign-up after the
  disclosure (REQ-180), accounts and sign-in (REQ-181), key material wrapped by the passphrase and by a recovery
  key (REQ-182), passphrase changes, and recovery with the recovery key only (REQ-184; REV-095: there is no reset
  without it). The operator can recover nothing: the private key is stored only wrapped.

  Failures carry ARCH-003 34's categories: `{:error, :validation, {field, message}}`,
  `{:error, :unauthenticated, :bad_credentials}`, `{:error, :rate_limited, :too_many_attempts}`.
  """

  import Ecto.Query
  alias FindependenceHosted.{Audit, Limits, Repo, Sessions}
  alias FindependenceHosted.Schemas.{Account, Membership}
  alias FindependenceShared.Crypto

  @min_passphrase 12
  @recovery_bytes 20
  @recovery_info "findependence recovery key v1"
  @number_bytes 10
  @number_info "findependence account number v1"

  # ---------------------------------------------------------------------------
  # Sign-up

  @doc """
  Creates an account once the person has confirmed the disclosure (REQ-180). Returns
  `{:ok, account_id, account_number, recovery_key}`: both are shown once (REQ-181, REQ-184 AC-1).

  WI-081 (REV-108; ASSESS-001 FND-06): an account is identified by an account number of 80 random bits, not an
  email address, so sign-up asks for nothing that could tell anyone whether a person has an account, and no
  personal address is kept. The number is stored as a keyed hash, to find the account at sign-in, and encrypted
  under a key derived from the member's private key, so their own signed-in session can show it again.
  """
  def sign_up(%{} = params) do
    with :ok <- disclosure(params["disclosure"]),
         :ok <- passphrase_ok(params["passphrase"], params["passphrase_confirmation"]) do
      id = Ecto.UUID.generate()
      {pub, priv} = Crypto.keypair()
      number = :crypto.strong_rand_bytes(@number_bytes)
      recovery = :crypto.strong_rand_bytes(@recovery_bytes)
      {pass_salt, iterations, by_pass} = wrap_by_passphrase(id, priv, params["passphrase"])
      recovery_salt = Crypto.random_salt()

      %Account{
        id: id,
        number_hmac: hmac(number),
        number_box:
          pack(Crypto.encrypt(number_key(priv), format_number(number), aad(id, "number"))),
        public_key: pub,
        # WI-079: published so members can pin it; derived from the private key, never stored itself
        signing_public_key: elem(Crypto.signing_keypair(priv), 0),
        pass_salt: pass_salt,
        pass_iterations: iterations,
        private_key_by_passphrase: by_pass,
        recovery_salt: recovery_salt,
        private_key_by_recovery_key:
          pack(Crypto.encrypt(recovery_key(recovery, recovery_salt), priv, aad(id, "recovery")))
      }
      |> Repo.insert!()

      Audit.record("sign_up", :ok, %{account_id: id})
      {:ok, id, format_number(number), format_recovery(recovery)}
    end
  end

  # ---------------------------------------------------------------------------
  # Sign-in

  @doc """
  Signs in with an account number and passphrase (REQ-181). An unknown number and a wrong passphrase get the
  same refusal after the same derivation work (AC-2); repeated failures are limited (REQ-190). Returns
  `{:ok, token}` for a new session holding the unwrapped key in memory (REQ-183).

  `device` is the account id from a device cookie this browser was given at an earlier sign-in, already
  verified by the caller (WI-080; REQ-190 AC-1 as CP-025 amends it). A sign-in to that same account isn't held
  back by the account's total from all clients, so guesses made elsewhere can't lock the owner out on a device
  they have used; it is still limited per client. Failures are counted against every key either way.
  """
  def sign_in(number, passphrase, client, device \\ nil) do
    h = number_hmac(number)
    keys = attempt_keys(h, client)
    found = Repo.get_by(Account, number_hmac: h)
    checked = if found && device == found.id, do: device_keys(h, client), else: keys

    if Limits.limited?(checked) do
      Audit.record("sign_in", :refused)
      {:error, :rate_limited, :too_many_attempts}
    else
      case found do
        nil ->
          # the same work as a real attempt, so the two refusals cannot be told apart by time
          _ =
            Crypto.derive_key(
              to_string(passphrase),
              Crypto.random_salt(),
              iterations(),
              kdf_opts()
            )

          refuse(keys, "sign_in", nil)

        account ->
          case unwrap_by_passphrase(account, passphrase) do
            {:ok, priv} ->
              Audit.record("sign_in", :ok, %{account_id: account.id})
              {:ok, start_session(account, priv)}

            :error ->
              refuse(keys, "sign_in", account.id)
          end
      end
    end
  end

  defp refuse(keys, operation, account_id) do
    Limits.failed(keys)
    Audit.record(operation, :refused, %{account_id: account_id})
    {:error, :unauthenticated, :bad_credentials}
  end

  defp start_session(account, priv) do
    # The public key is derived from the private key just unwrapped, not read from the accounts table, which
    # the operator could change (REV-099 G4); it is the one others have pinned.
    {pub, ^priv} = :crypto.generate_key(:ecdh, :x25519, priv)
    publish_signing_key(account, priv)
    token = Sessions.put(%{account_id: account.id, private_key: priv, public_key: pub})

    case Repo.get_by(Membership, account_id: account.id) do
      nil ->
        :ok

      m ->
        Sessions.put_membership(token, %{
          id: m.id,
          household_id: m.household_id,
          display_name: m.display_name
        })
    end

    token
  end

  # WI-079: an account made before signing keys publishes its signing key at its next sign-in. One already
  # published is left as it is: if it was changed, members who pinned it report the change.
  defp publish_signing_key(%Account{signing_public_key: nil} = account, priv) do
    from(a in Account, where: a.id == ^account.id and is_nil(a.signing_public_key))
    |> Repo.update_all(set: [signing_public_key: elem(Crypto.signing_keypair(priv), 0)])
  end

  defp publish_signing_key(_account, _priv), do: :ok

  @doc "Signs out: the session and its key are discarded (REQ-183 AC-1)."
  def sign_out(token, account_id) do
    Sessions.drop(token)
    Audit.record("sign_out", :ok, %{account_id: account_id})
    :ok
  end

  # ---------------------------------------------------------------------------
  # Passphrase change and recovery

  @doc """
  Changes the passphrase after checking the current one; every other session of the account ends (REQ-183 AC-2).
  """
  def change_passphrase(account_id, keep_token, params) do
    account = Repo.get!(Account, account_id)

    with :ok <- passphrase_ok(params["passphrase"], params["passphrase_confirmation"]),
         {:current, {:ok, priv}} <- {:current, unwrap_by_passphrase(account, params["current"])} do
      rewrap(account, priv, params["passphrase"])
      Sessions.drop_account(account_id, keep_token)
      Audit.record("passphrase_changed", :ok, %{account_id: account_id})
      :ok
    else
      {:current, :error} ->
        Audit.record("passphrase_changed", :refused, %{account_id: account_id})
        {:error, :validation, {:current, "That isn't your current passphrase."}}

      error ->
        error
    end
  end

  @doc """
  Deletes the account after checking its passphrase (REQ-189 AC-1, WI-074): refused while its person is a
  member of a household (they leave first, REQ-110); otherwise the account's row goes, with its wrapped key
  material, and every session of it ends. Content-free audit records stay (REQ-191).
  """
  def delete_account(account_id, passphrase) do
    account = Repo.get!(Account, account_id)

    cond do
      Repo.exists?(from(m in Membership, where: m.account_id == ^account_id)) ->
        Audit.record("account_deleted", :refused, %{account_id: account_id})
        {:error, :permanent_domain_rejection, :still_member}

      unwrap_by_passphrase(account, passphrase) == :error ->
        Audit.record("account_deleted", :refused, %{account_id: account_id})
        {:error, :validation, {:passphrase, "That isn't your passphrase."}}

      true ->
        Repo.delete!(account)
        Sessions.drop_account(account_id)
        Audit.record("account_deleted", :ok, %{account_id: account_id})
        :ok
    end
  end

  @doc """
  Sets a new passphrase with the account number and the recovery key, keeping all the member's information
  (REQ-184 AC-2). A wrong key gets the same refusal as an unknown account number; failures are limited (REQ-190).
  Without the recovery key there is no way back (REV-095). Every session of the account ends. The used key
  stops working and a new one is returned, to be shown once (REQ-184 AC-6, WI-079): `{:ok, recovery_key}`.
  """
  def recover(params, client) do
    h = number_hmac(params["account_number"])
    keys = attempt_keys(h, client)

    with :ok <- passphrase_ok(params["passphrase"], params["passphrase_confirmation"]) do
      cond do
        Limits.limited?(keys) ->
          Audit.record("recovery", :refused)
          {:error, :rate_limited, :too_many_attempts}

        true ->
          with %Account{} = account <- Repo.get_by(Account, number_hmac: h),
               {:ok, recovery} <- parse_recovery(params["recovery_key"]),
               {:ok, priv} <-
                 Crypto.decrypt(
                   recovery_key(recovery, account.recovery_salt),
                   unpack(account.private_key_by_recovery_key),
                   aad(account.id, "recovery")
                 ) do
            account = rewrap(account, priv, params["passphrase"])
            new_key = replace_recovery_wrap(account, priv)

            # REQ-184 AC-7 (WI-080): the owner can see when this happened
            account
            |> Ecto.Changeset.change(
              recovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
            )
            |> Repo.update!()

            Sessions.drop_account(account.id)
            Audit.record("recovery", :ok, %{account_id: account.id})
            {:ok, new_key}
          else
            nil -> refuse(keys, "recovery", nil)
            _ -> refuse(keys, "recovery", account_id_for(h))
          end
      end
    end
  end

  @doc "When the account was last recovered with a recovery key (REQ-184 AC-7), or nil."
  def recovered_at(account_id),
    do: Repo.one(from(a in Account, where: a.id == ^account_id, select: a.recovered_at))

  @doc """
  Replaces the recovery key after checking the passphrase (REQ-184 AC-5, WI-079): the old key stops working,
  every other session of the account ends, and the new key is returned to be shown once:
  `{:ok, recovery_key}`.
  """
  def replace_recovery_key(account_id, keep_token, passphrase) do
    account = Repo.get!(Account, account_id)

    case unwrap_by_passphrase(account, passphrase) do
      {:ok, priv} ->
        new_key = replace_recovery_wrap(account, priv)
        Sessions.drop_account(account_id, keep_token)
        Audit.record("recovery_key_replaced", :ok, %{account_id: account_id})
        {:ok, new_key}

      :error ->
        Audit.record("recovery_key_replaced", :refused, %{account_id: account_id})
        {:error, :validation, {:current, "That isn't your passphrase."}}
    end
  end

  # A fresh 160-bit recovery key and salt wrap the private key; the previous wrapping is overwritten, so the
  # previous key opens nothing. Returns the new key, formatted to show once.
  defp replace_recovery_wrap(account, priv) do
    recovery = :crypto.strong_rand_bytes(@recovery_bytes)
    salt = Crypto.random_salt()

    account
    |> Ecto.Changeset.change(
      recovery_salt: salt,
      private_key_by_recovery_key:
        pack(Crypto.encrypt(recovery_key(recovery, salt), priv, aad(account.id, "recovery")))
    )
    |> Repo.update!()

    format_recovery(recovery)
  end

  # an account number is counted per client, per client, and in total (REQ-190 AC-1 as CP-023 amends it)
  defp attempt_keys(h, client), do: [{:pair, {h, client}}, {:client, client}, {:account, h}]

  # a known device: the account's total from all clients doesn't apply (WI-080)
  defp device_keys(h, client), do: [{:pair, {h, client}}, {:client, client}]

  @doc """
  Whether a client may try another sign-up (REQ-190 AC-5, WI-079): at most 10 from one client in 15 minutes.
  `count_sign_up/1` counts each try, whatever its outcome.
  """
  def sign_up_allowed?(client), do: not Limits.limited?([{:sign_up, client}])

  @doc false
  def count_sign_up(client), do: Limits.failed([{:sign_up, client}])

  defp account_id_for(h) do
    Repo.one(from(a in Account, where: a.number_hmac == ^h, select: a.id))
  end

  defp rewrap(account, priv, passphrase) do
    {salt, iterations, by_pass} = wrap_by_passphrase(account.id, priv, passphrase)

    account
    |> Ecto.Changeset.change(
      pass_salt: salt,
      pass_iterations: iterations,
      private_key_by_passphrase: by_pass
    )
    |> Repo.update!()
  end

  # ---------------------------------------------------------------------------
  # Checks

  defp disclosure("true"), do: :ok

  defp disclosure(_),
    do:
      {:error, :validation,
       {:disclosure, "Confirm that you've read how your information is handled."}}

  defp passphrase_ok(pass, confirmation) do
    cond do
      String.length(to_string(pass)) < @min_passphrase ->
        {:error, :validation,
         {:passphrase, "Use a passphrase of at least #{@min_passphrase} characters."}}

      pass != confirmation ->
        {:error, :validation, {:passphrase_confirmation, "The two passphrases don't match."}}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Keys (REQ-182: PBKDF2-HMAC-SHA256 as REQ-118 specifies; the recovery key is 160 random bits, so HKDF suffices)

  defp wrap_by_passphrase(id, priv, passphrase) do
    salt = Crypto.random_salt()
    kek = Crypto.derive_key(to_string(passphrase), salt, iterations(), kdf_opts())
    {salt, iterations(), pack(Crypto.encrypt(kek, priv, aad(id, "passphrase")))}
  end

  defp unwrap_by_passphrase(account, passphrase) do
    kek =
      Crypto.derive_key(
        to_string(passphrase),
        account.pass_salt,
        account.pass_iterations,
        kdf_opts()
      )

    Crypto.decrypt(kek, unpack(account.private_key_by_passphrase), aad(account.id, "passphrase"))
  end

  defp recovery_key(recovery, salt), do: Crypto.hkdf(recovery, salt, @recovery_info, 32)
  defp aad(id, purpose), do: "findependence account " <> id <> " " <> purpose

  @doc "The configured PBKDF2 iteration count (REQ-118: at least 600,000 outside tests)."
  def iterations, do: Application.fetch_env!(:findependence_hosted, :kdf)[:iterations]

  defp kdf_opts,
    do: [unsafe_test: Application.fetch_env!(:findependence_hosted, :kdf)[:unsafe_test] == true]

  # nonce (12 bytes) <> tag (16 bytes) <> ciphertext
  defp pack(%{n: n, t: t, c: c}), do: n <> t <> c
  defp unpack(<<n::binary-size(12), t::binary-size(16), c::binary>>), do: %{n: n, t: t, c: c}

  defp format_recovery(bytes) do
    bytes
    |> Base.encode32(padding: false)
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join("-", &Enum.join/1)
  end

  defp parse_recovery(text) do
    cleaned = text |> to_string() |> String.upcase() |> String.replace(~r/[^A-Z2-7]/, "")

    case Base.decode32(cleaned, padding: false) do
      {:ok, <<_::binary-size(@recovery_bytes)>> = bytes} -> {:ok, bytes}
      _ -> :error
    end
  end

  # ---------------------------------------------------------------------------
  # Account numbers (WI-081): 80 random bits, written as four groups of four, kept only as a keyed hash and
  # encrypted for the member

  @doc "The account's number, for its own signed-in session (decrypted with the session's private key), or nil."
  def account_number(account_id, priv) do
    case Repo.one(from(a in Account, where: a.id == ^account_id, select: a.number_box)) do
      box when is_binary(box) ->
        case Crypto.decrypt(number_key(priv), unpack(box), aad(account_id, "number")) do
          {:ok, number} -> number
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc false
  def number_hmac(text) do
    case parse_number(text) do
      {:ok, bytes} -> hmac(bytes)
      # not a number we could have issued: hashed anyway, so the work and the refusal are the same
      :error -> hmac("not a number: " <> to_string(text))
    end
  end

  defp parse_number(text) do
    cleaned = text |> to_string() |> String.upcase() |> String.replace(~r/[^A-Z2-7]/, "")

    case Base.decode32(cleaned, padding: false) do
      {:ok, <<_::binary-size(@number_bytes)>> = bytes} -> {:ok, bytes}
      _ -> :error
    end
  end

  defp format_number(bytes), do: format_recovery(bytes)

  defp number_key(priv), do: Crypto.hkdf(priv, "", @number_info, 32)

  @doc false
  def hmac(bytes), do: :crypto.mac(:hmac, :sha256, hmac_key(), bytes)

  defp hmac_key, do: Application.fetch_env!(:findependence_hosted, :account_hmac_key)
end
