defmodule FindependenceHosted.Preflight do
  @moduledoc """
  REQ-194, REQ-195 (WI-084; OPS-001 E3): before a production server starts, check that its secrets, roles,
  connections, and host settings match the deployment guide (DEPLOY.md), and don't start if any required check
  fails. Also a release command, so an operator can run it on demand:

      bin/findependence_hosted eval "FindependenceHosted.Preflight.report()"

  `facts/0` reads the system (environment, /proc, the cookie file, the database); `checks/1` judges the facts and is
  pure, so each check is tested with good and bad facts. The checks:

  - secrets: SECRET_KEY_BASE at least 64 characters, the account-number hash key at least 32 bytes, RELEASE_COOKIE
    at least 32 characters
  - the release's COOKIE file readable by its owner only
  - console: distribution on only when OPERATOR_CONSOLE=on (REQ-193)
  - crash dumps off; the process's core-dump limit 0; swap off, or only on device-mapped (encrypted) storage
    (REQ-194)
  - process tracing restricted (kernel.yama.ptrace_scope 3)
  - the database role can only read and write rows (`FindependenceHosted.DbRoles.problems/1`)
  - the database connection uses verified TLS, or is on this host (WI-081)
  """

  alias FindependenceHosted.{DbRoles, Repo}

  @doc "What the checks judge, read from this system."
  def facts(repo \\ Repo) do
    %{
      secret_key_base:
        Application.get_env(:findependence_hosted, FindependenceHostedWeb.Endpoint)[
          :secret_key_base
        ],
      account_hmac_key: Application.get_env(:findependence_hosted, :account_hmac_key),
      passphrase_pepper: Application.get_env(:findependence_hosted, :passphrase_pepper),
      household_state_key: Application.get_env(:findependence_hosted, :household_state_key),
      release_cookie: System.get_env("RELEASE_COOKIE"),
      cookie_mode: cookie_mode(),
      operator_console: System.get_env("OPERATOR_CONSOLE") == "on",
      distributed: Node.alive?(),
      crash_dump_seconds: System.get_env("ERL_CRASH_DUMP_SECONDS"),
      core_limit: proc(:limits) |> core_limit(),
      swaps: proc(:swaps) |> swaps(),
      ptrace_scope: proc(:ptrace_scope) |> trim(),
      db_problems: db_problems(repo),
      repo_config: Application.get_env(:findependence_hosted, Repo, [])
    }
  end

  @doc "Each check's name and result, `:ok` or `{:fail, reason}`, in a fixed order."
  def checks(f) do
    [
      {"secret key base",
       length_at_least(
         f.secret_key_base,
         64,
         "SECRET_KEY_BASE is missing or shorter than 64 characters"
       )},
      {"account-number hash key",
       bytes_at_least(
         f.account_hmac_key,
         32,
         "ACCOUNT_HMAC_KEY is missing or shorter than 32 bytes"
       )},
      # WI-085 (REQ-197, REQ-198)
      {"passphrase pepper",
       bytes_at_least(
         f.passphrase_pepper,
         32,
         "PASSPHRASE_PEPPER is missing or shorter than 32 bytes"
       )},
      {"household state key",
       bytes_at_least(
         f.household_state_key,
         32,
         "HOUSEHOLD_STATE_KEY is missing or shorter than 32 bytes"
       )},
      {"release cookie",
       length_at_least(
         f.release_cookie,
         32,
         "RELEASE_COOKIE is missing or shorter than 32 characters"
       )},
      {"cookie file", cookie_file(f.cookie_mode)},
      {"remote console", console(f.distributed, f.operator_console)},
      {"crash dumps",
       if(f.crash_dump_seconds == "0", do: :ok, else: {:fail, "ERL_CRASH_DUMP_SECONDS isn't 0"})},
      {"core dumps",
       if(f.core_limit == "0",
         do: :ok,
         else: {:fail, "the core-dump limit is #{inspect(f.core_limit)}, not 0 (LimitCORE=0)"}
       )},
      {"swap", swap(f.swaps)},
      {"process tracing",
       if(f.ptrace_scope == "3",
         do: :ok,
         else: {:fail, "kernel.yama.ptrace_scope is #{inspect(f.ptrace_scope)}, not 3"}
       )},
      {"database role", db_role(f.db_problems)},
      {"database TLS", db_tls(f.repo_config)}
    ]
  end

  @doc "The failing checks, as `[{name, reason}]`."
  def failures(checks), do: for({name, {:fail, reason}} <- checks, do: {name, reason})

  @doc """
  The release command: prints every check and raises (so the command exits non-zero) if any fails. Starts the
  repository for the database checks, as `FindependenceHosted.Release` does.
  """
  def report do
    Application.load(:findependence_hosted)

    {:ok, checks, _} =
      Ecto.Migrator.with_repo(Repo, fn repo -> checks(facts(repo)) end)

    for {name, result} <- checks,
        do: IO.puts("#{if result == :ok, do: "ok  ", else: "FAIL"} #{name}#{reason(result)}")

    case failures(checks) do
      [] ->
        :ok

      failed ->
        raise "preflight failed: " <> Enum.map_join(failed, "; ", fn {n, r} -> "#{n}: #{r}" end)
    end
  end

  @doc false
  def child_spec(_),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}

  @doc "At start (production, `:preflight`): the server doesn't start if any check fails."
  def start_link do
    if Application.get_env(:findependence_hosted, :preflight, false) do
      case failures(checks(facts())) do
        [] ->
          :ignore

        failed ->
          raise "preflight failed: " <> Enum.map_join(failed, "; ", fn {n, r} -> "#{n}: #{r}" end)
      end
    else
      :ignore
    end
  end

  # ---------------------------------------------------------------------------

  defp reason(:ok), do: ""
  defp reason({:fail, r}), do: " (" <> r <> ")"

  defp length_at_least(v, n, msg),
    do: if(is_binary(v) and String.length(v) >= n, do: :ok, else: {:fail, msg})

  defp bytes_at_least(v, n, msg),
    do: if(is_binary(v) and byte_size(v) >= n, do: :ok, else: {:fail, msg})

  defp cookie_file(nil), do: :ok

  defp cookie_file(mode) when is_integer(mode) do
    import Bitwise

    if (mode &&& 0o077) == 0,
      do: :ok,
      else:
        {:fail,
         "the release's COOKIE file is readable by others (mode #{Integer.to_string(mode &&& 0o777, 8)})"}
  end

  defp console(true, false), do: {:fail, "distribution is on without OPERATOR_CONSOLE=on"}
  defp console(_, _), do: :ok

  defp swap(:unknown), do: {:fail, "/proc/swaps can't be read"}

  defp swap(devices) do
    plain =
      Enum.reject(
        devices,
        &(String.starts_with?(&1, "/dev/dm-") or String.starts_with?(&1, "/dev/mapper/"))
      )

    if plain == [],
      do: :ok,
      else:
        {:fail, "swap on storage that isn't device-mapped (encrypted): #{Enum.join(plain, ", ")}"}
  end

  defp db_role(:unknown), do: {:fail, "the database couldn't be asked"}
  defp db_role([]), do: :ok
  defp db_role(problems), do: {:fail, "the database role " <> Enum.join(problems, ", ")}

  defp db_tls(config) do
    host = config[:url] && URI.parse(config[:url]).host
    loopback? = host in ["localhost", "127.0.0.1", "::1"]

    case config[:ssl] do
      ssl when is_list(ssl) ->
        if ssl[:verify] == :verify_peer,
          do: :ok,
          else: {:fail, "TLS to the database doesn't verify the server"}

      _ when loopback? ->
        :ok

      _ ->
        {:fail, "the database connection isn't encrypted and the database isn't on this host"}
    end
  end

  defp cookie_mode do
    with root when is_binary(root) <- System.get_env("RELEASE_ROOT"),
         {:ok, %File.Stat{mode: mode}} <- File.stat(Path.join([root, "releases", "COOKIE"])) do
      mode
    else
      _ -> nil
    end
  end

  defp db_problems(repo) do
    DbRoles.problems(&repo.query!/1)
  rescue
    _ -> :unknown
  end

  # the three /proc files the checks read, each by its literal path
  defp proc(:limits), do: File.read("/proc/self/limits") |> ok_or_nil()
  defp proc(:swaps), do: File.read("/proc/swaps") |> ok_or_nil()
  defp proc(:ptrace_scope), do: File.read("/proc/sys/kernel/yama/ptrace_scope") |> ok_or_nil()

  defp ok_or_nil({:ok, text}), do: text
  defp ok_or_nil(_), do: nil

  defp trim(nil), do: nil
  defp trim(text), do: String.trim(text)

  @doc false
  def core_limit(nil), do: nil

  def core_limit(text) do
    case Regex.run(~r/^Max core file size\s+(\S+)/m, text) do
      [_, soft] -> soft
      _ -> nil
    end
  end

  @doc false
  def swaps(nil), do: :unknown

  def swaps(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.map(&(&1 |> String.split() |> List.first()))
  end
end
