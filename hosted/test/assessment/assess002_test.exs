defmodule FindependenceHosted.Assess002Test do
  @moduledoc """
  ASSESS-002 (project/assurance/security-review/ASSESS-002-implementation-assessment.md): the runtime evidence
  for the second implementation assessment of the hosted form. Each test asserts what was OBSERVED, whether the
  property held or failed, and prints its evidence line ("E-0nn ...") so a run is the evidence record.
  Run with `mix test test/assessment --trace`.

  WI-085 mitigated FND-201 and FND-203..FND-208; the tests for those findings now assert the fixed behaviour
  (evidence lines E-2nn), and the report's E-1nn lines record what main 5592d94 did before.

  Attacker models exercised here: another household's member (ISO-1), another member of the same household
  (ISO-2, DER-1), a grantee (DEL-2, REV-1), whoever can read the database (OI-2), whoever can write the database
  without the application's code (DI-1), and whoever can run code in the server's node (OI-2 runtime).
  """
  use FindependenceHostedWeb.DomainCase

  import Ecto.Query
  import ExUnit.CaptureLog

  alias FindependenceHosted.{Domain, Repo, Sessions, Tenancy}
  alias FindependenceHosted.Schemas.Household
  alias FindependenceHosted.TestStore
  alias FindependenceShared.{Items, Values}

  defp ev(id, text), do: IO.puts("#{id} #{text}")

  defp add(h, name, note, amount, direction \\ "in") do
    conn =
      act(h, name, "/act/add_item", %{
        "note" => note,
        "amount" => amount,
        "direction" => direction,
        "frequency" => "monthly",
        "on" => "2026-10-05"
      })

    302 = conn.status
    item_id(h, name, note)
  end

  defp item_id(h, name, note) do
    [id] =
      for {id, %{attrs: %{note: ^note}}} <- Items.all(scope(h, name)), do: id

    id
  end

  defp grant(h, owner, item, to) do
    {:ok, _} = Items.propose_grant(scope(h, owner), item, id(h, to))
  end

  defp body(conn), do: conn.resp_body || ""

  # a page without its per-request tokens, to compare two renderings
  defp normal(html) do
    html
    |> String.replace(~r/name="_csrf_token"[^>]*value="[^"]*"/, "")
    |> String.replace(~r/name="_form"[^>]*value="[^"]*"/, "")
    |> String.replace(~r/<meta name="csrf-token" content="[^"]*"/, "")
  end

  @pages ~w(/ /household /ahead /next-60-days /goals /retirement /plans /export /leave /balances/new /bring-in)

  # ---------------------------------------------------------------------------------------------------------
  # ISO-1: another household

  test "ISO-1: a member of another household reaches nothing of this one, by any identifier" do
    a = household(~w(ana))
    b = household(~w(zed))
    secret = add(a, "ana", "Iso one secret", "4321.09")
    {:ok, _} = Values.add_value(scope(a, "ana"), "Iso value")

    before =
      Domain.load(Tenancy.scope(elem(Sessions.fetch(a["ana"].token), 1)).session.household_id)

    gets =
      for path <- ["/items/#{secret}", "/requests/1", "/plans/#{secret}"],
          do: {path, page(b, "zed", path)}

    posts =
      for {path, params} <- [
            {"/act/grant", %{"item" => secret, "member" => id(b, "zed")}},
            {"/act/revoke", %{"item" => secret, "member" => id(a, "ana")}},
            {"/act/owners", %{"item" => secret, "owners" => [id(b, "zed")]}},
            {"/act/delete", %{"item" => secret}},
            {"/act/relinquish", %{"item" => secret}},
            {"/act/link", %{"item" => secret, "value" => secret}},
            {"/act/attach", %{"item" => secret, "account" => secret}},
            {"/act/mark", %{"item" => secret, "job" => secret}},
            {"/act/consent", %{"proposal" => "1"}},
            {"/act/withdraw", %{"proposal" => "1"}},
            {"/act/add_reading", %{"item" => secret, "balance" => "1", "on" => "2026-09-29"}},
            {"/confirm/delete", %{"item" => secret}}
          ],
          do: {path, act(b, "zed", path, params)}

    for {path, conn} <- gets ++ posts do
      refute body(conn) =~ "Iso one secret", path
      refute body(conn) =~ "4,321.09", path
    end

    after_ = Domain.load(before.hid |> Ecto.UUID.load!())
    assert after_.items == before.items
    assert after_.proposals == before.proposals

    ev(
      "E-101",
      "ISO-1 HELD: 3 GETs and 12 POSTs naming household A's item from household B: statuses " <>
        inspect(Enum.map(gets ++ posts, fn {p, c} -> {p, c.status} end)) <>
        "; A's rows unchanged; no A content in any response"
    )
  end

  # ---------------------------------------------------------------------------------------------------------
  # ISO-2 and DER-1: another member of the same household

  test "ISO-2/DER-1: every page another member sees is identical before and after a member adds private items" do
    h = household(~w(ana ben))
    seen = fn -> Map.new(@pages, &{&1, normal(body(page(h, "ben", &1)))}) end

    before = seen.()
    _ = add(h, "ana", "Private salary", "7123.45", "in")
    _ = add(h, "ana", "Private clinic", "250.00", "out")

    {:ok, _} =
      FindependenceShared.Balances.add_account(
        scope(h, "ana"),
        "acc-ana",
        "Ana savings",
        :savings
      )

    after_ = seen.()

    differing = for p <- @pages, before[p] != after_[p], do: p

    ev(
      "E-102",
      "ISO-2/DER-1 on #{length(@pages)} pages (#{Enum.join(@pages, " ")}): pages differing for Ben after " <>
        "Ana added 2 private money items and an account: #{inspect(differing)}"
    )

    assert differing == []
  end

  test "ISO-2: a hidden item and an item that doesn't exist get the same answer" do
    h = household(~w(ana ben))
    secret = add(h, "ana", "Hidden one", "10.00")
    hidden = page(h, "ben", "/items/#{secret}")
    missing = page(h, "ben", "/items/AAAAAAAAAAAA")

    ev(
      "E-103",
      "ISO-2 hidden vs missing item: statuses #{hidden.status}/#{missing.status}; bodies equal after " <>
        "removing tokens and the id: #{normal(body(hidden)) |> String.replace(secret, "X") == normal(body(missing)) |> String.replace("AAAAAAAAAAAA", "X")}"
    )

    assert hidden.status == missing.status

    assert normal(body(hidden)) |> String.replace(secret, "X") ==
             normal(body(missing)) |> String.replace("AAAAAAAAAAAA", "X")
  end

  test "FND-204 fixed (REQ-190 AC-4, WI-085): a member's item limit doesn't depend on others' items" do
    Application.put_env(:findependence_hosted, :max_items, 5)
    on_exit(fn -> Application.delete_env(:findependence_hosted, :max_items) end)

    h = household(~w(ana ben))
    for n <- 1..3, do: add(h, "ana", "Ana private #{n}", "1.00")

    added =
      Enum.reduce_while(1..10, 0, fn n, acc ->
        conn =
          act(h, "ben", "/act/add_item", %{
            "note" => "Ben #{n}",
            "amount" => "1",
            "direction" => "out",
            "frequency" => "monthly"
          })

        if conn.status == 302, do: {:cont, acc + 1}, else: {:halt, acc}
      end)

    ev(
      "E-204",
      "FND-204 after WI-085: limit 5 per member, Ana holds 3 private items, Ben could add #{added} " <>
        "(his own limit), so nothing about Ana's items can be inferred"
    )

    assert added == 5
  end

  test "FND-205 fixed (REQ-199, WI-085): request identifiers don't count others' requests" do
    h = household(~w(ana ben cal))
    a1 = add(h, "ana", "Ana joint", "1.00")
    a2 = add(h, "ana", "Ana second", "1.00")
    grant(h, "ana", a1, "cal")
    grant(h, "ana", a2, "cal")
    b1 = add(h, "ben", "Ben thing", "1.00")
    {:ok, _} = Items.propose_owners(scope(h, "ben"), b1, [id(h, "ben"), id(h, "cal")])
    # WI-086: Cal agrees to become an owner
    agree(h, "cal", b1)
    {:ok, saved} = Items.propose_grant(scope(h, "ben"), b1, id(h, "ana"))

    keys = saved.household.proposals |> Map.keys()
    ben_home = body(page(h, "ben", "/"))

    shown =
      Regex.scan(~r/<input[^>]*name="proposal"[^>]*>/, ben_home)
      |> Enum.flat_map(fn [tag] ->
        Regex.run(~r/value="([^"]+)"/, tag, capture: :all_but_first) || []
      end)
      |> Enum.uniq()

    # internally it is request 4; the same number in another household has a different identifier
    hid = elem(Sessions.fetch(h["ben"].token), 1).membership.household_id
    other = household(~w(zed))
    other_hid = elem(Sessions.fetch(other["zed"].token), 1).membership.household_id
    assert FindependenceHosted.RequestRefs.ref(hid, 4) == hd(keys)
    refute FindependenceHosted.RequestRefs.ref(other_hid, 4) == hd(keys)

    ev(
      "E-205",
      "FND-205 after WI-085: Ben's view keys requests by #{inspect(keys)}; his home page's forms carry " <>
        "#{inspect(shown)}; no integer appears: #{Enum.all?(shown, &(not Regex.match?(~r/\A[0-9]+\z/, &1)))}"
    )

    assert [ref] = keys
    assert Regex.match?(~r/\A[A-Za-z0-9_-]{12}\z/, ref)
    assert shown == [ref]
  end

  # ---------------------------------------------------------------------------------------------------------
  # DEL-1, DEL-2, REV-1: sharing

  test "DEL-2: a grantee can't reshare, revoke, delete, change owners of, or add readings to what they see" do
    h = household(~w(ana ben cal))

    {:ok, _} =
      FindependenceShared.Balances.add_account(scope(h, "ana"), "acc-1", "Shared acct", :checking)

    grant(h, "ana", "acc-1", "ben")
    before = scope(h, "ana") |> Items.get("acc-1") |> elem(1)

    tries = [
      {"/act/grant", %{"item" => "acc-1", "member" => id(h, "cal")}},
      {"/act/revoke", %{"item" => "acc-1", "member" => id(h, "ben")}},
      {"/act/owners", %{"item" => "acc-1", "owners" => [id(h, "ana"), id(h, "ben")]}},
      {"/act/owners", %{"item" => "acc-1", "owners" => [id(h, "ben")]}},
      {"/act/delete", %{"item" => "acc-1"}},
      {"/act/relinquish", %{"item" => "acc-1"}},
      {"/act/add_reading", %{"item" => "acc-1", "balance" => "999", "on" => "2026-09-29"}}
    ]

    results = for {path, params} <- tries, do: {path, act(h, "ben", path, params).status}
    after_ = scope(h, "ana") |> Items.get("acc-1") |> elem(1)
    pending = scope(h, "ana") |> Items.pending()

    ev(
      "E-106",
      "DEL-2 grantee attempts: #{inspect(results)}; owners #{inspect(after_.owners)} " <>
        "grantees unchanged: #{after_.grantees == before.grantees}; requests waiting on Ana: #{length(pending)}"
    )

    assert after_.owners == before.owners
    assert after_.grantees == before.grantees
    assert pending == []
  end

  test "REV-1: a revoked grantee's very next request no longer shows the item, nor does their export" do
    h = household(~w(ana ben))
    item = add(h, "ana", "Revocable rent", "1500.00", "out")
    grant(h, "ana", item, "ben")

    shown = page(h, "ben", "/items/#{item}")
    assert body(shown) =~ "Revocable rent"

    {:ok, _} = Items.revoke_grant(scope(h, "ana"), item, id(h, "ben"))

    t0 = System.monotonic_time(:microsecond)
    gone = page(h, "ben", "/items/#{item}")
    home = page(h, "ben", "/")
    export = page(h, "ben", "/export.json")
    t1 = System.monotonic_time(:microsecond)

    ev(
      "E-107",
      "REV-1 grant revoked: Ben's next item page #{gone.status} without the name: " <>
        "#{not (body(gone) =~ "Revocable rent")}; home without it: #{not (body(home) =~ "Revocable rent")}; " <>
        "export without it: #{not (body(export) =~ "Revocable rent")}; latency bound: the next request " <>
        "(three requests in #{div(t1 - t0, 1000)} ms, no cached view)"
    )

    refute body(gone) =~ "Revocable rent"
    refute body(home) =~ "Revocable rent"
    refute body(export) =~ "Revocable rent"
  end

  test "REV-1: leaving ends the leaver's every session at once; their household rows go" do
    h = household(~w(ana ben))
    ben = session_account(h, "ben")
    second = h["ben"].conn |> Phoenix.ConnTest.recycle()
    conn = act(h, "ben", "/leave", %{})
    assert conn.status in [302, 200]

    other =
      Phoenix.ConnTest.dispatch(second, FindependenceHostedWeb.Endpoint, :get, "/household", nil)

    ev(
      "E-108",
      "REV-1 leaving: the same browser's next request is sent to #{inspect(Phoenix.ConnTest.redirected_to(other))}; " <>
        "any session still holding Ben's key: #{Sessions.held?(ben)}"
    )

    assert Phoenix.ConnTest.redirected_to(other) == "/sign-in"
    refute Sessions.held?(ben)
  end

  defp session_account(h, name), do: elem(Sessions.fetch(h[name].token), 1).account_id

  test "UA-3: an export holds what the member owns and their own records, not what they were shown" do
    h = household(~w(ana ben))
    item = add(h, "ana", "Granted but not owned", "12.00")
    grant(h, "ana", item, "ben")
    _ = add(h, "ben", "Ben owns this", "13.00")
    export = body(page(h, "ben", "/export.json"))

    ev(
      "E-109",
      "UA-3 Ben's export: holds his own item #{export =~ "Ben owns this"}; holds Ana's granted item " <>
        "#{export =~ "Granted but not owned"}"
    )

    assert export =~ "Ben owns this"
    refute export =~ "Granted but not owned"
  end

  # ---------------------------------------------------------------------------------------------------------
  # OI-2: the database and the runtime

  test "OI-2 database path: no member content, account number, passphrase or recovery key in any row" do
    {:ok, _, number, recovery} =
      FindependenceHosted.Accounts.sign_up(%{
        "passphrase" => "assessment passphrase two",
        "passphrase_confirmation" => "assessment passphrase two",
        "disclosure" => "true"
      })

    h = household(~w(ana ben))
    _ = add(h, "ana", "Dbscan salary note", "6543.21")
    {:ok, _} = Values.add_value(scope(h, "ana"), "Dbscan value words")

    {:ok, _} =
      FindependenceShared.Balances.add_account(
        scope(h, "ana"),
        "acc-db",
        "Dbscan account",
        :savings
      )

    tables =
      Repo.query!(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'"
      ).rows
      |> List.flatten()

    dump =
      for t <- tables, into: "" do
        Repo.query!("SELECT coalesce(string_agg(row_to_json(x)::text, E'\\n'), '') FROM #{t} x").rows
        |> List.flatten()
        |> Enum.join()
      end

    raw =
      for t <- tables, into: "" do
        Repo.query!("SELECT coalesce(string_agg(x::text, ''), '') FROM #{t} x").rows
        |> List.flatten()
        |> Enum.join()
      end

    needles = [
      "Dbscan salary note",
      "654321",
      "6543.21",
      "Dbscan value words",
      "Dbscan account",
      number,
      String.replace(number, "-", ""),
      recovery,
      "assessment passphrase two",
      "a long passphrase 1"
    ]

    # WI-086 (REQ-200): structure too: display names and item identifiers (owners, grantees, and requests live
    # inside the encrypted block with them)
    item_ids = h |> scope("ana") |> Items.all() |> Map.keys()
    structure = ["Ana", "Ben" | item_ids]

    found =
      for n <- needles ++ structure, String.contains?(dump, n) or String.contains?(raw, n), do: n

    hex_found = for n <- needles, String.contains?(dump, Base.encode16(n, case: :lower)), do: n

    ev(
      "E-110",
      "OI-2 database: #{length(tables)} tables (#{byte_size(dump)} bytes as JSON) searched for " <>
        "#{length(needles)} secrets and contents, plain and hex, and for display names and #{length(item_ids)} " <>
        "item identifiers: found #{inspect(found ++ hex_found)}; in plaintext only membership and account " <>
        "identifiers, which members belong to which household, and each household's change counter"
    )

    assert found == []
    assert hex_found == []
  end

  test "FND-203 hardened (WI-085): the sessions table can't be read directly; the operator still can (REV-111)" do
    h = household(~w(ana))
    _ = add(h, "ana", "Runtime visible note", "77.00")

    direct =
      try do
        :ets.tab2list(FindependenceHosted.Sessions)
        :read
      rescue
        ArgumentError -> :refused
      end

    # what an operator's console can still do: run code inside the sessions process
    me = self()

    :sys.replace_state(FindependenceHosted.Sessions, fn st ->
      send(me, {:rows, :ets.tab2list(FindependenceHosted.Sessions)})
      st
    end)

    rows = receive do: ({:rows, r} -> r)
    ana = session_account(h, "ana")

    keyed =
      for {_t, %{private_key: k, account_id: ^ana} = s} <- rows, is_binary(k), s.membership, do: s

    content =
      for s <- keyed,
          v = Domain.view(s),
          {_, item} <- v.household.items,
          note = get_in(item, [:attrs, :note]),
          is_binary(note),
          do: note

    ev(
      "E-203",
      "FND-203 after WI-085: the sessions table is #{:ets.info(FindependenceHosted.Sessions, :protection)}; " <>
        "a direct read from another process: #{direct}; code run inside the sessions process (as a console " <>
        "could) still decrypted #{inspect(content)} (accepted, REV-111)"
    )

    assert direct == :refused
    assert "Runtime visible note" in content
  end

  # ---------------------------------------------------------------------------------------------------------
  # DI-1: whoever can write the database (not the application's code)
  #
  # Since WI-086 a household's records are one block encrypted under a key held outside the database
  # (FindependenceHosted.TestStore plays both attackers): there are no owner, grantee, request, or agreement rows
  # left to forge, and the block's counter is kept outside the database too (REQ-198 AC-5).

  test "FND-201 fixed (WI-085, WI-086): whoever can write only the database can't change the records" do
    h = household(~w(ana cal ben))
    item = add(h, "ana", "Joint savings plan", "900.00")
    {:ok, _} = Items.propose_owners(scope(h, "ana"), item, [id(h, "ana"), id(h, "cal")])
    # WI-086: Cal agrees to become an owner
    agree(h, "cal", item)
    hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id
    other = household(~w(zed))
    zid = elem(Sessions.fetch(other["zed"].token), 1).membership.household_id
    clean = TestStore.snapshot(hid)

    tries = [
      changed_byte: fn -> TestStore.corrupt(hid) end,
      another_households_block: fn ->
        TestStore.restore(hid, %{household: TestStore.snapshot(zid).household})
      end,
      no_code: fn ->
        from(x in Household, where: x.id == ^hid) |> Repo.update_all(set: [state_mac: nil])
      end
    ]

    results =
      for {name, change} <- tries do
        change.()
        {status, _, body} = assert_error_sent(409, fn -> page(h, "ana", "/") end)
        TestStore.restore(hid, clean)
        {name, status, body =~ "changed outside this service"}
      end

    ben_sees = body(page(h, "ben", "/items/#{item}")) =~ "Joint savings plan"

    ev(
      "E-212",
      "FND-201 after WI-086: the records are one encrypted block; a database writer's attempts: " <>
        "#{inspect(results)}; restored, Ben (no grant) reads the item: #{ben_sees}"
    )

    assert Enum.all?(results, fn {_, s, said} -> s == 409 and said end)
    refute ben_sees
  end

  test "FND-201 residual, closed by WI-090 (REQ-203): even holding the household keys, the operator can't forge an agreement" do
    h = household(~w(ana cal ben))
    item = add(h, "ana", "Joint savings plan", "900.00")
    {:ok, _} = Items.propose_owners(scope(h, "ana"), item, [id(h, "ana"), id(h, "cal")])
    # WI-086: Cal agrees to become an owner
    agree(h, "cal", item)

    hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id
    n = forge(hid, item, id(h, "cal"), id(h, "ben"))

    ref = FindependenceHosted.RequestRefs.ref(hid, n)
    ana_home = body(page(h, "ana", "/"))
    _ = act(h, "ana", "/act/consent", %{"proposal" => ref})
    ben_sees = body(page(h, "ben", "/items/#{item}")) =~ "Joint savings plan"

    ev(
      "E-212r",
      "FND-201 residual after WI-090: with the keys, the forged request shows \"Agreed so far: Cal\": " <>
        "#{ana_home =~ "Agreed so far: Cal"}; after Ana agrees Ben reads the item: #{ben_sees} " <>
        "(Cal's agreement isn't signed with Cal's key, so it isn't counted)"
    )

    refute ana_home =~ "Agreed so far: Cal"
    refute ben_sees
  end

  # the operator, holding the keys: a request "Cal asks to let Ben see it", with Cal's agreement
  defp forge(hid, item, cal, ben) do
    n = TestStore.held(hid).next_proposal

    TestStore.as_operator(hid, fn held ->
      held
      |> put_in([:proposals, n], %{
        item_id: item,
        change: {:grant, ben},
        proposed_by: cal,
        consents: MapSet.new([cal])
      })
      |> Map.put(:next_proposal, n + 1)
    end)

    n
  end

  test "DI-1 HELD: a reader written into the records by the operator is never given a key" do
    h = household(~w(ana ben cal))
    item = add(h, "ana", "Planted reader target", "41.00")
    hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id

    TestStore.as_operator(
      hid,
      &update_in(&1, [:items, item, :grantees], fn g -> Enum.sort([id(h, "ben") | g]) end)
    )

    # an honest change by Ana re-saves the item; the seal commitments still hold
    {:ok, _} = Items.propose_grant(scope(h, "ana"), item, id(h, "cal"))
    assert body(page(h, "cal", "/items/#{item}")) =~ "Planted reader target"
    ben_sees = body(page(h, "ben", "/items/#{item}")) =~ "Planted reader target"

    ev(
      "E-214",
      "DI-1 grantee written in by the operator without a seal: after Ana's save (a grant to Cal, who reads " <>
        "it), Ben reads the item: #{ben_sees}"
    )

    refute ben_sees
  end

  # ---------------------------------------------------------------------------------------------------------
  # Re-run at 4ac86a7 (2026-10-02), and WI-086's answers

  test "FND-209 fixed (WI-086): restoring a whole earlier copy of a household is refused" do
    h = household(~w(ana ben))
    item = add(h, "ana", "Rollback target", "60.00")
    grant(h, "ana", item, "ben")
    hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id

    copy = TestStore.snapshot(hid)
    {:ok, _} = Items.revoke_grant(scope(h, "ana"), item, id(h, "ben"))
    revoked = body(page(h, "ben", "/items/#{item}")) =~ "Rollback target"

    TestStore.restore(hid, copy)
    {status, _, restored} = assert_error_sent(409, fn -> page(h, "ben", "/items/#{item}") end)

    ev(
      "E-301",
      "FND-209 after WI-086: a database writer puts back an earlier copy (block, counter, and code): Ben's " <>
        "page answers #{status}, the item shown: #{restored =~ "Rollback target"}; the counter outside " <>
        "the database is #{FindependenceHosted.StateLedger.latest(hid)}, the copy's #{copy.household.version}"
    )

    refute revoked
    refute restored =~ "Rollback target"
  end

  test "RE-RUN HELD: an earlier block under the current counter is refused" do
    h = household(~w(ana ben))
    item = add(h, "ana", "Partial rollback", "61.00")
    grant(h, "ana", item, "ben")
    hid = elem(Sessions.fetch(h["ana"].token), 1).membership.household_id
    old = TestStore.snapshot(hid)

    {:ok, _} = Items.revoke_grant(scope(h, "ana"), item, id(h, "ben"))
    now = TestStore.snapshot(hid)

    TestStore.restore(hid, %{household: %{now.household | state_box: old.household.state_box}})
    {status, _, _} = assert_error_sent(409, fn -> page(h, "ben", "/items/#{item}") end)

    ev(
      "E-302",
      "an earlier block put back under the current counter and code: Ben's page answers #{status}"
    )
  end

  test "RE-RUN HELD: a made-up or another household's request identifier matches nothing" do
    h = household(~w(ana ben cal))
    item = add(h, "ana", "Ref target", "62.00")
    {:ok, _} = Items.propose_owners(scope(h, "ana"), item, [id(h, "ana"), id(h, "cal")])
    # WI-086: Cal agrees to become an owner
    agree(h, "cal", item)
    {:ok, _} = Items.propose_grant(scope(h, "ana"), item, id(h, "ben"))
    other = household(~w(zed))
    zid = elem(Sessions.fetch(other["zed"].token), 1).membership.household_id

    tries =
      for ref <- [
            "AAAAAAAAAAAA",
            FindependenceHosted.RequestRefs.ref(zid, 3),
            "3",
            "1",
            "../../x"
          ] do
        {ref, act(h, "cal", "/act/consent", %{"proposal" => ref}).status}
      end

    still_waiting = Items.pending(scope(h, "cal")) |> Enum.map(& &1.consents)

    ev(
      "E-303",
      "forged request identifiers sent by Cal: #{inspect(tries)}; the real request still waits for Cal: " <>
        "#{inspect(still_waiting)}"
    )

    assert Enum.all?(tries, fn {_, s} -> s == 422 end)
    assert [[_]] = still_waiting
  end

  test "FND-210 fixed (WI-086): items given to a member wait for them, so they can't fill their limit" do
    Application.put_env(:findependence_hosted, :max_items, 3)
    on_exit(fn -> Application.delete_env(:findependence_hosted, :max_items) end)

    h = household(~w(ana ben))

    for n <- 1..3 do
      item = add(h, "ana", "Dumped #{n}", "1.00")
      {:ok, _} = Items.propose_owners(scope(h, "ana"), item, [id(h, "ben")])
    end

    ben = id(h, "ben")
    ben_owns = Enum.count(Items.visible(scope(h, "ben")), &(ben in &1.owners))
    waiting = length(Items.pending(scope(h, "ben")))

    added =
      act(h, "ben", "/act/add_item", %{
        "note" => "Ben's own",
        "amount" => "1",
        "direction" => "out",
        "frequency" => "monthly"
      })

    ev(
      "E-310",
      "FND-210 after WI-086: limit 3 per member; Ana offered Ben 3 items; Ben owns #{ben_owns}, with " <>
        "#{waiting} requests waiting for his answer; Ben adding his own item answers #{added.status}"
    )

    assert ben_owns == 0
    assert waiting == 3
    assert added.status == 302
  end

  # ---------------------------------------------------------------------------------------------------------
  # DM-1 / SC-1: logs

  test "DM-1/SC-1: a full session at debug level logs no content, secret, number, or token" do
    previous = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous) end)

    log =
      capture_log([level: :debug], fn ->
        h = household(~w(ana ben))
        item = add(h, "ana", "Logscan note", "3210.98")
        grant(h, "ana", item, "ben")
        _ = page(h, "ben", "/items/#{item}")
        _ = page(h, "ana", "/export.json")
        _ = act(h, "ana", "/act/add_item", %{"note" => "Logscan bad", "amount" => %{"x" => "1"}})
        send(self(), {:tokens, h["ana"].token, h["ben"].token})
      end)

    {ana_t, ben_t} = receive do: ({:tokens, a, b} -> {a, b})

    needles = [
      "Logscan note",
      "3210.98",
      "321098",
      "Logscan bad",
      "a long passphrase 1",
      ana_t,
      ben_t
    ]

    found = for n <- needles, String.contains?(log, n), do: n

    ev(
      "E-115",
      "DM-1 logs at debug: #{length(String.split(log, "\n"))} lines captured; found #{inspect(found)}; " <>
        "parameters shown as #{if log =~ "[FILTERED]", do: "[FILTERED]", else: "absent"}"
    )

    assert found == []
  end

  # ---------------------------------------------------------------------------------------------------------
  # Browser and session properties

  test "FND-206 fixed (WI-085): the session cookie is encrypted; nothing in it is readable without the key" do
    h = household(~w(ana))

    conn =
      act(h, "ana", "/act/add_item", %{
        "note" => "Cookie visible note",
        "amount" => "5",
        "direction" => "out",
        "frequency" => "monthly"
      })

    cookie = conn.resp_cookies["_findependence_hosted_key"].value

    readable =
      cookie
      |> String.split(".")
      |> Enum.any?(fn part ->
        case Base.url_decode64(part, padding: false) do
          {:ok, bin} -> bin =~ "Cookie visible note"
          :error -> false
        end
      end)

    ev(
      "E-217",
      "FND-206 after WI-085: the session cookie has #{length(String.split(cookie, "."))} parts " <>
        "(Plug's encrypted format, \"XCP.\" prefix: #{String.starts_with?(cookie, "XCP.")}); the item's name " <>
        "readable from it: #{readable}"
    )

    assert String.starts_with?(cookie, "XCP.")
    refute readable
  end

  test "HTTP: security headers and the session cookie on a signed-in page" do
    h = household(~w(ana))
    conn = page(h, "ana", "/")
    headers = Map.new(conn.resp_headers)

    keys =
      ~w(content-security-policy referrer-policy cache-control x-content-type-options x-frame-options permissions-policy)

    missing = for k <- keys, not Map.has_key?(headers, k), do: k

    ev(
      "E-116",
      "HTTP headers on /: " <>
        inspect(Map.take(headers, keys)) <>
        "; missing: #{inspect(missing)}; session cookie options in the endpoint: SameSite=Lax, HttpOnly, " <>
        "Secure (compile-time true outside tests)"
    )

    assert headers["content-security-policy"] =~ "default-src"
    # FND-208 (WI-085)
    assert headers["x-frame-options"] == "DENY"
    assert headers["cache-control"] =~ "no-store"
    refute headers["content-security-policy"] =~ "unsafe-eval"
  end
end
