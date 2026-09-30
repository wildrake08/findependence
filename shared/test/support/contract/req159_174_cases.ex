defmodule FindependenceShared.Contract.B4 do
  @moduledoc """
  Helpers for the REQ-159..REQ-174 contract cases (REQ-188 AC-1, WI-074). Each takes the form module first,
  like `FindependenceShared.Contract.Helpers`.
  """

  import ExUnit.Assertions
  import FindependenceShared.Contract.Helpers

  alias FindependenceShared.{Balances, Households, Items, Persistence, Portability, Values}

  @doc "The fixed date the cases use as today."
  def today, do: ~D[2026-09-27]

  @doc "Adds an account for the named member and returns its id."
  def account(form, h, name, label, type) do
    id = Persistence.new_id()
    {:ok, _} = Balances.add_account(scope(form, h, name), id, label, type)
    id
  end

  @doc "Adds a debt for the named member and returns its id."
  def debt(form, h, name, label, type) do
    id = Persistence.new_id()
    {:ok, _} = Balances.add_debt(scope(form, h, name), id, label, type)
    id
  end

  @doc "Adds an account reading (cents, may be negative) as of `on`."
  def reading(form, h, name, id, cents, on) do
    input = %{balance: {:ok, abs(cents), cents < 0}, on: {:ok, on}}
    {:ok, _} = Balances.add_reading(scope(form, h, name), id, input)
  end

  @doc "Adds a debt reading: amount owed, rate in basis points, minimum payment, as of `on`."
  def debt_reading(form, h, name, id, owed, rate_bp, min, on) do
    input = %{
      balance: {:ok, owed, false},
      on: {:ok, on},
      rate: {:ok, rate_bp},
      min_payment: {:ok, min}
    }

    {:ok, _} = Balances.add_reading(scope(form, h, name), id, input)
  end

  @doc "Adds a value for the named member and returns its id."
  def value(form, h, name, label) do
    {:ok, saved} = Values.add_value(scope(form, h, name), label)
    by_label(saved.household, label)
  end

  @doc "The id of the entry with this label in a household view, or nil."
  def by_label(household, label),
    do: Enum.find_value(household.items, fn {id, i} -> if i.attrs[:label] == label, do: id end)

  @doc "Grants `item` from the named owner to the named member (one owner: applies at once)."
  def grant(form, h, owner, item, to),
    do: {:ok, _} = Items.propose_grant(scope(form, h, owner), item, id(form, h, to))

  @doc "Proposes the named members as the item's owners."
  def owners(form, h, owner, item, names),
    do: Items.propose_owners(scope(form, h, owner), item, Enum.map(names, &id(form, h, &1)))

  @doc "The id of a pending proposal on `item` that the named member can see, or nil."
  def proposal(form, h, name, item),
    do: Enum.find_value(Items.pending(scope(form, h, name)), &(&1.item_id == item && &1.id))

  @doc "The named member consents to the pending proposal on `item`."
  def consent(form, h, name, item) do
    p = proposal(form, h, name, item)
    assert p != nil
    {:ok, _} = Items.consent(scope(form, h, name), p)
  end

  @doc "The sealed state as stored, read through the named member's handle."
  def stored(form, h, name), do: form.stored(Map.fetch!(h, name))

  @doc "The member ids of these names, sorted."
  def ids(form, h, names), do: names |> Enum.map(&id(form, h, &1)) |> Enum.sort()

  @doc "Who holds a sealed key to the item's content, sorted."
  def key_holders(stored, item), do: stored.items[item].keys |> Map.keys() |> Enum.sort()

  @doc "For each stored ledger entry of the item, who holds a sealed key to it, sorted."
  def entry_readers(stored, item),
    do: for(e <- stored.items[item].ledger, do: e.keys |> Map.keys() |> Enum.sort())

  @doc "The member's saved file, as the transports write it."
  def export_bytes(scope),
    do: scope |> Portability.export() |> Portability.to_data() |> json()

  @doc "JSON bytes of data."
  def json(data), do: data |> :json.encode() |> IO.iodata_to_binary()

  @doc "Checks and brings in a file for the named member; returns the checked result."
  def bring_in!(form, h, name, bytes, today) do
    {:ok, %{bundle: b, fingerprint: fp} = checked} =
      Portability.check(scope(form, h, name), bytes)

    {:ok, _} = Portability.bring_in(scope(form, h, name), b, fp, today)
    checked
  end

  @doc "The notes or labels of items, sorted."
  def names(items), do: items |> Enum.map(&(&1.attrs[:note] || &1.attrs[:label])) |> Enum.sort()

  @doc "The notes of each day's entries in a cash flow, by date, for days with entries."
  def entries_by_day(flow),
    do:
      for(
        d <- flow.days,
        d.entries != [],
        into: %{},
        do: {d.date, Enum.map(d.entries, fn {i, _} -> i.attrs[:note] end) |> Enum.sort()}
      )

  @doc """
  REQ-171 AC-4: the item rules (REQ-101, REQ-103, REQ-105..REQ-108, REQ-110, REQ-125, REQ-167, REQ-169) on
  an account or a debt, for a household of ana, ben, and cy.
  """
  def item_rules(form, h, kind) do
    [a, b, c] = Enum.map(~w(ana ben cy), &id(form, h, &1))

    x =
      if kind == :account,
        do: account(form, h, "ana", "Joint checking", :checking),
        else: debt(form, h, "ana", "Car loan", :loan)

    # REQ-101: its creator owns it alone
    {:ok, i} = Items.get(scope(form, h, "ana"), x)
    assert i.owners == [a] and i.grantees == []

    # REQ-103 / REQ-167: a grant makes it readable; revoking ends that
    refute reads?(form, h, "ben", x)
    grant(form, h, "ana", x, "ben")
    assert reads?(form, h, "ben", x)
    {:ok, _} = Items.revoke_grant(scope(form, h, "ana"), x, b)
    refute reads?(form, h, "ben", x)
    assert Items.get(scope(form, h, "ben"), x) == {:error, :not_found}

    # REQ-107: owners change; a joint owner may relinquish
    {:ok, _} = owners(form, h, "ana", x, ~w(ana ben))
    {:ok, i} = Items.get(scope(form, h, "ben"), x)
    assert Enum.sort(i.owners) == Enum.sort([a, b])
    {:ok, _} = Items.relinquish(scope(form, h, "ben"), x)
    refute reads?(form, h, "ben", x)

    # REQ-125: a pending proposal can be withdrawn by an owner; nothing changes
    {:ok, _} = owners(form, h, "ana", x, ~w(ana ben))
    {:ok, _} = Items.propose_grant(scope(form, h, "ana"), x, c)
    p = proposal(form, h, "ana", x)
    assert p != nil
    refute reads?(form, h, "cy", x)
    {:ok, _} = Items.withdraw(scope(form, h, "ana"), p)
    assert Items.pending(scope(form, h, "ana")) == []
    refute reads?(form, h, "cy", x)

    # REQ-108: a joint owner can't delete it
    assert {:error, :unauthorized, :not_sole_owner, _} = Items.delete(scope(form, h, "ana"), x)

    # REQ-110: a grantee who leaves loses the grant; an owner can't leave
    {:ok, _} = Items.propose_grant(scope(form, h, "ana"), x, c)
    consent(form, h, "ben", x)
    assert reads?(form, h, "cy", x)
    {:ok, _} = Households.leave(scope(form, h, "cy"))
    {:ok, i} = Items.get(scope(form, h, "ana"), x)
    assert i.grantees == []
    assert {:error, _, :still_owner, _} = Households.leave(scope(form, h, "ben"))

    # REQ-105: the history
    {:ok, ledger} = Items.ledger(scope(form, h, "ana"), x)

    assert Enum.map(ledger, & &1.event) == [
             :created,
             :granted,
             :grant_revoked,
             :owners_changed,
             :owner_relinquished,
             :owners_changed,
             :granted,
             :grantee_departed
           ]

    # REQ-169: each owner's export contains it
    for n <- ~w(ana ben),
        do: assert(x in Enum.map(Portability.export(scope(form, h, n)).items, & &1.id))

    # REQ-108: once sole owner, it can be deleted; it is gone for everyone and from storage
    {:ok, _} = Items.relinquish(scope(form, h, "ben"), x)
    {:ok, _} = Items.delete(scope(form, h, "ana"), x)
    assert Items.get(scope(form, h, "ana"), x) == {:error, :not_found}
    assert Items.get(scope(form, h, "ben"), x) == {:error, :not_found}
    refute Map.has_key?(stored(form, h, "ana").items, x)
  end

  @doc """
  REQ-174: the named member (born 1950, retiring at 65, so already retired: the balance at retirement is
  the latest reading of their 401(k)) saves a target and a Social Security estimate; returns the projection.
  Options: :target, :ss, :return_bp (default 0), :balance (default 1,000,000 cents).
  """
  def retire(form, h, opts) do
    s = scope(form, h, "ana")

    k401 =
      case Balances.retirement_account_ids(s) do
        [k] -> k
        [] -> account(form, h, "ana", "401k", :retirement_401k)
      end

    reading(form, h, "ana", k401, Keyword.get(opts, :balance, 1_000_000), "2026-09-27")

    {:ok, _} =
      FindependenceShared.Planning.save_retirement(scope(form, h, "ana"), %{
        birth_year: {:ok, 1950},
        retire_age: {:ok, 65},
        return_bp: {:ok, Keyword.get(opts, :return_bp, 0)},
        ss_monthly: {:ok, Keyword.fetch!(opts, :ss)},
        target_monthly: {:ok, Keyword.fetch!(opts, :target)},
        contributions: []
      })

    FindependenceShared.Planning.retirement_projection(scope(form, h, "ana"), today())
  end
