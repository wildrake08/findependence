defmodule FindependenceHosted.DomainTest do
  @moduledoc """
  WI-074: the hosted form's domain storage and persistence, for what is the hosted form's own (the criteria
  shared with the local form are in the contract cases): pins (REV-099 G4), one change at a time (G5), tenancy
  through the contexts and the database (REQ-186), joining (REQ-185 AC-3), recovery (REQ-184 AC-2), leaving and
  account deletion (REQ-189, REQ-183 AC-2, REQ-191 AC-1), and what is stored (REQ-187).
  """
  use FindependenceHostedWeb.ConnCase, async: false

  import Ecto.Query
  import FindependenceShared.Contract.Helpers

  alias FindependenceHosted.{Accounts, Limits, Repo, Sessions}
  alias FindependenceHosted.Schemas.{Account, AuditEvent, Membership}
  alias FindependenceShared.{Balances, Envelope, Households, Items, Planning, Values}

  @form FindependenceHosted.ContractForm
  @pass "a long passphrase 1"

  setup do
    Limits.reset()
    :ok
  end

  defp session(token), do: elem(Sessions.fetch(token), 1)
  defp account_id(token), do: session(token).account_id

  describe "REV-099 G4: pinned public keys" do
    test "a public key changed in the accounts table is reported and never sealed to" do
      h = household(@form, ~w(ana ben))
      ben = id(@form, h, "ben")
      # Ana's first operation pins Ben's key
      _ = add_item(@form, h, "ana", "First")

      # the operator swaps Ben's public key for one it holds
      {evil_pub, evil_priv} = FindependenceShared.Crypto.keypair()

      Repo.update_all(from(a in Account, where: a.id == ^account_id(h["ben"])),
        set: [public_key: evil_pub]
      )

      id = add_item(@form, h, "ana", "Rent")
      {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), id, ben)

      assert {:public_key_changed, ben} in Envelope.integrity_issues(
               scope(@form, h, "ana").session
             )

      # the new key sealed for Ben opens with Ben's own key, not the swapped one
      sealed = stored(@form, h).items[id].keys[ben]
      aad = Envelope.aad(stored(@form, h).hid, {:item_key, id, ben})
      assert :error = FindependenceShared.Crypto.open(evil_pub, evil_priv, sealed, aad)
      assert reads?(@form, h, "ben", id)
    end

    test "a member's own public key is derived from their private key, not read from the table" do
      email = "own-#{System.unique_integer([:positive])}@example.com"

      {:ok, _, _} =
        Accounts.sign_up(%{
          "email" => email,
          "passphrase" => @pass,
          "passphrase_confirmation" => @pass,
          "disclosure" => "true"
        })

      {:ok, t} = Accounts.sign_in(email, @pass, "t")
      real = session(t).public_key

      Repo.update_all(from(a in Account),
        set: [public_key: elem(FindependenceShared.Crypto.keypair(), 0)]
      )

      {:ok, t2} = Accounts.sign_in(email, @pass, "t")
      assert session(t2).public_key == real
    end
  end

  describe "REV-099 G5: one change at a time" do
    test "concurrent operations in one household are all kept" do
      h = household(@form, ~w(ana ben))

      tasks =
        for n <- 1..8 do
          who = if rem(n, 2) == 0, do: "ana", else: "ben"
          Task.async(fn -> add_item(@form, h, who, "Item #{n}") end)
        end

      ids = Task.await_many(tasks, 30_000)
      assert length(Enum.uniq(ids)) == 8
      assert map_size(stored(@form, h).items) == 8
    end
  end

  describe "REQ-186 AC-1: another household's identifiers" do
    test "an item, proposal, or member of another household is not found, and nothing changes" do
      h1 = household(@form, ~w(ana ben))
      h2 = household(@form, ~w(cy dee))
      theirs = add_item(@form, h2, "cy", "Theirs")
      # a value's joiner must consent, so this proposal stays open
      {:ok, v} = Values.add_value(scope(@form, h2, "cy"), "Their value")

      value =
        Enum.find_value(v.household.items, fn {id, i} ->
          if i.attrs[:label] == "Their value", do: id
        end)

      {:ok, saved} =
        Items.propose_owners(scope(@form, h2, "cy"), value, [
          id(@form, h2, "cy"),
          id(@form, h2, "dee")
        ])

      [proposal] = Map.keys(saved.household.proposals)
      mine = add_item(@form, h1, "ana", "Mine")
      before = stored(@form, h2)

      ana = scope(@form, h1, "ana")
      assert {:error, :not_found} = Items.get(ana, theirs)
      assert {:error, _, _, _} = Items.propose_grant(ana, theirs, id(@form, h1, "ben"))
      assert {:error, _, _, _} = Items.delete(ana, theirs)
      assert {:error, _, _, _} = Items.consent(ana, proposal)
      assert {:error, _, _, _} = Items.propose_grant(ana, mine, id(@form, h2, "dee"))
      assert {:error, _, _, _} = Values.link(ana, mine, theirs)
      assert {:error, _, _, _} = Planning.mark(ana, theirs, mine)

      assert stored(@form, h2) == before
    end
  end

  describe "REQ-186 AC-2: every domain table's household is tied by constraint" do
    test "a row referring to another household's item or member fails" do
      h1 = household(@form, ~w(ana))
      h2 = household(@form, ~w(cy))
      item = add_item(@form, h1, "ana", "Mine")
      hh1 = session(h1["ana"]).membership.household_id
      hh2 = session(h2["cy"]).membership.household_id
      cy = id(@form, h2, "cy")

      cases = [
        {"item_readers", "item_readers_member",
         "INSERT INTO item_readers VALUES ($1, $2, $3, 'grantee')", [hh1, item, cy]},
        {"item_readers", "item_readers_item",
         "INSERT INTO item_readers VALUES ($1, $2, $3, 'grantee')", [hh2, item, cy]},
        {"sealed_keys", "sealed_keys_member",
         "INSERT INTO sealed_keys VALUES ($1, $2, 'item', 0, $3, '\\x00')", [hh1, item, cy]},
        {"ledger_entries", "ledger_entries_item",
         "INSERT INTO ledger_entries VALUES ($1, $2, 99, '\\x00')", [hh2, item]},
        {"readings", "readings_item", "INSERT INTO readings VALUES ($1, $2, 99, '\\x00')",
         [hh2, item]},
        {"proposals", "proposals_proposer",
         "INSERT INTO proposals VALUES ($1, 99, $2, 'grant', $3)", [hh1, item, cy]},
        {"personal_records", "personal_records_member",
         "INSERT INTO personal_records VALUES ($1, $2, '\\x00')", [cy, hh1]}
      ]

      for {_table, constraint, sql, params} <- cases do
        params = Enum.map(params, &dump/1)

        assert_raise Postgrex.Error,
                     ~r/#{constraint}/,
                     fn ->
                       Repo.transaction(fn -> Repo.query!(sql, params) end)
                     end
      end
    end
  end

  defp dump(<<_::binary-size(36)>> = uuid), do: Ecto.UUID.dump!(uuid)
  defp dump(other), do: other

  describe "REQ-185 AC-3: a new member" do
    test "reads nothing until it is shared with them, and holds no key" do
      h = household(@form, ~w(ana ben))
      a = add_item(@form, h, "ana", "Ana's")
      b = add_item(@form, h, "ben", "Shared")
      {:ok, _} = Items.propose_grant(scope(@form, h, "ben"), b, id(@form, h, "ana"))

      {:ok, code, _} = FindependenceHosted.Tenancy.create_invitation(session(h["ana"]))
      cy_token = new_member("cy")
      {:ok, _} = FindependenceHosted.Tenancy.join(cy_token, session(cy_token), code, "Cy", "t")
      h = Map.put(h, "cy", cy_token)
      cy = id(@form, h, "cy")

      refute reads?(@form, h, "cy", a)
      refute reads?(@form, h, "cy", b)
      state = stored(@form, h)
      refute Enum.any?(state.items, fn {_, rec} -> Map.has_key?(rec.keys, cy) end)
      assert cy in Households.members(scope(@form, h, "cy"))

      {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), a, cy)
      assert reads?(@form, h, "cy", a)
    end
  end

  describe "REQ-184 AC-2: recovery" do
    test "after recovery the member reads every item, reading, and private record as before" do
      email = "rec-#{System.unique_integer([:positive])}@example.com"

      {:ok, _, key} =
        Accounts.sign_up(%{
          "email" => email,
          "passphrase" => @pass,
          "passphrase_confirmation" => @pass,
          "disclosure" => "true"
        })

      {:ok, t} = Accounts.sign_in(email, @pass, "t")
      {:ok, _} = FindependenceHosted.Tenancy.create_household(t, session(t), "Ana")
      h = %{"ana" => t}

      item = add_item(@form, h, "ana", "Rent")
      {:ok, v} = Values.add_value(scope(@form, h, "ana"), "Security")

      value =
        Enum.find_value(v.household.items, fn {id, i} ->
          if i.attrs[:label] == "Security", do: id
        end)

      {:ok, _} = Values.link(scope(@form, h, "ana"), item, value)
      {:ok, _} = Balances.add_account(scope(@form, h, "ana"), "acct1", "Checking", :checking)

      {:ok, _} =
        Balances.add_reading(scope(@form, h, "ana"), "acct1", %{
          balance: {:ok, 250_000, false},
          on: {:ok, "2026-09-01"},
          rate: nil,
          min_payment: nil
        })

      before = view(@form, h, "ana")

      :ok =
        Accounts.recover(
          %{
            "email" => email,
            "recovery_key" => key,
            "passphrase" => "a recovered passphrase",
            "passphrase_confirmation" => "a recovered passphrase"
          },
          "t"
        )

      {:ok, t2} = Accounts.sign_in(email, "a recovered passphrase", "t")
      after_ = view(@form, %{"ana" => t2}, "ana")

      assert after_.items == before.items
      assert after_.readings == before.readings
      assert after_.links == before.links
      assert after_.ledger == before.ledger
    end
  end

  defp new_member(name) do
    email = "#{name}-#{System.unique_integer([:positive])}@example.com"

    {:ok, _, _} =
      Accounts.sign_up(%{
        "email" => email,
        "passphrase" => @pass,
        "passphrase_confirmation" => @pass,
        "disclosure" => "true"
      })

    {:ok, token} = Accounts.sign_in(email, @pass, "test")
    token
  end

  describe "REQ-189 and REQ-183 AC-2: leaving and account deletion" do
    test "leaving removes the member's private records and every session; deleting leaves only audit" do
      h = household(@form, ~w(ana ben))
      ben = id(@form, h, "ben")
      ben_account = account_id(h["ben"])
      a = add_item(@form, h, "ana", "Rent")
      {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), a, ben)
      mine = add_item(@form, h, "ben", "Ben's")
      {:ok, _} = Planning.new_plan(scope(@form, h, "ben"), "p1", "Ben's plan")
      {:ok, _} = Planning.set_fund_goal(scope(@form, h, "ben"), 3)

      # still an owner: refused, with nothing changed
      assert {:error, :permanent_domain_rejection, :still_owner, _} =
               Households.leave(scope(@form, h, "ben"))

      assert {:error, :permanent_domain_rejection, :still_member} =
               Accounts.delete_account(ben_account, @pass)

      {:ok, _} = Items.delete(scope(@form, h, "ben"), mine)
      {:ok, _} = Planning.delete_plan(scope(@form, h, "ben"), "p1")
      other = Sessions.put(Map.take(session(h["ben"]), [:account_id, :private_key, :public_key]))
      Sessions.put_membership(other, session(h["ben"]).membership)

      {:ok, _} = Households.leave(scope(@form, h, "ben"))

      # REQ-183 AC-2: every session in the membership has ended
      assert Sessions.fetch(h["ben"]) == :none
      assert Sessions.fetch(other) == :none

      # REQ-189 AC-2: the member's personal record and membership are gone; the grant is revoked
      state = stored(@form, %{"ana" => h["ana"]})
      refute Map.has_key?(state.personal, ben)
      refute Map.has_key?(state.members, ben)

      refute Enum.any?(state.items, fn {_, rec} ->
               ben in rec.grantees or Map.has_key?(rec.keys, ben)
             end)

      refute Repo.exists?(from(m in Membership, where: m.id == ^ben))

      # REQ-189 AC-1: once out of the household the account can be deleted; only audit records name it
      assert {:error, :validation, _} = Accounts.delete_account(ben_account, "not the passphrase")
      assert :ok = Accounts.delete_account(ben_account, @pass)

      for [t] <- Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public'").rows,
          t not in ["audit_events", "schema_migrations"] do
        dumped = Repo.query!(~s(SELECT * FROM "#{t}")).rows |> List.flatten()
        refute Ecto.UUID.dump!(ben_account) in dumped, "#{t} still names the account"
        refute Ecto.UUID.dump!(ben) in dumped, "#{t} still names the membership"
      end

      ops =
        Repo.all(from(e in AuditEvent, where: e.account_id == ^ben_account, select: e.operation))

      assert "account_deleted" in ops
    end

    test "the last member leaving removes the household" do
      h = household(@form, ~w(ana))
      hh = session(h["ana"]).membership.household_id
      {:ok, _} = Households.leave(scope(@form, h, "ana"))
      refute Repo.exists?(from(x in FindependenceHosted.Schemas.Household, where: x.id == ^hh))
    end
  end

  describe "REQ-187 AC-1: what is stored" do
    test "after a visit adding every kind of information, no table holds what was entered" do
      h = household(@form, ~w(ana ben))
      ana = fn -> scope(@form, h, "ana") end
      # identifiers are structure, stored plainly; the transport makes them random, as here
      [acct, debt, plan] = for _ <- 1..3, do: FindependenceShared.Persistence.new_id()

      rent =
        add_item(@form, h, "ana", "Zanzibar rent 7731", amount: -98_765_432, on: "2026-09-17")

      pay = add_item(@form, h, "ana", "Quokka salary 4412", amount: 87_654_321)
      {:ok, v} = Values.add_value(ana.(), "Pelican security 5519")

      value =
        Enum.find_value(v.household.items, fn {id, i} ->
          if i.attrs[:label] == "Pelican security 5519", do: id
        end)

      {:ok, _} = Values.link(ana.(), rent, value)
      {:ok, _} = Balances.add_account(ana.(), acct, "Marmoset checking 3301", :checking)
      {:ok, _} = Balances.add_debt(ana.(), debt, "Ocelot card 2290", :card)

      {:ok, _} =
        Balances.add_reading(ana.(), acct, %{
          balance: {:ok, 76_543_210, false},
          on: {:ok, "2026-08-23"},
          rate: nil,
          min_payment: nil
        })

      {:ok, _} =
        Balances.add_reading(ana.(), debt, %{
          balance: {:ok, 65_432_109, false},
          on: {:ok, "2026-08-24"},
          rate: {:ok, 2_199},
          min_payment: {:ok, 54_321}
        })

      {:ok, _} = Balances.attach(ana.(), rent, acct)
      {:ok, _} = Planning.mark(ana.(), rent, pay)
      {:ok, _} = Planning.new_plan(ana.(), plan, "Axolotl plan 6604")

      {:ok, _} =
        Planning.add_step(ana.(), plan, %{
          kind: "add",
          note: "Narwhal step 8812",
          amount: {:ok, 43_210_987},
          frequency: {:every, 1, :month},
          from: "2026-11"
        })

      {:ok, _} = Planning.set_fund_goal(ana.(), 7)
      {:ok, _} = Items.propose_grant(ana.(), rent, id(@form, h, "ben"))

      entered =
        ~w(Zanzibar Quokka Pelican Marmoset Ocelot Axolotl Narwhal 98765432 87654321 76543210 65432109
           43210987 54321 2199 2026-09-17 2026-08-23 2026-08-24 2026-11) ++
          ~w(checking card monthly value account debt)

      bytes = stored_bytes(@form, h)

      for word <- entered,
          do:
            refute(Enum.any?(bytes, &(:binary.match(&1, word) != :nomatch)), "#{word} is stored")

      # and the values really were kept: Ana reads them back
      assert view(@form, h, "ana").items[rent].attrs.note == "Zanzibar rent 7731"
    end
  end

  describe "REQ-187 AC-3: jobs and PubSub" do
    test "there is no job queue, and the contexts publish nothing" do
      refute Code.ensure_loaded?(Oban)
      lock = File.read!("mix.lock")
      refute lock =~ ~s("oban")

      :erlang.trace_pattern({Phoenix.PubSub, :broadcast, :_}, true, [:global])
      :erlang.trace_pattern({Phoenix.PubSub, :broadcast_from, :_}, true, [:global])
      me = self()

      task =
        Task.async(fn ->
          receive do
            :go ->
              h = household(@form, ~w(ana ben))
              id = add_item(@form, h, "ana", "Secret rent")
              {:ok, _} = Items.propose_grant(scope(@form, h, "ana"), id, id(@form, h, "ben"))
          end
        end)

      :erlang.trace(task.pid, true, [:call, :set_on_spawn, {:tracer, me}])
      send(task.pid, :go)
      Task.await(task, 30_000)
      :erlang.trace_pattern({Phoenix.PubSub, :_, :_}, false, [:global])
      ref = :erlang.trace_delivered(:all)
      assert_receive {:trace_delivered, _, ^ref}, 5_000
      refute_received {:trace, _, :call, {Phoenix.PubSub, _, _}}
    end
  end
end
