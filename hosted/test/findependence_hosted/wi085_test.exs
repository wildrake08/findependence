defmodule FindependenceHosted.WI085Test do
  @moduledoc """
  WI-085 (CP-028, REV-113; ASSESS-002): the passphrase pepper and the common-passphrase list (REQ-197), the
  household records' code (REQ-198), the server keys required in production, the audit records copied to the
  log, and the console's approval reference (REQ-193 AC-3). The request identifiers (REQ-199), the per-member
  item limit (REQ-190 AC-4), the encrypted cookie, the private sessions table, and the headers are tested in
  test/assessment/assess002_test.exs, against the assessment's own attacks.
  """
  use FindependenceHostedWeb.DomainCase

  import Ecto.Query
  import ExUnit.CaptureLog

  alias FindependenceHosted.{
    Accounts,
    CommonPassphrases,
    Domain,
    Repo,
    Sessions,
    StateSeal,
    Tenancy
  }

  alias FindependenceHosted.Schemas.{Account, Household, Membership}

  @pass "a long passphrase 1"

  defp sign_up(pass \\ @pass),
    do:
      Accounts.sign_up(%{
        "passphrase" => pass,
        "passphrase_confirmation" => pass,
        "disclosure" => "true"
      })

  describe "REQ-197: a database copy alone allows no passphrase guessing" do
    test "AC-1: the stored key opens only with the passphrase and the pepper together" do
      {:ok, id, number, _recovery} = sign_up()
      account = Repo.get!(Account, id)

      # what someone with only the database can try: the passphrase, stretched as stored, without the pepper
      stretched =
        FindependenceShared.Crypto.derive_key(
          @pass,
          account.pass_salt,
          account.pass_iterations,
          unsafe_test: true
        )

      <<n::binary-12, t::binary-16, c::binary>> = account.private_key_by_passphrase
      aad = "findependence account " <> id <> " passphrase"

      assert FindependenceShared.Crypto.decrypt(stretched, %{n: n, t: t, c: c}, aad) == :error

      peppered =
        :crypto.mac(
          :hmac,
          :sha256,
          Application.fetch_env!(:findependence_hosted, :passphrase_pepper),
          stretched
        )

      assert {:ok, _} = FindependenceShared.Crypto.decrypt(peppered, %{n: n, t: t, c: c}, aad)

      # and the service signs in with it, but not under another pepper
      assert {:ok, _} = Accounts.sign_in(number, @pass, "test")
      previous = Application.fetch_env!(:findependence_hosted, :passphrase_pepper)
      Application.put_env(:findependence_hosted, :passphrase_pepper, String.duplicate("p", 32))
      on_exit(fn -> Application.put_env(:findependence_hosted, :passphrase_pepper, previous) end)
      assert {:error, _, _} = Accounts.sign_in(number, @pass, "test2")
    end

    test "AC-2: the most commonly used passphrases are refused, whatever their case or spacing" do
      for pass <- ["qwerty123456", " QWERTY123456 ", "1q2w3e4r5t6y"] do
        assert {:error, :validation, {:passphrase, message}} = sign_up(pass)
        assert message =~ "most commonly used"
      end

      assert {:ok, _, _, _} = sign_up("a long passphrase 1")
    end

    test "AC-2: the list is the one the moduledoc describes" do
      bytes = File.read!(Path.join([__DIR__, "..", "..", "priv", "common_passphrases.txt"]))

      assert :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) ==
               "7205db6ee41a2ccc9de1dd17292ba54070fd19665d9098fd80bc4f9231a61af0"

      assert CommonPassphrases.size() == 30_371
      refute CommonPassphrases.common?("a long passphrase 1")
    end
  end

  describe "REQ-198: a household's records carry a code under a key held outside the database" do
    test "AC-1: every change the service makes writes a code that verifies" do
      h = household(~w(ana ben))
      hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id

      assert Repo.one!(from(x in Household, where: x.id == ^hid, select: x.state_mac))
             |> is_binary()

      act(h, "ana", "/act/add_value", %{"label" => "A safe home"})
      assert %{} = Domain.load(hid)
    end

    test "AC-2: a swapped display name, a removed code, or a code from another household is refused" do
      h = household(~w(ana ben))
      other = household(~w(zed))
      hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id
      zid = elem(Sessions.fetch(other["zed"].token), 1).membership.household_id
      [ana, ben] = [id(h, "ana"), id(h, "ben")]
      box = fn m -> Repo.one!(from(x in Membership, where: x.id == ^m, select: x.name_box)) end

      set_box = fn m, b ->
        from(x in Membership, where: x.id == ^m) |> Repo.update_all(set: [name_box: b])
      end

      mac = fn hh -> Repo.one!(from(x in Household, where: x.id == ^hh, select: x.state_mac)) end

      set_mac = fn m ->
        from(x in Household, where: x.id == ^hid) |> Repo.update_all(set: [state_mac: m])
      end

      {ben_box, own_mac} = {box.(ben), mac.(hid)}

      # each change is refused, then undone
      for {change, undo} <- [
            # REQ-200: Ana's encrypted name copied over Ben's (each name is bound to its member)
            {fn -> set_box.(ben, box.(ana)) end, fn -> set_box.(ben, ben_box) end},
            {fn -> set_mac.(nil) end, fn -> set_mac.(own_mac) end},
            {fn -> set_mac.(mac.(zid)) end, fn -> set_mac.(own_mac) end}
          ] do
        change.()
        assert_raise FindependenceHosted.HouseholdTampered, fn -> Domain.load(hid) end
        undo.()
        assert %{} = Domain.load(hid)
      end
    end

    test "AC-3: a join doesn't vouch for records changed outside the service" do
      h = household(~w(ana))
      hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id
      {:ok, code, _} = Tenancy.create_invitation(elem(Sessions.fetch(h["ana"].token), 1))

      from(x in Household, where: x.id == ^hid) |> Repo.update_all(set: [state_mac: nil])

      {:ok, _, number, _} = sign_up()
      {:ok, token} = Accounts.sign_in(number, @pass, "test")

      assert_raise FindependenceHosted.HouseholdTampered, fn ->
        Tenancy.join(token, elem(Sessions.fetch(token), 1), code, "Dee", "test")
      end

      assert_raise FindependenceHosted.HouseholdTampered, fn -> Domain.load(hid) end
    end

    test "AC-4: after review, an operator's audited command writes a fresh block and code" do
      h = household(~w(ana))
      hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id

      from(x in Household, where: x.id == ^hid) |> Repo.update_all(set: [state_mac: nil])
      assert_raise FindependenceHosted.HouseholdTampered, fn -> Domain.load(hid) end

      assert_raise ArgumentError, fn ->
        FindependenceHosted.Release.reseal(hid, "no spaces allowed")
      end

      assert :ok = FindependenceHosted.Release.reseal(hid, "CR-2026-002")
      assert %{} = Domain.load(hid)

      assert %FindependenceHosted.Schemas.AuditEvent{
               operation: "operator_access",
               channel: "release_command",
               resource_id: resource
             } =
               Repo.one(
                 from(e in FindependenceHosted.Schemas.AuditEvent,
                   order_by: [desc: e.id],
                   limit: 1
                 )
               )

      assert resource == "reseal:#{hid}:CR-2026-002"
    end

    test "the encoding is canonical: the same state in another order gives the same code" do
      a = %{x: MapSet.new([3, 1, 2]), y: [1, 2], z: %{"b" => 1, "a" => {:t, nil}}}
      b = %{z: %{"a" => {:t, nil}, "b" => 1}, y: [1, 2], x: MapSet.new([2, 3, 1])}
      assert StateSeal.enc(a) == StateSeal.enc(b)
      refute StateSeal.enc(%{y: [1, 2]}) == StateSeal.enc(%{y: [2, 1]})
      refute StateSeal.enc("ab") == StateSeal.enc(["ab"])
    end
  end

  describe "ASSESS-002 FND-203: audit records reach the log" do
    test "each record is also written to the log, content-free" do
      previous = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: previous) end)

      log = capture_log([level: :info], fn -> {:ok, _, _, _} = sign_up() end)

      assert log =~
               ~r/audit id=\d+ at=\S+ operation=sign_up outcome=ok channel=web account=[0-9a-f-]{36}/

      refute log =~ @pass
    end
  end

  describe "the production configuration requires the two new keys" do
    test "PASSPHRASE_PEPPER and HOUSEHOLD_STATE_KEY: Base64 of at least 32 bytes" do
      good = %{
        "SECRET_KEY_BASE" => String.duplicate("s", 64),
        "DATABASE_URL" => "ecto://app:pw@db.internal/findependence",
        "ACCOUNT_HMAC_KEY" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "PASSPHRASE_PEPPER" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "HOUSEHOLD_STATE_KEY" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "HOUSEHOLD_LEDGER_PATH" => "/var/lib/findependence/household_ledger",
        "PHX_HOST" => "app.example.org"
      }

      prod = fn env ->
        saved = for k <- Map.keys(good), into: %{}, do: {k, System.get_env(k)}

        try do
          for k <- Map.keys(good), do: System.delete_env(k)
          for {k, v} <- env, do: System.put_env(k, v)

          Config.Reader.read!(Path.join([__DIR__, "..", "..", "config", "runtime.exs"]),
            env: :prod
          )
        after
          for {k, v} <- saved, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
        end
      end

      config = prod.(good)
      assert byte_size(config[:findependence_hosted][:passphrase_pepper]) == 32
      assert byte_size(config[:findependence_hosted][:household_state_key]) == 32

      for name <- ["PASSPHRASE_PEPPER", "HOUSEHOLD_STATE_KEY"],
          weak <- [nil, "short", Base.encode64(:crypto.strong_rand_bytes(16))] do
        env = if weak, do: Map.put(good, name, weak), else: Map.delete(good, name)

        assert_raise RuntimeError, ~r/#{name} must be Base64/, fn -> prod.(env) end
      end
    end
  end
end
