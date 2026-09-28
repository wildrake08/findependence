# VV-001 demonstration for REQ-123. From app/: mix run --no-start ../project/assurance/vv/demo_req123.exs
# REQ-123 demonstration: an unlocked session last used 16 minutes ago, with no request since.
alias FindependenceApp.{Sessions, Session, Vault}
path = Path.join(System.tmp_dir!(), "vv-req123-#{System.unique_integer([:positive])}.vault")
Vault.create([{"ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true) |> Vault.write!(path)
{:ok, _} = Sessions.start_link([])
{:ok, s} = Session.open(Vault.read!(path), "ana", "ana passphrase 1")
t0 = System.monotonic_time(:millisecond) - 16 * 60 * 1000
token = Sessions.put(s, t0)
held = Agent.get(Sessions, & &1) |> Map.values() |> Enum.any?(&match?(%{session: %{}}, &1))
IO.puts("VV-DEMO after 16 min idle, before any request: unlocked session still held in memory = #{held}")
# Since WI-052 a sweep runs every 5 seconds; wait one interval and look again, still with no request.
Process.sleep(6_000)
held_later = Agent.get(Sessions, & &1) |> Map.values() |> Enum.any?(&match?(%{session: %{}}, &1))
IO.puts("VV-DEMO 6 s later, still before any request: unlocked session still held in memory = #{held_later}")
IO.puts("VV-DEMO first request after that: #{inspect(elem(Sessions.fetch(token), 0))}, held now = #{Agent.get(Sessions, &map_size/1) > 0}")
File.rm(path)
