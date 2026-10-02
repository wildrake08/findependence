defmodule FindependenceHosted.WI086Test do
  @moduledoc """
  WI-086 (CP-029, REV-114; ASSESS-002 re-run): each household's records as one block encrypted under a server key,
  with display names encrypted (REQ-200); the change counter kept outside the database and shown to members
  (REQ-198 AC-5; deliberately not shown to members); a key that doesn't match its account refused at sign-in (REQ-182 AC-5). The attacks are in
  test/assessment/assess002_test.exs; nobody becoming an owner without agreeing (REQ-115 as amended) is in the
  contract suite.
  """
  use FindependenceHostedWeb.DomainCase

  import Ecto.Query

  alias FindependenceHosted.{Accounts, Domain, Repo, Sessions, StateLedger, TestStore}
  alias FindependenceHosted.Schemas.{Account, Household, Membership}

  defp hid(h, name), do: elem(Sessions.fetch(h[name].token), 1).membership.household_id

  describe "REQ-198 AC-5: the change counter" do
    test "every change counts one more, recorded outside the database once committed" do
      h = household(~w(ana ben))
      hid = hid(h, "ana")
      before = Domain.version(hid)
      assert StateLedger.latest(hid) == before

      act(h, "ana", "/act/add_value", %{"label" => "A safe home"})
      assert Domain.version(hid) == before + 1
      assert StateLedger.latest(hid) == before + 1
      assert File.read!(StateLedger.path()) =~ "#{hid} #{before + 1}\n"
    end

    test "after a deliberate restore from backup, the reseal command brings the household back" do
      h = household(~w(ana))
      hid = hid(h, "ana")
      backup = TestStore.snapshot(hid)
      act(h, "ana", "/act/add_value", %{"label" => "After the backup"})
      act(h, "ana", "/act/add_value", %{"label" => "And another"})

      TestStore.restore(hid, backup)
      assert_raise FindependenceHosted.HouseholdTampered, fn -> Domain.load(hid) end

      assert :ok = FindependenceHosted.Release.reseal(hid, "CR-2026-003")
      assert %{} = Domain.load(hid)
      assert Domain.version(hid) > backup.household.version + 2
    end

    test "a counter below the one recorded is refused; one above it is accepted and recorded" do
      hid = Ecto.UUID.generate()
      :ok = StateLedger.record(hid, 5)
      assert StateLedger.check(hid, 4) == {:rolled_back, 5}
      assert StateLedger.check(hid, 5) == :ok
      assert StateLedger.check(hid, 6) == :ok
      assert StateLedger.latest(hid) == 6
    end

    test "members aren't shown the counter: it would count other members' private changes (REQ-106 AC-2)" do
      h = household(~w(ana ben))
      act(h, "ana", "/act/add_value", %{"label" => "Ana's private value"})
      body = page(h, "ben", "/household").resp_body
      refute body =~ "data-change"
      refute body =~ "records are at change"
    end
  end

  describe "REQ-200: what a database copy shows" do
    test "the records are one encrypted block, and names are encrypted, yet still unique in a household" do
      h = household(~w(ana ben))
      hid = hid(h, "ana")
      %Household{state_box: box} = Repo.get!(Household, hid)
      assert is_binary(box) and byte_size(box) > 28
      assert {:ok, %{items: %{}}} = Domain.open(hid)

      boxes = Repo.all(from(m in Membership, where: m.household_id == ^hid, select: m.name_box))
      refute Enum.any?(boxes, &(&1 =~ "Ana" or &1 =~ "Ben"))
      assert {:ok, names} = Domain.names(hid)
      assert names |> Map.values() |> Enum.sort() == ["Ana", "Ben"]

      # a second "Ben" can't join (the keyed hash's index)
      {:ok, code, _} =
        FindependenceHosted.Tenancy.create_invitation(elem(Sessions.fetch(h["ana"].token), 1))

      {:ok, _, number, _} =
        Accounts.sign_up(%{
          "passphrase" => "a long passphrase 1",
          "passphrase_confirmation" => "a long passphrase 1",
          "disclosure" => "true"
        })

      {:ok, t} = Accounts.sign_in(number, "a long passphrase 1", "test")

      assert {:error, :validation, {:display_name, _}} =
               FindependenceHosted.Tenancy.join(
                 t,
                 elem(Sessions.fetch(t), 1),
                 code,
                 "Ben",
                 "test"
               )
    end

    test "the operator's tools can still open the block for a review (DEPLOY.md section 8)" do
      h = household(~w(ana))
      act(h, "ana", "/act/add_value", %{"label" => "Review me"})
      held = TestStore.held(hid(h, "ana"))
      assert map_size(held.items) == 1
    end
  end

  describe "REQ-182 AC-5: a key that doesn't match its account" do
    test "is refused at sign-in with words saying the account was changed outside the service" do
      {:ok, id, number, _} =
        Accounts.sign_up(%{
          "passphrase" => "a long passphrase 1",
          "passphrase_confirmation" => "a long passphrase 1",
          "disclosure" => "true"
        })

      # a wrapped key copied from another account doesn't even open: it is bound to its account's id. What
      # someone with the database can change is the account's public key, which the opened key must match.
      from(a in Account, where: a.id == ^id)
      |> Repo.update_all(set: [public_key: elem(FindependenceShared.Crypto.keypair(), 0)])

      conn =
        post(build_conn(), "/sign-in", %{
          "account" => %{"account_number" => number, "passphrase" => "a long passphrase 1"}
        })

      assert html_response(conn, 401) =~ "changed outside this service"
    end
  end
end