end

defmodule FindependenceShared.Contract.Cases.Req159To174 do
  @moduledoc """
  Contract cases for the CORE and PERSIST criteria of REQ-159..REQ-174 (REQ-188 AC-1, WI-074), run on both
  forms through the shared contexts.
  """

  defmacro __using__(_) do
    quote do
      alias FindependenceShared.Contract.B4

      describe "REQ-159" do
        test "REQ-159 AC-1: the same file brought in twice by the same member is refused with the date; nothing changes" do
          h = household(@form, ~w(ana ben))
          add_item(@form, h, "ana", "Rent", amount: -150_000)
          bytes = B4.export_bytes(scope(@form, h, "ana"))
          %{bundle: bundle, fingerprint: fp} = B4.bring_in!(@form, h, "ana", bytes, B4.today())

          before = B4.stored(@form, h, "ana")

          assert FindependenceShared.Portability.check(scope(@form, h, "ana"), bytes) ==
                   {:error, :conflict, {:already_imported, "2026-09-27"}}

          assert {:error, _, {:already_imported, "2026-09-27"}, _} =
                   FindependenceShared.Portability.bring_in(
                     scope(@form, h, "ana"),
                     bundle,
                     fp,
                     ~D[2026-10-01]
                   )

          assert B4.stored(@form, h, "ana") == before
          assert length(FindependenceShared.Items.visible(scope(@form, h, "ana"))) == 2
        end

        test "REQ-159 AC-2: a different file, or the same file brought in by another member, is not refused" do
          h = household(@form, ~w(ana ben))
          add_item(@form, h, "ana", "Rent", amount: -150_000)
          bytes = B4.export_bytes(scope(@form, h, "ana"))
          B4.bring_in!(@form, h, "ana", bytes, B4.today())

          # the same file, by another member
          assert {:ok, _} = FindependenceShared.Portability.check(scope(@form, h, "ben"), bytes)
          B4.bring_in!(@form, h, "ben", bytes, B4.today())

          # a different file, by the same member
          other = B4.export_bytes(scope(@form, h, "ana"))
          assert other != bytes
          assert {:ok, _} = FindependenceShared.Portability.check(scope(@form, h, "ana"), other)
          B4.bring_in!(@form, h, "ana", other, B4.today())

          assert length(FindependenceShared.Items.visible(scope(@form, h, "ana"))) == 4
          assert length(FindependenceShared.Items.visible(scope(@form, h, "ben"))) == 1
        end

        test "REQ-159 AC-3: bringing a record in changes nothing anyone else owns or can see" do
          h = household(@form, ~w(ana ben))
          add_item(@form, h, "ben", "Ben's gym", amount: -4_000)
          shared = add_item(@form, h, "ana", "Groceries", amount: -60_000)
          B4.grant(@form, h, "ana", shared, "ben")
          add_item(@form, h, "ana", "Rent", amount: -150_000)
          b = id(@form, h, "ben")

          ben_before = FindependenceShared.Items.visible(scope(@form, h, "ben"))
          owned = fn items -> for i <- items, b in i.owners, do: i end
          bytes = B4.export_bytes(scope(@form, h, "ana"))
          B4.bring_in!(@form, h, "ana", bytes, B4.today())

          ben_after = FindependenceShared.Items.visible(scope(@form, h, "ben"))
          assert ben_after == ben_before
          assert owned.(ben_after) == owned.(ben_before)
          assert length(FindependenceShared.Items.visible(scope(@form, h, "ana"))) == 4

          new =
            for {id, _} <- view(@form, h, "ana").items,
                id not in Enum.map(ben_before, & &1.id),
                do: id

          assert length(new) == 3
          for id <- new, do: refute(reads?(@form, h, "ben", id))
        end
      end

      describe "REQ-160" do
        test "REQ-160 AC-1: a money item can go through a checking, savings, or 'other' account" do
          h = household(@form, ~w(ana))
          item = add_item(@form, h, "ana", "Rent")

          for type <- [:checking, :savings, :other] do
            acct = B4.account(@form, h, "ana", "Account #{type}", type)
            ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), item, acct))

            assert FindependenceShared.Balances.attached(scope(@form, h, "ana")) == %{
                     item => acct
                   }
          end
        end

        test "REQ-160 AC-2: a retirement account or a debt can't be chosen" do
          h = household(@form, ~w(ana))
          item = add_item(@form, h, "ana", "Rent")

          for acct <- [
                B4.account(@form, h, "ana", "401k", :retirement_401k),
                B4.account(@form, h, "ana", "IRA", :ira),
                B4.debt(@form, h, "ana", "Card", :card)
              ] do
            assert {:error, :validation, :not_a_cash_account, _} =
                     FindependenceShared.Balances.attach(scope(@form, h, "ana"), item, acct)
          end

          assert FindependenceShared.Balances.attached(scope(@form, h, "ana")) == %{}
        end

        test "REQ-160 AC-3: visible money items and accounts qualify, shared ones too; the invisible and non-money are refused" do
          h = household(@form, ~w(ana ben))
          bens = add_item(@form, h, "ben", "Ben's phone")
          ben_chk = B4.account(@form, h, "ben", "Ben's checking", :checking)
          B4.grant(@form, h, "ben", bens, "ana")
          B4.grant(@form, h, "ben", ben_chk, "ana")
          hidden_item = add_item(@form, h, "ben", "Ben's secret")
          hidden_acct = B4.account(@form, h, "ben", "Ben's savings", :savings)
          mine = add_item(@form, h, "ana", "Rent")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          v = B4.value(@form, h, "ana", "A safe home")
          card = B4.debt(@form, h, "ana", "Card", :card)
          attach = &FindependenceShared.Balances.attach(scope(@form, h, "ana"), &1, &2)

          ok!(attach.(bens, ben_chk))
          ok!(attach.(mine, ben_chk))
          ok!(attach.(bens, chk))

          assert FindependenceShared.Balances.attached(scope(@form, h, "ana")) == %{
                   bens => chk,
                   mine => ben_chk
                 }

          assert {:error, :not_found, :not_found, _} = attach.(hidden_item, chk)
          assert {:error, :not_found, :not_found, _} = attach.(mine, hidden_acct)

          for not_money <- [v, chk, card],
              do: assert({:error, :validation, :not_money, _} = attach.(not_money, chk))
        end

        test "REQ-160 AC-4: changing the account replaces the first" do
          h = household(@form, ~w(ana))
          item = add_item(@form, h, "ana", "Rent")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          sav = B4.account(@form, h, "ana", "Savings", :savings)
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), item, chk))
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), item, sav))
          assert FindependenceShared.Balances.attached(scope(@form, h, "ana")) == %{item => sav}
        end

        test "REQ-160 AC-5: the member can clear it" do
          h = household(@form, ~w(ana))
          item = add_item(@form, h, "ana", "Rent")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), item, chk))
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), item, nil))
          assert FindependenceShared.Balances.attached(scope(@form, h, "ana")) == %{}
        end

        test "REQ-160 AC-6: only the member sees it" do
          h = household(@form, ~w(ana ben))
          item = add_item(@form, h, "ana", "Rent")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          B4.grant(@form, h, "ana", item, "ben")
          B4.grant(@form, h, "ana", chk, "ben")
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), item, chk))

          assert FindependenceShared.Balances.attached(scope(@form, h, "ana")) == %{item => chk}
          assert FindependenceShared.Balances.attached(scope(@form, h, "ben")) == %{}

          assert FindependenceShared.Planning.goals(scope(@form, h, "ben"))[:attached] in [
                   nil,
                   %{}
                 ]
        end

        test "REQ-160 AC-7: deleting the item or the account removes it, whoever deletes" do
          h = household(@form, ~w(ana ben))
          item = add_item(@form, h, "ana", "Rent")
          other = add_item(@form, h, "ana", "Phone")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          ben_chk = B4.account(@form, h, "ben", "Ben's checking", :checking)
          ben_item = add_item(@form, h, "ben", "Ben's gym")
          B4.grant(@form, h, "ben", ben_chk, "ana")
          B4.grant(@form, h, "ben", ben_item, "ana")
          attach = &FindependenceShared.Balances.attach(scope(@form, h, "ana"), &1, &2)
          ok!(attach.(item, chk))
          ok!(attach.(other, ben_chk))
          ok!(attach.(ben_item, chk))

          ok!(FindependenceShared.Items.delete(scope(@form, h, "ana"), item))

          assert FindependenceShared.Balances.attached(scope(@form, h, "ana")) == %{
                   other => ben_chk,
                   ben_item => chk
                 }

          ok!(FindependenceShared.Items.delete(scope(@form, h, "ben"), ben_chk))
          ok!(FindependenceShared.Items.delete(scope(@form, h, "ben"), ben_item))
          assert FindependenceShared.Balances.attached(scope(@form, h, "ana")) == %{}
        end

        test "REQ-160 AC-8: leaving removes all of the member's own, though the item and account remain" do
          h = household(@form, ~w(ana ben))
          item = add_item(@form, h, "ana", "Rent")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          B4.grant(@form, h, "ana", item, "ben")
          B4.grant(@form, h, "ana", chk, "ben")
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ben"), item, chk))
          assert FindependenceShared.Balances.attached(scope(@form, h, "ben")) == %{item => chk}
          b = id(@form, h, "ben")
          assert Map.has_key?(B4.stored(@form, h, "ana").personal, b)

          ok!(FindependenceShared.Households.leave(scope(@form, h, "ben")))

          s = B4.stored(@form, h, "ana")
          refute Map.has_key?(s.personal, b)
          assert Map.has_key?(s.items, item) and Map.has_key?(s.items, chk)
        end
      end

      describe "REQ-161" do
        test "REQ-161 AC-5: the dated items that count: attached to a visible checking account, or owned and unattached" do
          h = household(@form, ~w(ana ben))
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          sav = B4.account(@form, h, "ana", "Savings", :savings)
          on = fn d -> [amount: -100, frequency: :one_off, on: d] end
          add_item(@form, h, "ana", "Own", on.("2026-10-03"))
          via_chk = add_item(@form, h, "ana", "Via checking", on.("2026-10-04"))
          via_sav = add_item(@form, h, "ana", "Via savings", on.("2026-10-05"))
          bens = add_item(@form, h, "ben", "Ben's", on.("2026-10-06"))
          B4.grant(@form, h, "ben", bens, "ana")
          attach = &FindependenceShared.Balances.attach(scope(@form, h, "ana"), &1, &2)
          ok!(attach.(via_chk, chk))
          ok!(attach.(via_sav, sav))

          flow = fn ->
            FindependenceShared.CashFlow.cash_flow(scope(@form, h, "ana"), ~D[2026-10-01], 14)
          end

          assert B4.entries_by_day(flow.()) == %{
                   ~D[2026-10-03] => ["Own"],
                   ~D[2026-10-04] => ["Via checking"]
                 }

          ok!(attach.(bens, chk))

          assert B4.entries_by_day(flow.()) == %{
                   ~D[2026-10-03] => ["Own"],
                   ~D[2026-10-04] => ["Via checking"],
                   ~D[2026-10-06] => ["Ben's"]
                 }
        end

        test "REQ-161 AC-6: the running balance of the member's visible checking accounts only; none without one" do
          h = household(@form, ~w(ana ben cy))
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          sav = B4.account(@form, h, "ana", "Savings", :savings)
          ben_chk = B4.account(@form, h, "ben", "Ben's checking", :checking)
          B4.reading(@form, h, "ana", chk, 100_000, "2026-09-30")
          B4.reading(@form, h, "ana", sav, 900_000, "2026-09-30")
          B4.reading(@form, h, "ben", ben_chk, 50_000, "2026-09-30")

          add_item(@form, h, "ana", "Rent",
            amount: -120_000,
            frequency: :one_off,
            on: "2026-10-02"
          )

          flow = fn n ->
            FindependenceShared.CashFlow.cash_flow(scope(@form, h, n), ~D[2026-10-01], 3)
          end

          %{start: start, days: days} = flow.("ana")
          assert start.balance == 100_000 and start.accounts == [chk]
          assert Enum.map(days, & &1.balance) == [100_000, -20_000, -20_000]

          B4.grant(@form, h, "ben", ben_chk, "ana")
          %{start: start, days: days} = flow.("ana")
          assert start.balance == 150_000 and start.accounts == Enum.sort([chk, ben_chk])
          assert Enum.map(days, & &1.balance) == [150_000, 30_000, 30_000]

          # without a visible checking account with a reading, no balance
          add_item(@form, h, "cy", "Cy's bill",
            amount: -100,
            frequency: :one_off,
            on: "2026-10-02"
          )

          %{start: nil, days: days} = flow.("cy")
          assert Enum.all?(days, &(&1.balance == nil))
        end

        test "REQ-161 AC-7: starts from the sum of the latest readings and applies every occurrence after the most recent date" do
          h = household(@form, ~w(ana ben))
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          ben_chk = B4.account(@form, h, "ben", "Ben's checking", :checking)
          B4.grant(@form, h, "ben", ben_chk, "ana")
          B4.reading(@form, h, "ana", chk, 999_999, "2026-09-20")
          B4.reading(@form, h, "ana", chk, 100_000, "2026-09-28")
          B4.reading(@form, h, "ben", ben_chk, 50_000, "2026-09-30")
          # before and on the most recent reading's date: already in the readings
          add_item(@form, h, "ana", "Gym",
            amount: -1_000,
            frequency: {:every, 1, :month},
            on: "2026-09-29"
          )

          add_item(@form, h, "ana", "Fee", amount: -7, frequency: :one_off, on: "2026-09-30")
          # after it, but before the first day shown
          add_item(@form, h, "ana", "Bonus", amount: 5_000, frequency: :one_off, on: "2026-10-01")

          %{start: start, days: days} =
            FindependenceShared.CashFlow.cash_flow(scope(@form, h, "ana"), ~D[2026-10-02], 28)

          assert start == %{
                   balance: 150_000,
                   on: ~D[2026-09-30],
                   accounts: Enum.sort([chk, ben_chk])
                 }

          by = Map.new(days, &{&1.date, &1.balance})
          assert by[~D[2026-10-02]] == 155_000
          assert by[~D[2026-10-28]] == 155_000
          assert by[~D[2026-10-29]] == 154_000
        end
      end

      describe "REQ-162" do
        test "REQ-162 AC-1: each of the next twelve months, from the month after this one" do
          h = household(@form, ~w(ana))
          p = FindependenceShared.CashFlow.project(scope(@form, h, "ana"), B4.today())
          months = Enum.map(p.months, & &1.month)
          assert length(months) == 12
          assert hd(months) == "2026-10" and List.last(months) == "2027-09"
          assert months == FindependenceShared.CashFlow.months(B4.today())
        end

        test "REQ-162 AC-2: money in and out counts attached items and the member's own unattached ones" do
          h = household(@form, ~w(ana ben))
          sav = B4.account(@form, h, "ana", "Savings", :savings)
          add_item(@form, h, "ana", "Own", amount: -1_000, frequency: {:every, 1, :month})

          bens =
            add_item(@form, h, "ben", "Ben's", amount: -7_000, frequency: {:every, 1, :month})

          B4.grant(@form, h, "ben", bens, "ana")

          out = fn ->
            FindependenceShared.CashFlow.project(scope(@form, h, "ana"), B4.today()).months
            |> Enum.map(& &1.out)
          end

          assert out.() == List.duplicate(-1_000, 12)
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), bens, sav))
          assert out.() == List.duplicate(-8_000, 12)
        end

        test "REQ-162 AC-3: repeating items per month; a dated one-off in its month; an undated one-off in none" do
          h = household(@form, ~w(ana))
          add_item(@form, h, "ana", "Rent", amount: -1_000, frequency: {:every, 1, :month})
          add_item(@form, h, "ana", "Water", amount: -3_000, frequency: {:every, 3, :month})

          add_item(@form, h, "ana", "Sofa",
            amount: -80_000,
            frequency: :one_off,
            on: "2027-01-15"
          )

          add_item(@form, h, "ana", "TV", amount: -50_000, frequency: :one_off)

          months = FindependenceShared.CashFlow.project(scope(@form, h, "ana"), B4.today()).months
          assert FindependenceShared.CashFlow.per_month(-3_000, {:every, 3, :month}) == -1_000

          assert Enum.map(months, & &1.out) ==
                   [-2_000, -2_000, -2_000, -82_000] ++ List.duplicate(-2_000, 8)
        end

        test "REQ-162 AC-4: cash starts from the latest balances of the cash accounts the member can see" do
          h = household(@form, ~w(ana ben))
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          sav = B4.account(@form, h, "ana", "Savings", :savings)
          ira = B4.account(@form, h, "ana", "IRA", :ira)
          ben_chk = B4.account(@form, h, "ben", "Ben's checking", :checking)
          B4.reading(@form, h, "ana", chk, 1, "2026-09-01")
          B4.reading(@form, h, "ana", chk, 100_000, "2026-09-27")
          B4.reading(@form, h, "ana", sav, 200_000, "2026-09-20")
          B4.reading(@form, h, "ana", ira, 1_000_000, "2026-09-20")
          B4.reading(@form, h, "ben", ben_chk, 50_000, "2026-09-20")
          add_item(@form, h, "ana", "Rent", amount: -1_000, frequency: {:every, 1, :month})

          p = FindependenceShared.CashFlow.project(scope(@form, h, "ana"), B4.today())
          assert p.start.cash == 300_000
          assert p.start.accounts == Enum.sort([chk, sav])
          assert Enum.map(p.months, & &1.cash) == for(k <- 1..12, do: 300_000 - 1_000 * k)
        end

        test "REQ-162 AC-5: each visible debt grows by a month's interest and falls by its minimum payment" do
          h = household(@form, ~w(ana ben))
          visa = B4.debt(@form, h, "ana", "Visa", :card)
          B4.debt_reading(@form, h, "ana", visa, 620_000, 2499, 19_000, "2026-09-27")
          loan = B4.debt(@form, h, "ben", "Car loan", :loan)
          B4.debt_reading(@form, h, "ben", loan, 900_000, 500, 30_000, "2026-09-27")

          project = fn n ->
            FindependenceShared.CashFlow.project(scope(@form, h, n), B4.today())
          end

          assert [%{id: ^visa} = d] = project.("ana").debts
          i = FindependenceShared.Balances.monthly_interest(%{balance: 620_000, rate_bp: 2499})
          assert hd(d.months) == 620_000 + i - 19_000

          B4.grant(@form, h, "ben", loan, "ana")
          debts = project.("ana").debts
          assert Enum.map(debts, & &1.id) == [loan, visa]
          assert hd(debts) == hd(project.("ben").debts)
        end

        test "REQ-162 AC-6: until paid off; then zero with no more interest, and the month it is paid off" do
          h = household(@form, ~w(ana))
          loan = B4.debt(@form, h, "ana", "Small loan", :loan)
          B4.debt_reading(@form, h, "ana", loan, 50_000, 1200, 20_000, "2026-09-27")

          [d] = FindependenceShared.CashFlow.project(scope(@form, h, "ana"), B4.today()).debts
          assert Enum.take(d.months, 3) == [30_500, 10_805, 0]
          assert Enum.drop(d.months, 3) == List.duplicate(0, 9)
          assert d.paid_off == "2026-12"
          assert d.interest == 500 + 305 + 108
        end
      end

      describe "REQ-164" do
        test "REQ-164 AC-1: the file carries attachments where the member owns both item and account, only those" do
          h = household(@form, ~w(ana ben))
          pay = add_item(@form, h, "ana", "Paycheck", amount: 265_000)
          rent = add_item(@form, h, "ana", "Rent")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          ben_sav = B4.account(@form, h, "ben", "Ben's savings", :savings)
          bens = add_item(@form, h, "ben", "Ben's gym")
          B4.grant(@form, h, "ben", ben_sav, "ana")
          B4.grant(@form, h, "ben", bens, "ana")
          attach = &FindependenceShared.Balances.attach(scope(@form, h, "ana"), &1, &2)
          ok!(attach.(pay, chk))
          ok!(attach.(rent, ben_sav))
          ok!(attach.(bens, chk))

          e = FindependenceShared.Portability.export(scope(@form, h, "ana"))
          assert e.attached == [{pay, chk}]

          assert FindependenceShared.Portability.to_data(e)["attached"] == [
                   %{"item" => pay, "account" => chk}
                 ]
        end

        test "REQ-164 AC-2: bringing the file in restores those attachments between the new entries" do
          h = household(@form, ~w(ana ben))
          pay = add_item(@form, h, "ana", "Paycheck", amount: 265_000)
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), pay, chk))
          bytes = B4.export_bytes(scope(@form, h, "ana"))

          B4.bring_in!(@form, h, "ben", bytes, B4.today())
          v = view(@form, h, "ben")
          new_pay = find(v, "Paycheck")
          new_chk = B4.by_label(v, "Checking")
          assert new_pay not in [nil, pay] and new_chk not in [nil, chk]

          assert FindependenceShared.Balances.attached(scope(@form, h, "ben")) == %{
                   new_pay => new_chk
                 }
        end

        test "REQ-164 AC-3: the file names its format version as 3" do
          h = household(@form, ~w(ana))
          add_item(@form, h, "ana", "Rent")
          data = :json.decode(B4.export_bytes(scope(@form, h, "ana")))
          assert data["format"] == "findependence-export" and data["version"] == 3
        end

        test "REQ-164 AC-4: versions 1 and 2 still come in, without attachments; a version 2 file naming them is refused" do
          h = household(@form, ~w(ana ben))
          pay = add_item(@form, h, "ana", "Paycheck", amount: 265_000)
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), pay, chk))

          data =
            scope(@form, h, "ana")
            |> FindependenceShared.Portability.export()
            |> FindependenceShared.Portability.to_data()

          check = &FindependenceShared.Portability.check(scope(@form, h, "ben"), B4.json(&1))

          assert {:error, :validation, {:problems, problems}} =
                   check.(Map.put(data, "version", 2))

          assert {"attached", :unknown_field} in problems

          v2 = data |> Map.put("version", 2) |> Map.delete("attached")
          assert {:ok, _} = check.(v2)
          B4.bring_in!(@form, h, "ben", B4.json(v2), B4.today())
          assert find(view(@form, h, "ben"), "Paycheck") != nil
          assert FindependenceShared.Balances.attached(scope(@form, h, "ben")) == %{}

          v1 = %{
            "member" => "old",
            "items" => [
              %{
                "id" => "a",
                "attrs" => %{
                  "note" => "Old rent",
                  "amount" => -150_000,
                  "unit" => "cents",
                  "frequency" => "monthly"
                },
                "owners" => ["old"],
                "grantees" => []
              }
            ],
            "links" => []
          }

          assert {:ok, _} = check.(v1)
          B4.bring_in!(@form, h, "ben", B4.json(v1), B4.today())
          assert find(view(@form, h, "ben"), "Old rent") != nil
          assert FindependenceShared.Balances.attached(scope(@form, h, "ben")) == %{}
        end
      end

      describe "REQ-167" do
        test "REQ-167 AC-1: an owner can read the item" do
          h = household(@form, ~w(ana ben))
          item = add_item(@form, h, "ana", "Rent", amount: -150_000)

          {:ok, _} =
            FindependenceShared.Items.propose_owners(
              scope(@form, h, "ana"),
              item,
              B4.ids(@form, h, ~w(ana ben))
            )

          for n <- ~w(ana ben) do
            assert reads?(@form, h, n, item)
            assert FindependenceShared.Items.visible?(scope(@form, h, n), item)

            assert {:ok, %{attrs: %{note: "Rent", amount: -150_000}}} =
                     FindependenceShared.Items.get(scope(@form, h, n), item)
          end

          assert B4.key_holders(B4.stored(@form, h, "ana"), item) == B4.ids(@form, h, ~w(ana ben))
        end

        test "REQ-167 AC-2: a member holding an active grant can read it" do
          h = household(@form, ~w(ana ben cy))
          item = add_item(@form, h, "ana", "Rent")
          {:ok, _} = B4.owners(@form, h, "ana", item, ~w(ana ben))

          {:ok, _} =
            FindependenceShared.Items.propose_grant(
              scope(@form, h, "ana"),
              item,
              id(@form, h, "cy")
            )

          refute reads?(@form, h, "cy", item)
          B4.consent(@form, h, "ben", item)
          assert reads?(@form, h, "cy", item)

          assert {:ok, %{attrs: %{note: "Rent"}}} =
                   FindependenceShared.Items.get(scope(@form, h, "cy"), item)
        end

        test "REQ-167 AC-3: a member being added to a value, once every current owner agreed, can read it" do
          h = household(@form, ~w(ana ben cy))
          v = B4.value(@form, h, "ana", "A safe home")
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana ben))
          B4.consent(@form, h, "ben", v)
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana ben cy))
          refute reads?(@form, h, "cy", v)
          B4.consent(@form, h, "ben", v)

          # cy has not agreed yet
          assert B4.proposal(@form, h, "ana", v) != nil
          assert reads?(@form, h, "cy", v)

          assert %{attrs: %{label: "A safe home"}} =
                   FindependenceShared.Items.lookup(scope(@form, h, "cy"), v)

          assert id(@form, h, "cy") in B4.key_holders(B4.stored(@form, h, "ana"), v)
        end

        test "REQ-167 AC-4: the same for a shared plan" do
          h = household(@form, ~w(ana ben))
          ok!(FindependenceShared.Planning.new_plan(scope(@form, h, "ana"), "p1", "If pay stops"))

          ok!(
            FindependenceShared.Planning.share_plan(scope(@form, h, "ana"), "p1", [
              id(@form, h, "ben")
            ])
          )

          sp = B4.by_label(view(@form, h, "ana"), "If pay stops")
          assert B4.proposal(@form, h, "ana", sp) != nil
          assert reads?(@form, h, "ben", sp)

          assert %{attrs: %{kind: :plan, label: "If pay stops"}} =
                   FindependenceShared.Items.lookup(scope(@form, h, "ben"), sp)

          assert B4.key_holders(B4.stored(@form, h, "ana"), sp) == B4.ids(@form, h, ~w(ana ben))
        end

        test "REQ-167 AC-5: nobody else can read it; an invisible item reads like a missing one" do
          h = household(@form, ~w(ana ben cy dee))
          c = id(@form, h, "cy")
          # no role
          item = add_item(@form, h, "ana", "Rent")
          refute reads?(@form, h, "cy", item)

          assert FindependenceShared.Items.get(scope(@form, h, "cy"), item) ==
                   FindependenceShared.Items.get(scope(@form, h, "cy"), "no-such-item")

          assert FindependenceShared.Items.get(scope(@form, h, "cy"), item) ==
                   {:error, :not_found}

          refute FindependenceShared.Items.visible?(scope(@form, h, "cy"), item)
          refute FindependenceShared.Items.visible?(scope(@form, h, "cy"), "no-such-item")

          refute item in Enum.map(
                   FindependenceShared.Items.visible(scope(@form, h, "cy")),
                   & &1.id
                 )

          # a former grantee
          B4.grant(@form, h, "ana", item, "cy")
          ok!(FindependenceShared.Items.revoke_grant(scope(@form, h, "ana"), item, c))
          refute reads?(@form, h, "cy", item)

          # a former owner
          {:ok, _} = B4.owners(@form, h, "ana", item, ~w(ana ben))
          ok!(FindependenceShared.Items.relinquish(scope(@form, h, "ben"), item))
          refute reads?(@form, h, "ben", item)

          # named in a pending owner change on an ordinary item, or in a pending grant
          {:ok, _} = B4.owners(@form, h, "ana", item, ~w(ana dee))
          {:ok, _} = B4.owners(@form, h, "ana", item, ~w(ana dee cy))
          refute reads?(@form, h, "cy", item)

          {:ok, _} =
            FindependenceShared.Items.propose_grant(
              scope(@form, h, "ana"),
              item,
              id(@form, h, "ben")
            )

          refute reads?(@form, h, "ben", item)

          # invited to a value, or to a shared plan, before every current owner agreed
          v = B4.value(@form, h, "ana", "A safe home")
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana dee))
          B4.consent(@form, h, "dee", v)
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana dee cy))
          refute reads?(@form, h, "cy", v)

          ok!(FindependenceShared.Planning.new_plan(scope(@form, h, "ana"), "p1", "If pay stops"))

          ok!(
            FindependenceShared.Planning.share_plan(scope(@form, h, "ana"), "p1", [
              id(@form, h, "dee")
            ])
          )

          sp = B4.by_label(view(@form, h, "ana"), "If pay stops")
          B4.consent(@form, h, "dee", sp)
          {:ok, _} = B4.owners(@form, h, "ana", sp, ~w(ana dee cy))
          refute reads?(@form, h, "cy", sp)

          s = B4.stored(@form, h, "ana")
          for id <- [item, v, sp], do: refute(c in B4.key_holders(s, id))
          refute id(@form, h, "ben") in B4.key_holders(s, item)
        end

        test "REQ-167 AC-6: an invitee's access ends when the proposal is withdrawn" do
          h = household(@form, ~w(ana ben))
          v = B4.value(@form, h, "ana", "A safe home")
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana ben))
          assert reads?(@form, h, "ben", v)
          p = B4.proposal(@form, h, "ana", v)
          ok!(FindependenceShared.Items.withdraw(scope(@form, h, "ana"), p))
          refute reads?(@form, h, "ben", v)
          assert FindependenceShared.Items.lookup(scope(@form, h, "ben"), v).attrs == %{}
          assert B4.key_holders(B4.stored(@form, h, "ana"), v) == [id(@form, h, "ana")]
        end
      end

      describe "REQ-168" do
        test "REQ-168 AC-1: any visible money item can be linked to any visible value" do
          h = household(@form, ~w(ana ben))

          monthly =
            add_item(@form, h, "ana", "Rent", amount: -1_000, frequency: {:every, 1, :month})

          one_off = add_item(@form, h, "ana", "Sofa", amount: -80_000, frequency: :one_off)
          irregular = add_item(@form, h, "ana", "Repairs", amount: -60_000, frequency: :irregular)
          joint = add_item(@form, h, "ben", "Groceries")
          {:ok, _} = B4.owners(@form, h, "ben", joint, ~w(ben ana))
          shared = add_item(@form, h, "ben", "Ben's phone")
          B4.grant(@form, h, "ben", shared, "ana")

          own_v = B4.value(@form, h, "ana", "Health")
          joint_v = B4.value(@form, h, "ben", "Family")
          {:ok, _} = B4.owners(@form, h, "ben", joint_v, ~w(ben ana))
          B4.consent(@form, h, "ana", joint_v)
          granted_v = B4.value(@form, h, "ben", "Learning")
          B4.grant(@form, h, "ben", granted_v, "ana")

          pairs =
            for i <- [monthly, one_off, irregular, joint, shared],
                v <- [own_v, joint_v, granted_v],
                do: {i, v}

          for {i, v} <- pairs,
              do: ok!(FindependenceShared.Values.link(scope(@form, h, "ana"), i, v))

          assert Enum.sort(FindependenceShared.Values.links(scope(@form, h, "ana"))) ==
                   Enum.sort(pairs)
        end

        test "REQ-168 AC-2: they can unlink any of their links" do
          h = household(@form, ~w(ana))
          i = add_item(@form, h, "ana", "Rent")
          v = B4.value(@form, h, "ana", "Health")
          w = B4.value(@form, h, "ana", "Family")
          ok!(FindependenceShared.Values.link(scope(@form, h, "ana"), i, v))
          ok!(FindependenceShared.Values.link(scope(@form, h, "ana"), i, w))
          ok!(FindependenceShared.Values.unlink(scope(@form, h, "ana"), i, v))
          assert FindependenceShared.Values.links(scope(@form, h, "ana")) == [{i, w}]
          ok!(FindependenceShared.Values.unlink(scope(@form, h, "ana"), i, w))
          assert FindependenceShared.Values.links(scope(@form, h, "ana")) == []
        end

        test "REQ-168 AC-3: a value, an account or debt, or a shared plan can't be linked as the item" do
          h = household(@form, ~w(ana ben))
          v = B4.value(@form, h, "ana", "Health")
          w = B4.value(@form, h, "ana", "Family")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          card = B4.debt(@form, h, "ana", "Card", :card)
          ok!(FindependenceShared.Planning.new_plan(scope(@form, h, "ana"), "p1", "If pay stops"))

          ok!(
            FindependenceShared.Planning.share_plan(scope(@form, h, "ana"), "p1", [
              id(@form, h, "ben")
            ])
          )

          sp = B4.by_label(view(@form, h, "ana"), "If pay stops")
          link = &FindependenceShared.Values.link(scope(@form, h, "ana"), &1, v)

          assert {:error, :validation, :cannot_link_a_value, _} = link.(w)
          assert {:error, :validation, :cannot_link_a_balance, _} = link.(chk)
          assert {:error, :validation, :cannot_link_a_balance, _} = link.(card)
          assert {:error, :validation, :cannot_link_a_plan, _} = link.(sp)
          assert FindependenceShared.Values.links(scope(@form, h, "ana")) == []
        end

        test "REQ-168 AC-4: links belong to their member: made independently, and nobody else can unlink them" do
          h = household(@form, ~w(ana ben))
          i = add_item(@form, h, "ana", "Groceries")
          {:ok, _} = B4.owners(@form, h, "ana", i, ~w(ana ben))
          v = B4.value(@form, h, "ana", "Family")
          B4.grant(@form, h, "ana", v, "ben")

          ok!(FindependenceShared.Values.link(scope(@form, h, "ana"), i, v))
          ok!(FindependenceShared.Values.link(scope(@form, h, "ben"), i, v))
          assert FindependenceShared.Values.links(scope(@form, h, "ana")) == [{i, v}]
          assert FindependenceShared.Values.links(scope(@form, h, "ben")) == [{i, v}]

          ok!(FindependenceShared.Values.unlink(scope(@form, h, "ben"), i, v))
          assert FindependenceShared.Values.links(scope(@form, h, "ben")) == []
          assert FindependenceShared.Values.links(scope(@form, h, "ana")) == [{i, v}]

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Values.unlink(scope(@form, h, "ben"), i, v)

          assert FindependenceShared.Values.links(scope(@form, h, "ana")) == [{i, v}]
        end

        test "REQ-168 AC-5: no other member can read them, even seeing or later owning both ends" do
          h = household(@form, ~w(ana ben))
          i = add_item(@form, h, "ana", "Groceries", amount: -60_000)
          v = B4.value(@form, h, "ana", "Family")
          B4.grant(@form, h, "ana", i, "ben")
          B4.grant(@form, h, "ana", v, "ben")
          a = id(@form, h, "ana")

          ben = fn ->
            s = scope(@form, h, "ben")

            {FindependenceShared.Values.links(s), FindependenceShared.Values.distribution(s),
             FindependenceShared.Portability.export(s)}
          end

          before = ben.()
          ok!(FindependenceShared.Values.link(scope(@form, h, "ana"), i, v))
          assert ben.() == before
          refute Map.has_key?(view(@form, h, "ben").links, a)

          # later owned by ben too
          {:ok, _} = B4.owners(@form, h, "ana", i, ~w(ana ben))
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana ben))
          B4.consent(@form, h, "ben", v)
          s = scope(@form, h, "ben")
          assert FindependenceShared.Values.links(s) == []
          assert FindependenceShared.Portability.export(s).links == []
          assert FindependenceShared.Values.distribution(s) == elem(before, 1)
          refute Map.has_key?(view(@form, h, "ben").links, a)
          assert FindependenceShared.Values.links(scope(@form, h, "ana")) == [{i, v}]
        end
      end

      describe "REQ-169" do
        test "REQ-169 AC-1: export needs nobody else's consent: produced at once, asking nothing" do
          h = household(@form, ~w(ana ben))
          i = add_item(@form, h, "ana", "Groceries")
          {:ok, _} = B4.owners(@form, h, "ana", i, ~w(ana ben))
          before = B4.stored(@form, h, "ana")
          e = FindependenceShared.Portability.export(scope(@form, h, "ana"))
          assert [%{id: ^i}] = e.items
          assert B4.stored(@form, h, "ana") == before
          assert FindependenceShared.Items.pending(scope(@form, h, "ben")) == []
        end

        test "REQ-169 AC-2..AC-4: every item owned, of every kind, with attributes, owners, grantees, history, and readings" do
          h = household(@form, ~w(ana ben))
          [a, b] = [id(@form, h, "ana"), id(@form, h, "ben")]
          money = add_item(@form, h, "ana", "Rent", amount: -150_000)
          B4.grant(@form, h, "ana", money, "ben")
          joint = add_item(@form, h, "ben", "Groceries")
          {:ok, _} = B4.owners(@form, h, "ben", joint, ~w(ben ana))
          v = B4.value(@form, h, "ana", "Health")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          B4.reading(@form, h, "ana", chk, 120_000, "2026-09-01")
          visa = B4.debt(@form, h, "ana", "Visa", :card)
          B4.debt_reading(@form, h, "ana", visa, 50_000, 2199, 2_500, "2026-09-02")
          ok!(FindependenceShared.Planning.new_plan(scope(@form, h, "ana"), "p1", "If pay stops"))
          ok!(FindependenceShared.Planning.share_plan(scope(@form, h, "ana"), "p1", [b]))
          sp = B4.by_label(view(@form, h, "ana"), "If pay stops")
          # not owned by ana
          bens = add_item(@form, h, "ben", "Ben's phone")
          B4.grant(@form, h, "ben", bens, "ana")
          add_item(@form, h, "ben", "Ben's secret")

          s = scope(@form, h, "ana")
          e = FindependenceShared.Portability.export(s)
          by = Map.new(e.items, &{&1.id, &1})
          assert Enum.sort(Map.keys(by)) == Enum.sort([money, joint, v, chk, visa, sp])

          # AC-3
          for x <- e.items do
            {:ok, i} = FindependenceShared.Items.get(s, x.id)
            assert x.attrs == i.attrs
            assert x.owners == Enum.sort(i.owners)
            assert x.grantees == Enum.sort(i.grantees)
            assert {:ok, x.ledger} == FindependenceShared.Items.ledger(s, x.id)
          end

          assert by[money].attrs.note == "Rent" and by[money].grantees == [b]
          assert by[joint].owners == Enum.sort([a, b])
          assert by[sp].attrs.kind == :plan

          # AC-4
          assert [%{on: "2026-09-01", balance: 120_000}] = by[chk].readings
          assert [%{balance: 50_000, rate_bp: 2199, min_payment: 2_500}] = by[visa].readings
          assert by[money].readings == [] and by[v].readings == []
        end

        test "REQ-169 AC-5..AC-8: own links, plans, marks, goals, retirement, and attachments, only with references it contains" do
          h = household(@form, ~w(ana ben))
          b = id(@form, h, "ben")
          pay = add_item(@form, h, "ana", "Paycheck", amount: 400_000)
          gym = add_item(@form, h, "ana", "Gym", amount: -4_000)
          jointly = add_item(@form, h, "ana", "Bonus", amount: 100_000)
          {:ok, _} = B4.owners(@form, h, "ana", jointly, ~w(ana ben))
          home = B4.value(@form, h, "ana", "Home")
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          k401 = B4.account(@form, h, "ana", "401k", :retirement_401k)
          # ben's, shared with ana
          theirs = B4.value(@form, h, "ben", "Theirs")
          B4.grant(@form, h, "ben", theirs, "ana")
          ben_ira = B4.account(@form, h, "ben", "Ben's IRA", :ira)
          B4.grant(@form, h, "ben", ben_ira, "ana")
          ben_chk = B4.account(@form, h, "ben", "Ben's checking", :checking)
          B4.grant(@form, h, "ben", ben_chk, "ana")

          s = fn -> scope(@form, h, "ana") end
          ok!(FindependenceShared.Values.link(s.(), pay, home))
          ok!(FindependenceShared.Values.link(s.(), pay, theirs))
          ok!(FindependenceShared.Values.link(s.(), jointly, home))
          ok!(FindependenceShared.Planning.new_plan(s.(), "p1", "If the job stops"))

          ok!(
            FindependenceShared.Planning.add_step(s.(), "p1", %{
              kind: "switch_off",
              items: [pay, jointly],
              from: "2026-11"
            })
          )

          ok!(
            FindependenceShared.Planning.add_step(s.(), "p1", %{
              kind: "add",
              note: "Tools",
              amount: {:ok, -5_000},
              frequency: :one_off,
              from: "2026-12"
            })
          )

          ok!(FindependenceShared.Planning.mark(s.(), gym, pay))
          ok!(FindependenceShared.Planning.mark(s.(), gym, jointly))
          ok!(FindependenceShared.Planning.set_fund_goal(s.(), 3))
          ok!(FindependenceShared.Planning.set_aside(s.(), home, 2_500))
          ok!(FindependenceShared.Planning.set_aside(s.(), theirs, 1_000))

          ok!(
            FindependenceShared.Planning.save_retirement(s.(), %{
              birth_year: {:ok, 1980},
              retire_age: {:ok, 65},
              return_bp: {:ok, nil},
              ss_monthly: {:ok, nil},
              target_monthly: {:ok, nil},
              contributions: [{k401, {:ok, 20_000}}, {ben_ira, {:ok, 5_000}}]
            })
          )

          attach = &FindependenceShared.Balances.attach(s.(), &1, &2)
          ok!(attach.(pay, chk))
          ok!(attach.(gym, ben_chk))
          ok!(attach.(jointly, chk))

          # ana stops owning the jointly owned item: references to it go
          ok!(FindependenceShared.Items.relinquish(s.(), jointly))
          e = FindependenceShared.Portability.export(s.())

          # AC-5
          assert e.links == [{pay, home}]
          # AC-6, AC-8
          assert [%{id: "p1", name: "If the job stops", steps: steps}] = e.plans

          assert steps == [
                   {:switch_off, [pay], "2026-11"},
                   {:add, %{note: "Tools", amount: -5_000, frequency: :one_off}, "2026-12"}
                 ]

          assert e.marks == [{gym, pay}]
          assert e.goals == %{fund_months: 3, set_aside: [{home, 2_500}]}

          assert e.retirement == %{
                   birth_year: 1980,
                   retire_age: 65,
                   return_bp: nil,
                   ss_monthly: nil,
                   target_monthly: nil,
                   contributions: [{k401, 20_000}]
                 }

          # AC-7, AC-8
          assert e.attached == [{pay, chk}]
          refute b in (e.items |> Enum.flat_map(& &1.owners))
        end

        test "REQ-169 AC-9: nothing else: exactly these parts and fields, nothing of others, deletions, or proposals" do
          h = household(@form, ~w(ana ben))
          a = id(@form, h, "ana")
          i = add_item(@form, h, "ana", "Rent")
          gone = add_item(@form, h, "ana", "Old")
          ok!(FindependenceShared.Items.delete(scope(@form, h, "ana"), gone))
          v = B4.value(@form, h, "ana", "Home")
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana ben))
          assert B4.proposal(@form, h, "ana", v) != nil
          bens = add_item(@form, h, "ben", "Ben's phone")
          B4.grant(@form, h, "ben", bens, "ana")
          other = B4.value(@form, h, "ben", "Ben's value")
          B4.grant(@form, h, "ben", other, "ana")
          ok!(FindependenceShared.Values.link(scope(@form, h, "ben"), bens, other))
          ok!(FindependenceShared.Planning.set_fund_goal(scope(@form, h, "ben"), 6))

          e = FindependenceShared.Portability.export(scope(@form, h, "ana"))

          assert Enum.sort(Map.keys(e)) ==
                   [:attached, :goals, :items, :links, :marks, :member, :plans, :retirement]

          assert e.member == a
          assert Enum.sort(Enum.map(e.items, & &1.id)) == Enum.sort([i, v])

          for x <- e.items,
              do:
                assert(
                  Enum.sort(Map.keys(x)) == [:attrs, :grantees, :id, :ledger, :owners, :readings]
                )

          assert e.links == [] and e.plans == [] and e.marks == [] and e.attached == []
          assert e.goals == %{fund_months: nil, set_aside: []}

          data = FindependenceShared.Portability.to_data(e)

          assert Enum.sort(Map.keys(data)) ==
                   ~w(attached format goals items links marks member plans retirement version)

          text = B4.json(data)
          refute text =~ "Old"
          refute text =~ "Ben's"
          refute text =~ "proposal"
          refute text =~ "deletion"

          assert FindependenceShared.Items.get(scope(@form, h, "ana"), v)
                 |> elem(1)
                 |> Map.get(:owners) == [a]
        end
      end

      describe "REQ-170" do
        test "REQ-170 AC-2: an appended entry's key is sealed to exactly the owners at that moment, not grantees" do
          h = household(@form, ~w(ana ben cy))
          [a, b] = [id(@form, h, "ana"), id(@form, h, "ben")]
          i = add_item(@form, h, "ana", "Rent")
          assert B4.entry_readers(B4.stored(@form, h, "ana"), i) == [[a]]
          B4.grant(@form, h, "ana", i, "ben")
          # the grantee holds the item key but no entry key
          assert b in B4.key_holders(B4.stored(@form, h, "ana"), i)
          assert B4.entry_readers(B4.stored(@form, h, "ana"), i) == [[a], [a]]

          assert FindependenceShared.Items.ledger(scope(@form, h, "ben"), i) ==
                   {:error, :not_found}

          assert Enum.all?(view(@form, h, "ben").ledger[i], &(&1 == :sealed))

          # with two owners, a new entry is sealed to both, not to the new grantee
          j = add_item(@form, h, "ana", "Groceries")
          {:ok, _} = B4.owners(@form, h, "ana", j, ~w(ana ben))

          {:ok, _} =
            FindependenceShared.Items.propose_grant(scope(@form, h, "ana"), j, id(@form, h, "cy"))

          B4.consent(@form, h, "ben", j)
          assert List.last(B4.entry_readers(B4.stored(@form, h, "ana"), j)) == Enum.sort([a, b])
          {:ok, entries} = FindependenceShared.Items.ledger(scope(@form, h, "ana"), j)
          assert List.last(entries).event == :granted
        end

        test "REQ-170 AC-3: every existing entry is re-sealed for each new owner, who can open the whole ledger" do
          h = household(@form, ~w(ana ben cy))
          i = add_item(@form, h, "ana", "Rent")
          B4.grant(@form, h, "ana", i, "ben")
          {:ok, _} = B4.owners(@form, h, "ana", i, ~w(ana cy))
          ac = B4.ids(@form, h, ~w(ana cy))
          assert B4.entry_readers(B4.stored(@form, h, "ana"), i) == List.duplicate(ac, 3)
          {:ok, entries} = FindependenceShared.Items.ledger(scope(@form, h, "cy"), i)
          assert Enum.map(entries, & &1.event) == [:created, :granted, :owners_changed]
          refute :sealed in view(@form, h, "cy").ledger[i]
        end

        test "REQ-170 AC-4: a prospective value owner opens every entry once every owner agreed, before own consent; withdrawn, keys go" do
          h = household(@form, ~w(ana ben cy))
          c = id(@form, h, "cy")
          v = B4.value(@form, h, "ana", "A safe home")
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana ben))
          B4.consent(@form, h, "ben", v)
          {:ok, _} = B4.owners(@form, h, "ana", v, ~w(ana ben cy))
          # only ana has agreed so far
          refute Enum.any?(B4.entry_readers(B4.stored(@form, h, "ana"), v), &(c in &1))
          assert Enum.all?(view(@form, h, "cy").ledger[v], &(&1 == :sealed))

          B4.consent(@form, h, "ben", v)
          p = B4.proposal(@form, h, "ana", v)
          assert p != nil
          assert Enum.all?(B4.entry_readers(B4.stored(@form, h, "ana"), v), &(c in &1))
          ledger = view(@form, h, "cy").ledger[v]
          assert ledger != [] and not Enum.member?(ledger, :sealed)

          ok!(FindependenceShared.Items.withdraw(scope(@form, h, "ana"), p))
          refute Enum.any?(B4.entry_readers(B4.stored(@form, h, "ana"), v), &(c in &1))
          assert Enum.all?(view(@form, h, "cy").ledger[v], &(&1 == :sealed))
        end

        test "REQ-170 AC-5: the same for a prospective owner of a shared plan" do
          h = household(@form, ~w(ana ben cy))
          [b, c] = [id(@form, h, "ben"), id(@form, h, "cy")]
          ok!(FindependenceShared.Planning.new_plan(scope(@form, h, "ana"), "p1", "If pay stops"))
          ok!(FindependenceShared.Planning.share_plan(scope(@form, h, "ana"), "p1", [b]))
          sp = B4.by_label(view(@form, h, "ana"), "If pay stops")
          # ana alone owns it and has agreed: ben opens every entry before his own consent
          assert Enum.all?(B4.entry_readers(B4.stored(@form, h, "ana"), sp), &(b in &1))
          refute :sealed in view(@form, h, "ben").ledger[sp]
          B4.consent(@form, h, "ben", sp)

          {:ok, _} = B4.owners(@form, h, "ana", sp, ~w(ana ben cy))
          refute Enum.any?(B4.entry_readers(B4.stored(@form, h, "ana"), sp), &(c in &1))
          B4.consent(@form, h, "ben", sp)
          p = B4.proposal(@form, h, "ana", sp)
          assert p != nil
          assert Enum.all?(B4.entry_readers(B4.stored(@form, h, "ana"), sp), &(c in &1))
          refute :sealed in view(@form, h, "cy").ledger[sp]

          ok!(FindependenceShared.Items.withdraw(scope(@form, h, "ana"), p))
          refute Enum.any?(B4.entry_readers(B4.stored(@form, h, "ana"), sp), &(c in &1))
        end

        test "REQ-170 AC-6: no other member opens an entry: grantee, proposed owner of another kind, former owner" do
          h = household(@form, ~w(ana ben cy dee))
          [a, b, c] = [id(@form, h, "ana"), id(@form, h, "ben"), id(@form, h, "cy")]
          i = add_item(@form, h, "ana", "Rent")
          B4.grant(@form, h, "ana", i, "dee")
          # a proposed owner of an ordinary item
          {:ok, _} = B4.owners(@form, h, "ana", i, ~w(ana ben))
          {:ok, _} = B4.owners(@form, h, "ana", i, ~w(ana ben cy))
          assert B4.proposal(@form, h, "ana", i) != nil
          s = B4.stored(@form, h, "ana")
          refute c in B4.key_holders(s, i)
          refute Enum.any?(B4.entry_readers(s, i), &(c in &1))
          # a grantee
          refute Enum.any?(B4.entry_readers(s, i), &(id(@form, h, "dee") in &1))

          # a former owner: loses earlier entries and gets none of the later
          ok!(FindependenceShared.Items.relinquish(scope(@form, h, "ben"), i))

          ok!(
            FindependenceShared.Items.revoke_grant(scope(@form, h, "ana"), i, id(@form, h, "dee"))
          )

          readers = B4.entry_readers(B4.stored(@form, h, "ana"), i)
          assert readers == List.duplicate([a], length(readers))

          assert FindependenceShared.Items.ledger(scope(@form, h, "ben"), i) ==
                   {:error, :not_found}

          assert Enum.all?(view(@form, h, "ben").ledger[i], &(&1 == :sealed))
          refute b in B4.key_holders(B4.stored(@form, h, "ana"), i)
        end
      end

      describe "REQ-171" do
        test "REQ-171 AC-1: each listed kind can be created, of its own kind and type; no other type" do
          h = household(@form, ~w(ana))

          for {add, kind, key, types} <- [
                {&FindependenceShared.Balances.add_account/4, :account, :account_type,
                 [:checking, :savings, :other, :retirement_401k, :ira]},
                {&FindependenceShared.Balances.add_debt/4, :debt, :debt_type,
                 [:card, :heloc, :loan, :other]}
              ],
              type <- types do
            x = FindependenceShared.Persistence.new_id()
            ok!(add.(scope(@form, h, "ana"), x, "Mine #{type}", type))
            {:ok, i} = FindependenceShared.Items.get(scope(@form, h, "ana"), x)
            assert i.attrs == %{:kind => kind, :label => "Mine #{type}", key => type}
          end

          x = FindependenceShared.Persistence.new_id()

          for {add, type} <- [
                {&FindependenceShared.Balances.add_account/4, :card},
                {&FindependenceShared.Balances.add_account/4, :mortgage},
                {&FindependenceShared.Balances.add_debt/4, :checking},
                {&FindependenceShared.Balances.add_debt/4, :ira}
              ] do
            assert {:error, :validation, :invalid_balance, _} =
                     add.(scope(@form, h, "ana"), x, "X", type)
          end

          assert FindependenceShared.Items.get(scope(@form, h, "ana"), x) == {:error, :not_found}
        end

        test "REQ-171 AC-2: created by a member and owned by that member alone" do
          h = household(@form, ~w(ana ben))
          a = id(@form, h, "ana")

          for x <- [
                B4.account(@form, h, "ana", "Checking", :checking),
                B4.debt(@form, h, "ana", "Card", :card)
              ] do
            {:ok, i} = FindependenceShared.Items.get(scope(@form, h, "ana"), x)
            assert i.owners == [a] and i.grantees == []
            assert B4.stored(@form, h, "ana").items[x].owners == [a]
          end
        end

        test "REQ-171 AC-3: private by default: no other member can see it until shared" do
          h = household(@form, ~w(ana ben))

          for x <- [
                B4.account(@form, h, "ana", "Checking", :checking),
                B4.debt(@form, h, "ana", "Card", :card)
              ] do
            s = scope(@form, h, "ben")
            refute x in Enum.map(FindependenceShared.Items.visible(s), & &1.id)
            assert FindependenceShared.Items.get(s, x) == {:error, :not_found}
            refute reads?(@form, h, "ben", x)
            assert B4.key_holders(B4.stored(@form, h, "ana"), x) == [id(@form, h, "ana")]
            B4.grant(@form, h, "ana", x, "ben")
            assert reads?(@form, h, "ben", x)
          end
        end

        test "REQ-171 AC-4: the item rules hold for an account" do
          h = household(@form, ~w(ana ben cy))
          B4.item_rules(@form, h, :account)
        end

        test "REQ-171 AC-4: the item rules hold for a debt" do
          h = household(@form, ~w(ana ben cy))
          B4.item_rules(@form, h, :debt)
        end

        test "REQ-171 AC-5: name and kind are fixed; it can't be added again under its id" do
          h = household(@form, ~w(ana ben cy))
          c = id(@form, h, "cy")

          for {x, reading} <- [
                {B4.account(@form, h, "ana", "Checking", :checking),
                 fn x -> B4.reading(@form, h, "ana", x, 1_000, "2026-09-27") end},
                {B4.debt(@form, h, "ana", "Card", :card),
                 fn x -> B4.debt_reading(@form, h, "ana", x, 1_000, 1_999, 100, "2026-09-27") end}
              ] do
            {:ok, %{attrs: attrs}} = FindependenceShared.Items.get(scope(@form, h, "ana"), x)

            same = fn ->
              assert FindependenceShared.Items.lookup(scope(@form, h, "ana"), x).attrs == attrs
            end

            reading.(x)
            same.()
            B4.grant(@form, h, "ana", x, "cy")
            same.()
            ok!(FindependenceShared.Items.revoke_grant(scope(@form, h, "ana"), x, c))
            same.()
            {:ok, _} = B4.owners(@form, h, "ana", x, ~w(ana ben))
            same.()
            ok!(FindependenceShared.Items.relinquish(scope(@form, h, "ben"), x))
            same.()
            B4.grant(@form, h, "ana", x, "cy")

            for add <- [
                  &FindependenceShared.Balances.add_account/4,
                  &FindependenceShared.Balances.add_debt/4
                ],
                type <- [:other],
                do:
                  assert(
                    {:error, :conflict, :item_exists, _} =
                      add.(scope(@form, h, "ana"), x, "Renamed", type)
                  )

            same.()
          end

          ok!(FindependenceShared.Households.leave(scope(@form, h, "cy")))

          for {_, i} <- view(@form, h, "ana").items,
              do: assert(i.attrs.label in ["Checking", "Card"])
        end
      end

      describe "REQ-173" do
        test "REQ-173 AC-3: the sixty days carry the running balance REQ-161 describes" do
          h = household(@form, ~w(ana))
          chk = B4.account(@form, h, "ana", "Checking", :checking)
          sav = B4.account(@form, h, "ana", "Savings", :savings)
          B4.reading(@form, h, "ana", chk, 100_000, "2026-09-30")
          B4.reading(@form, h, "ana", sav, 500_000, "2026-09-30")

          add_item(@form, h, "ana", "Rent",
            amount: -150_000,
            frequency: {:every, 1, :month},
            on: "2026-10-01"
          )

          add_item(@form, h, "ana", "Pay",
            amount: 200_000,
            frequency: {:every, 2, :week},
            on: "2026-10-02"
          )

          last =
            add_item(@form, h, "ana", "Last", amount: -7, frequency: :one_off, on: "2026-11-29")

          add_item(@form, h, "ana", "Beyond", amount: -9, frequency: :one_off, on: "2026-11-30")
          ok!(FindependenceShared.Balances.attach(scope(@form, h, "ana"), last, chk))
          s = scope(@form, h, "ana")

          sixty = FindependenceShared.CashFlow.cash_flow(s, ~D[2026-10-01], 60)
          fourteen = FindependenceShared.CashFlow.cash_flow(s, ~D[2026-10-01], 14)
          assert length(sixty.days) == 60
          assert Enum.take(sixty.days, 14) == fourteen.days
          assert sixty.start == %{balance: 100_000, on: ~D[2026-09-30], accounts: [chk]}

          # each day's balance is the start plus every occurrence up to that day
          Enum.reduce(sixty.days, 100_000, fn d, bal ->
            bal = bal + Enum.sum(Enum.map(d.entries, &elem(&1, 1)))
            assert d.balance == bal
            bal
          end)

          by = Map.new(sixty.days, &{&1.date, &1.balance})
          assert by[~D[2026-10-01]] == -50_000
          assert by[~D[2026-10-02]] == 150_000
          assert List.last(sixty.days).date == ~D[2026-11-29]
          assert List.last(sixty.days).balance == 100_000 - 2 * 150_000 + 5 * 200_000 - 7
        end
      end

      describe "REQ-174" do
        test "REQ-174 AC-1: without a target income, no comparison" do
          h = household(@form, ~w(ana))
          p = B4.retire(@form, h, target: nil, ss: 200_000)
          assert p.gap == nil and p.lasts == nil
        end

        test "REQ-174 AC-2: with a target, the monthly difference from Social Security (none counts as none)" do
          h = household(@form, ~w(ana))
          p = B4.retire(@form, h, target: 300_000, ss: 200_000)
          assert p.gap == 100_000
          p = B4.retire(@form, h, target: 300_000, ss: nil)
          assert p.gap == 300_000
        end

        test "REQ-174 AC-3: how long the balance lasts paying the difference, month by month at the same return" do
          h = household(@form, ~w(ana))
          p = B4.retire(@form, h, target: 300_000, ss: 200_000, return_bp: 0)
          assert p.at_retirement == 1_000_000 and p.lasts == {:months, 10}
          # 12,989.47 at 1% a month, paying 1,000.00 a month: 13 full months
          p =
            B4.retire(@form, h,
              target: 300_000,
              ss: 200_000,
              return_bp: 1_200,
              balance: 1_298_947
            )

          assert p.at_retirement == 1_298_947 and p.lasts == {:months, 13}
        end

        test "REQ-174 AC-4: when some would remain at age 100, it says so" do
          h = household(@form, ~w(ana))
          p = B4.retire(@form, h, target: 1_000, ss: nil, return_bp: 1_200)
          assert p.gap == 1_000 and p.lasts == :beyond
        end

        test "REQ-174 AC-5: Social Security at least the target covers it" do
          h = household(@form, ~w(ana))

          for ss <- [200_000, 250_000] do
            p = B4.retire(@form, h, target: 200_000, ss: ss)
            assert p.lasts == :covered
          end
        end
      end
    end
  end
end
