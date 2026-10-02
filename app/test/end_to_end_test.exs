defmodule FindependenceApp.EndToEndTest do
  @moduledoc """
  WI-028 (security self-review F-18): the real server, started as its own OS process the way a
  household runs it, used over loopback HTTP with curl. Two earlier bugs appeared only at this
  level (a fresh VM, a real terminal), so this complements the in-process Plug tests.
  """
  use ExUnit.Case, async: false

  alias FindependenceApp.Vault

  @moduletag timeout: 180_000

  setup do
    if System.find_executable("curl") == nil, do: raise("curl is needed for the end-to-end test")

    dir = Path.join(System.tmp_dir!(), "fv-e2e-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "household.vault")

    Vault.create([{"ana", "ana passphrase 1"}, {"ben", "ben passphrase 2"}],
      iterations: 1_000,
      unsafe_test: true
    )
    |> Vault.write!(path)

    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir, path: path, port: free_port()}
  end

  defp free_port do
    {:ok, s} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(s)
    :gen_tcp.close(s)
    port
  end

  # Starts `mix findependence.serve` in its own OS process and waits until it answers.
  defp start_server(path, port) do
    mix = System.find_executable("mix")

    server =
      Port.open({:spawn_executable, mix}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["findependence.serve", path, Integer.to_string(port)],
        cd: File.cwd!(),
        env: [{~c"MIX_ENV", ~c"dev"}, {~c"ERL_CRASH_DUMP_SECONDS", ~c"0"}]
      ])

    wait_until(fn -> match?({_, 200}, curl(port, nil, ["http://127.0.0.1:#{port}/"])) end, 120)
    server
  end

  defp stop_server(server) do
    {:os_pid, pid} = Port.info(server, :os_pid)
    System.cmd("kill", [Integer.to_string(pid)])
    Port.close(server)
  catch
    _, _ -> :ok
  end

  defp wait_until(fun, seconds) do
    Enum.reduce_while(1..(seconds * 4), nil, fn _, _ ->
      if fun.(), do: {:halt, :ok}, else: Process.sleep(250) && {:cont, nil}
    end) || flunk("server did not answer within #{seconds} s")
  end

  # Returns {body, status}. `jar` keeps cookies between calls, as a browser would.
  defp curl(port, jar, args) do
    jar_args = if jar, do: ["-b", jar, "-c", jar], else: []

    {out, _} =
      System.cmd("curl", ["-s", "-w", "\n%{http_code}"] ++ jar_args ++ args,
        stderr_to_stdout: true
      )

    [status | rest] = out |> String.split("\n") |> Enum.reverse()
    {rest |> Enum.reverse() |> Enum.join("\n"), String.to_integer(status)}
  rescue
    _ -> {"", 0}
  after
    _ = port
  end

  defp get(port, jar, path), do: curl(port, jar, ["http://127.0.0.1:#{port}#{path}"])

  defp post(port, jar, path, fields) do
    {page, 200} = get(port, jar, "/")
    [_, token] = Regex.run(~r/name=_csrf_token value="([^"]+)"/, page)
    # the page's one-time form token, as a browser sends it (REQ-165, DEF-041)
    [_, form] = Regex.run(~r/name=_form value="([^"]+)"/, page)

    data =
      Enum.flat_map([{"_csrf_token", token}, {"_form", form} | fields], fn {k, v} ->
        ["--data-urlencode", "#{k}=#{v}"]
      end)

    curl(port, jar, data ++ ["http://127.0.0.1:#{port}#{path}"])
  end

  defp login(port, jar, member, pass),
    do: {_, 303} = post(port, jar, "/login", [{"member", member}, {"passphrase", pass}])

  # The listening socket for `port`, from /proc/net/tcp{,6}: [{local_address_hex, family}]
  defp listeners(port) do
    hex = port |> Integer.to_string(16) |> String.pad_leading(4, "0")

    for {file, family} <- [{"/proc/net/tcp", :v4}, {"/proc/net/tcp6", :v6}],
        File.exists?(file),
        line <- file |> File.read!() |> String.split("\n") |> Enum.drop(1),
        [_, local, _, state | _] <- [String.split(line)],
        state == "0A",
        [addr, ^hex] <- [String.split(local, ":")],
        do: {addr, family}
  end

  test "a member uses the real server over loopback, and everything survives a restart",
       %{dir: dir, path: path, port: port} do
    jar = Path.join(dir, "cookies")
    server = start_server(path, port)

    try do
      # REQ-123: bound to 127.0.0.1 only
      assert listeners(port) == [{"0100007F", :v4}]

      # a foreign Host header is refused over real TCP
      {_, status} = curl(port, nil, ["-H", "Host: evil.example", "http://127.0.0.1:#{port}/"])
      assert status in 400..499

      login(port, jar, "ana", "ana passphrase 1")

      {_, 303} =
        post(port, jar, "/act/add_item", [
          {"note", "Bus pass"},
          {"amount", "32.50"},
          {"direction", "out"},
          {"frequency", "weekly"}
        ])

      {home, 200} = get(port, jar, "/")
      assert home =~ "Added “Bus pass”."
      # UX-003 C10: on home the figure and how often it happens have their own cells
      assert home =~
               ~s(>−$32.50<span class=phone-only> a week</span></td><td role=cell class=freq data-label="How often">a week</td>)

      # REQ-126: 3250 x 52 / 12 = 14083.33
      assert home =~ ~s(data-label="Money out, per month" data-short="Out/month">−$140.83<)

      [_, id] = Regex.run(~r{href="/items/([A-Za-z0-9_-]+)"><b>Bus pass}, home)
      {_, 303} = post(port, jar, "/act/grant", [{"item", id}, {"member", "ben"}])
      {_, 303} = post(port, jar, "/logout", [])
      {locked, 200} = get(port, jar, "/")
      assert locked =~ "Unlock"
      refute locked =~ "Bus pass"
    after
      stop_server(server)
    end

    # a new server process on the same file. The real server runs with the 72-hour cooling-off (REQ-201,
    # WI-088): ben doesn't see the share yet, and ana still sees it waiting, with the time it takes effect
    port2 = free_port()
    server2 = start_server(path, port2)

    try do
      jar2 = Path.join(dir, "cookies2")
      login(port2, jar2, "ben", "ben passphrase 2")
      {home, 200} = get(port2, jar2, "/")
      refute home =~ "Bus pass"

      jar3 = Path.join(dir, "cookies3")
      login(port2, jar3, "ana", "ana passphrase 1")
      {home, 200} = get(port2, jar3, "/")
      assert home =~ "Bus pass"
      assert home =~ "Takes effect"
    after
      stop_server(server2)
    end
  end
end
