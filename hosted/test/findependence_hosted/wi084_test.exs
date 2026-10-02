defmodule FindependenceHosted.WI084Test do
  @moduledoc """
  WI-084 (REV-112; OPS-001): the hosted form's operating controls under a trusted operator. REQ-193: no remote
  console unless deliberately enabled, and enabling it is audited. REQ-194: no crash dumps; no start where core
  dumps or unencrypted swap are possible. REQ-195: the preflight check. REQ-196: readiness depends on the database.
  OPS-001 A7: operator-access records can be listed for shipping off the host.
  """
  use FindependenceHostedWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  alias FindependenceHosted.{OperatorAccess, Preflight, Release, Repo}
  alias FindependenceHosted.Schemas.AuditEvent

  describe "REQ-196: readiness" do
    test "ready answers 200 while the database is reachable, 503 when it isn't; live doesn't depend on it" do
      assert text_response(get(build_conn(), ~p"/health/ready"), 200) == "ok"

      # no connection is shared with the request any more, so its query fails as an unreachable database's would
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
      assert text_response(get(build_conn(), ~p"/health/ready"), 503) =~ "database unreachable"
      assert text_response(get(build_conn(), ~p"/health/live"), 200) == "ok"
    end
  end

  describe "REQ-193, REQ-194: the release script" do
    # rel/env.sh.eex rendered as the release does, then sourced by sh with chosen variables
    defp env_sh(vars) do
      dir = Path.join(System.tmp_dir!(), "fd-env-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      script =
        EEx.eval_file("rel/env.sh.eex", assigns: [release: %{name: "findependence_hosted"}])

      File.write!(Path.join(dir, "env.sh"), script)

      {out, status} =
        System.cmd(
          "sh",
          [
            "-c",
            ". ./env.sh && echo \"$RELEASE_DISTRIBUTION $ERL_CRASH_DUMP_SECONDS $ERL_CRASH_DUMP\""
          ],
          cd: dir,
          env: [{"RELEASE_COOKIE", String.duplicate("c", 40)} | vars],
          stderr_to_stdout: true
        )

      {String.trim(out), status}
    end

    test "the console is off unless OPERATOR_CONSOLE=on, whatever RELEASE_DISTRIBUTION says" do
      assert {"none 0 /dev/null", 0} = env_sh([])
      assert {"none 0 /dev/null", 0} = env_sh([{"RELEASE_DISTRIBUTION", "sname"}])
      assert {"none 0 /dev/null", 0} = env_sh([{"OPERATOR_CONSOLE", "yes"}])
      on = [{"OPERATOR_CONSOLE", "on"}, {"OPERATOR_CONSOLE_APPROVAL", "CR-2026-001"}]
      assert {"sname 0 /dev/null", 0} = env_sh(on)
      assert {"sname 0 /dev/null", 0} = env_sh([{"RELEASE_DISTRIBUTION", "none"} | on])

      # REQ-193 AC-3 (WI-085): not without the approved request's reference, nor with one that isn't plain
      for bad <- [
            [],
            [{"OPERATOR_CONSOLE_APPROVAL", ""}],
            [{"OPERATOR_CONSOLE_APPROVAL", "a b; rm -rf"}],
            [{"OPERATOR_CONSOLE_APPROVAL", String.duplicate("x", 65)}]
          ] do
        {out, status} = env_sh([{"OPERATOR_CONSOLE", "on"} | bad])
        assert status == 1
        assert out =~ "OPERATOR_CONSOLE_APPROVAL"
      end
    end

    test "crash dumps are off even when asked for" do
      assert {"none 0 /dev/null", 0} = env_sh([{"ERL_CRASH_DUMP_SECONDS", "600"}])
    end

    test "without a long release cookie nothing starts" do
      {out, status} = env_sh([{"RELEASE_COOKIE", "short"}])
      assert status == 1
      assert out =~ "RELEASE_COOKIE must be set"
    end
  end

  describe "REQ-193 AC-2: a console enabled at boot is audited" do
    test "a distributed node writes one record; an undistributed one writes none" do
      count = fn -> Repo.aggregate(AuditEvent, :count) end
      before = count.()

      refute OperatorAccess.record_console(false)
      assert count.() == before

      assert OperatorAccess.record_console(true, "CR-2026-001")

      assert %AuditEvent{
               operation: "operator_access",
               channel: "release_boot",
               resource_id: "console_enabled:CR-2026-001"
             } =
               Repo.one(from e in AuditEvent, order_by: [desc: e.id], limit: 1)

      # REQ-193 AC-3: a node started some other way, without a plain reference, says so
      assert OperatorAccess.record_console(true, nil)

      assert %AuditEvent{resource_id: "console_enabled:unapproved"} =
               Repo.one(from e in AuditEvent, order_by: [desc: e.id], limit: 1)
    end
  end

  describe "REQ-194, REQ-195: the preflight check" do
    @good %{
      secret_key_base: String.duplicate("k", 64),
      account_hmac_key: :crypto.strong_rand_bytes(32),
      passphrase_pepper: :crypto.strong_rand_bytes(32),
      household_state_key: :crypto.strong_rand_bytes(32),
      ledger: :ok,
      release_cookie: String.duplicate("c", 32),
      cookie_mode: 0o100600,
      operator_console: false,
      distributed: false,
      crash_dump_seconds: "0",
      core_limit: "0",
      swaps: [],
      ptrace_scope: "3",
      db_problems: [],
      repo_config: [url: "ecto://app:pw@db.internal/findependence", ssl: [verify: :verify_peer]]
    }

    test "a host matching the deployment guide passes every check" do
      checks = Preflight.checks(@good)
      assert length(checks) == 14
      assert Preflight.failures(checks) == []
    end

    test "each departure from the guide fails its own check" do
      for {change, name} <- [
            {%{secret_key_base: "short"}, "secret key base"},
            {%{account_hmac_key: "16 bytes only!!!"}, "account-number hash key"},
            {%{passphrase_pepper: nil}, "passphrase pepper"},
            {%{household_state_key: "16 bytes only!!!"}, "household state key"},
            {%{ledger: {:error, "eacces"}}, "household change ledger"},
            {%{release_cookie: nil}, "release cookie"},
            {%{cookie_mode: 0o100644}, "cookie file"},
            {%{distributed: true}, "remote console"},
            {%{crash_dump_seconds: nil}, "crash dumps"},
            {%{core_limit: "unlimited"}, "core dumps"},
            {%{swaps: ["/dev/sda2"]}, "swap"},
            {%{swaps: :unknown}, "swap"},
            {%{ptrace_scope: "1"}, "process tracing"},
            {%{ptrace_scope: nil}, "process tracing"},
            {%{db_problems: ["is a superuser"]}, "database role"},
            {%{db_problems: :unknown}, "database role"},
            {%{repo_config: [url: "ecto://app:pw@db.internal/f", ssl: false]}, "database TLS"},
            {%{repo_config: [url: "ecto://app:pw@db.internal/f", ssl: [verify: :verify_none]]},
             "database TLS"}
          ] do
        failed = Preflight.failures(Preflight.checks(Map.merge(@good, change)))
        assert [{^name, _reason}] = failed, "#{inspect(change)} -> #{inspect(failed)}"
      end
    end

    test "allowed variations pass: the console when enabled, encrypted swap, a database on this host" do
      for change <- [
            %{distributed: true, operator_console: true},
            %{swaps: ["/dev/dm-1", "/dev/mapper/cryptswap"]},
            %{repo_config: [url: "ecto://app:pw@localhost/f", ssl: false]},
            %{cookie_mode: nil}
          ] do
        assert Preflight.failures(Preflight.checks(Map.merge(@good, change))) == [],
               inspect(change)
      end
    end

    test "the /proc readers" do
      limits = """
      Limit                     Soft Limit           Hard Limit           Units
      Max cpu time              unlimited            unlimited            seconds
      Max core file size        0                    unlimited            bytes
      """

      assert Preflight.core_limit(limits) == "0"
      assert Preflight.core_limit(nil) == nil

      swaps =
        "Filename Type Size Used Priority\n/dev/dm-1 partition 1024 0 -2\n/swapfile file 512 0 -3\n"

      assert Preflight.swaps(swaps) == ["/dev/dm-1", "/swapfile"]
      assert Preflight.swaps("Filename Type Size Used Priority\n") == []
      assert Preflight.swaps(nil) == :unknown
    end

    test "facts are read from the running system" do
      f = Preflight.facts()
      assert Map.keys(f) |> Enum.sort() == Map.keys(@good) |> Enum.sort()
      # the test database is reached as the superuser, which the database-role check names
      assert "is a superuser" in f.db_problems
    end

    test "with the check on (production), a host that fails it doesn't start; with it off, nothing runs" do
      Application.put_env(:findependence_hosted, :preflight, true)
      on_exit(fn -> Application.delete_env(:findependence_hosted, :preflight) end)
      # the test host fails several checks (the superuser role among them)
      assert_raise RuntimeError, ~r/preflight failed: .*database role/, fn ->
        Preflight.start_link()
      end

      Application.put_env(:findependence_hosted, :preflight, false)
      assert Preflight.start_link() == :ignore
    end
  end

  describe "OPS-001 A7: operator-access records for shipping off the host" do
    test "lists the operator-access records since a time, and nothing else" do
      t0 = DateTime.utc_now() |> DateTime.add(-1, :second)
      FindependenceHosted.Audit.record("sign_up", :ok, %{})

      FindependenceHosted.Audit.record("operator_access", :ok, %{
        resource_id: "node@host",
        channel: "remote_console"
      })

      [line] = Release.operator_access_lines(Repo, t0)
      assert [_at, "remote_console", "node@host", "ok"] = String.split(line, "\t")

      assert Release.operator_access_lines(Repo, DateTime.add(DateTime.utc_now(), 60, :second)) ==
               []
    end
  end
end
