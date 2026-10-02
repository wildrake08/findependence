defmodule FindependenceShared.Contract.B2 do
  @moduledoc """
  Helpers for the contract cases of REQ-129..REQ-145 (REQ-188 AC-1, WI-074). Each takes the form module
  first, like `FindependenceShared.Contract.Helpers`.
  """

  alias FindependenceShared.{Balances, Items, Planning}
  alias FindependenceShared.Contract.Helpers, as: H

  @today ~D[2026-09-29]

  @doc "The fixed date the cases use as today."
  def today, do: @today

  @doc "A new unique id for an account, debt, or plan."
  def new_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  @doc "Adds an account the named member owns and returns its id."
  def account(form, h, name, label \\ "Checking", type \\ :checking) do
    id = new_id("acct")
    {:ok, _} = Balances.add_account(H.scope(form, h, name), id, label, type)
    id
  end

  @doc "Adds a debt the named member owns and returns its id."
  def debt(form, h, name, label \\ "Visa", type \\ :card) do
    id = new_id("debt")
    {:ok, _} = Balances.add_debt(H.scope(form, h, name), id, label, type)
    id
  end

  @doc "The transport-decoded input for an account's reading."
  def account_input(on, cents),
    do: %{balance: {:ok, abs(cents), cents < 0}, on: {:ok, on}, rate: nil, min_payment: nil}

  @doc "The transport-decoded input for a debt's reading."
  def debt_input(on, owed, bp, min),
    do: %{balance: {:ok, owed, false}, on: {:ok, on}, rate: {:ok, bp}, min_payment: {:ok, min}}

  @doc "Adds a reading as the named member (the result of the context operation)."
  def add_reading(form, h, name, item, input),
    do: Balances.add_reading(H.scope(form, h, name), item, input)

  @doc "Adds a reading as the named member, expecting success."
  def add_reading!(form, h, name, item, input) do
    {:ok, _} = add_reading(form, h, name, item, input)
    :ok
  end

  @doc "The owner grants `item` to the named grantee (a single owner's grant applies at once)."
  def grant(form, h, owner, item, grantee) do
    {:ok, _} = Items.propose_grant(H.scope(form, h, owner), item, H.id(form, h, grantee))
    :ok
  end

  @doc "Makes `item`, solely owned by `owner`, jointly owned with `other`, who agrees (WI-086, CP-029)."
  def joint(form, h, owner, item, other) do
    {:ok, _} = H.make_owners(form, h, owner, item, [owner, other])
    :ok
  end

  @doc "For each stored reading of `item`: `{seq, sorted ids of the members holding its sealed key}`."
  def reading_keys(form, h, item) do
    rec = H.stored(form, h).items[item]
    for r <- Map.get(rec, :readings, []), do: {r.seq, r.keys |> Map.keys() |> Enum.sort()}
  end

  @doc "Sorted member ids for these names."
  def ids(form, h, names), do: names |> Enum.map(&H.id(form, h, &1)) |> Enum.sort()

  @doc "The named member's view of the item's readings: decoded maps, or `:sealed` placeholders."
  def view_readings(form, h, name, item), do: Map.get(H.view(form, h, name).readings, item, [])

  @doc "Adds an item and returns the item as the named member sees it after a refresh."
  def item!(form, h, name, note, opts) do
    id = H.add_item(form, h, name, note, opts)
    H.view(form, h, name).items[id]
  end

  @doc "Starts a plan for the named member and returns its id."
  def plan(form, h, name, label) do
    id = new_id("plan")
    {:ok, _} = Planning.new_plan(H.scope(form, h, name), id, label)
    id
  end

  @doc "Adds a step to a plan, returning the context result."
  def step(form, h, name, plan, input) do
    input =
      Map.merge(
        %{
          kind: nil,
          items: [],
          from: nil,
          note: nil,
          amount: nil,
          frequency: nil,
          borrow: :error
        },
        input
      )

    Planning.add_step(H.scope(form, h, name), plan, input)
  end

  @doc "Adds a step, expecting success."
  def step!(form, h, name, plan, input) do
    {:ok, _} = step(form, h, name, plan, input)
    :ok
  end

  @doc "The named member's projection, as things are or with their plan."
  def project(form, h, name, plan_id \\ nil) do
    s = H.scope(form, h, name)
    plan = plan_id && Planning.plan(s, plan_id)
    FindependenceShared.CashFlow.project(s, @today, plan)
  end

  @doc "Every real total REQ-142 AC-8 names, for the named member."
  def real_totals(form, h, name) do
    s = H.scope(form, h, name)

    %{
      project: FindependenceShared.CashFlow.project(s, @today),
      distribution: FindependenceShared.Values.distribution(s),
      cash_flow: FindependenceShared.CashFlow.cash_flow(s, @today, 60),
      set_asides: FindependenceShared.CashFlow.set_asides(s),
      goal_set_asides: Planning.set_asides(s),
      cover: Planning.cover(s)
    }
  end

  @doc "The named member's set-asides as item id => monthly cents."
  def covered(form, h, name) do
    sa = FindependenceShared.CashFlow.set_asides(H.scope(form, h, name))
    Map.new(sa.items, fn {i, c} -> {i.id, c} end)
  end

  @doc "A month's figure of a projection, by \"YYYY-MM\"."
  def month(projection, mo), do: Enum.find(projection.months, &(&1.month == mo))
end

defmodule FindependenceShared.Contract.Cases.Req129To145 do
  @moduledoc """
  Contract cases for the CORE and PERSIST acceptance criteria of REQ-129..REQ-145 (REQ-188 AC-1, WI-074),
  run against both forms' contexts.
  """

  defmacro __using__(_) do
    quote do
      alias FindependenceShared.Contract.B2

      describe "REQ-129" do
        test "REQ-129 AC-2: an item sent with no choice of how often is not saved; the member is told to choose" do
          h = household(@form, ~w(ana))

          input = %{note: "Gym", amount: {:ok, -4_000}, frequency: nil, on: ""}

          assert {:error, :validation, {:frequency, "Choose how often this happens."}} =
                   FindependenceShared.Items.add_item(scope(@form, h, "ana"), input)

          assert find(view(@form, h, "ana"), "Gym") == nil
        end

        test "REQ-129 AC-3: an irregular amount is kept as the total for a year, counted as a twelfth a month" do
          h = household(@form, ~w(ana))
          i = B2.item!(@form, h, "ana", "Car repairs", amount: -120_000, frequency: :irregular)

          assert i.attrs.amount == -120_000
          assert FindependenceShared.CashFlow.per_month(i.attrs.amount, :irregular) == -10_000

          d = FindependenceShared.Values.distribution(scope(@form, h, "ana"))
          assert d.unlinked.per_month.out == -10_000
          assert d.unlinked.one_off.out == 0
        end

        test "REQ-129 AC-4: each of the nine choices is stored exactly as chosen" do
          h = household(@form, ~w(ana))
          choices = Findependence.Alignment.frequencies()
          assert length(choices) == 9

          for {f, k} <- Enum.with_index(choices),
              do: add_item(@form, h, "ana", "Item #{k}", frequency: f)

          v = view(@form, h, "ana")

          for {f, k} <- Enum.with_index(choices) do
            item = v.items[find(v, "Item #{k}")]
            assert item.attrs.frequency == f
            assert FindependenceShared.Items.frequency(item) == f
          end
        end

        test "REQ-129 AC-7: items stored with the earlier frequencies read and count as the same intervals" do
          h = household(@form, ~w(ana))

          legacy = [
            weekly: {:every, 1, :week},
            biweekly: {:every, 2, :week},
            monthly: {:every, 1, :month},
            yearly: {:every, 1, :year}
          ]

          for {old, _} <- legacy,
              do: add_item(@form, h, "ana", "Old #{old}", amount: -12_000, frequency: old)

          v = view(@form, h, "ana")

          for {old, interval} <- legacy do
            item = v.items[find(v, "Old #{old}")]
            assert FindependenceShared.Items.frequency(item) == interval
          end

          expected =
            legacy
            |> Enum.map(fn {_, i} -> FindependenceShared.CashFlow.per_month(-12_000, i) end)
            |> Enum.sum()

          d = FindependenceShared.Values.distribution(scope(@form, h, "ana"))
          assert d.unlinked.count == 4
          assert d.unlinked.per_month.out == expected
        end
      end

      describe "REQ-131" do
        test "REQ-131 AC-1: any owner, a joint owner included, adds a reading at once, with no proposal" do
          h = household(@form, ~w(ana ben))
          acct = B2.account(@form, h, "ana", "Joint checking")
          :ok = B2.joint(@form, h, "ana", acct, "ben")

          :ok = B2.add_reading!(@form, h, "ben", acct, B2.account_input("2026-09-20", 124_000))
          :ok = B2.add_reading!(@form, h, "ana", acct, B2.account_input("2026-09-27", 98_050))

          for n <- ~w(ana ben) do
            s = scope(@form, h, n)
            assert FindependenceShared.Items.pending(s) == []
            assert %{balance: 98_050, by: by} = FindependenceShared.Balances.latest(s, acct)
            assert by == id(@form, h, "ana")
          end

          assert {:ok, [%{seq: 1, balance: 124_000}, %{seq: 2}]} =
                   FindependenceShared.Balances.readings(scope(@form, h, "ana"), acct)
        end

        test "REQ-131 AC-2: a grantee is refused as not an owner; someone who can't see it, as not found" do
          h = household(@form, ~w(ana ben cara))
          visa = B2.debt(@form, h, "ana")
          :ok = B2.grant(@form, h, "ana", visa, "ben")
          r = B2.debt_input("2026-09-27", 520_000, 2199, 15_000)

          assert {:error, :unauthorized, :not_owner, _} = B2.add_reading(@form, h, "ben", visa, r)
          assert {:error, :not_found, :not_found, _} = B2.add_reading(@form, h, "cara", visa, r)
          assert {:error, :not_found, :not_found, _} = B2.add_reading(@form, h, "cara", "nope", r)
          assert B2.reading_keys(@form, h, visa) == []
        end

        test "REQ-131 AC-3: an account's reading is a balance; a debt's is owed, rate, and minimum; anything else is refused" do
          h = household(@form, ~w(ana))
          chk = B2.account(@form, h, "ana")
          visa = B2.debt(@form, h, "ana")
          rent = add_item(@form, h, "ana", "Rent")

          # an account may be overdrawn
          :ok = B2.add_reading!(@form, h, "ana", chk, B2.account_input("2026-09-27", -5_000))
          :ok = B2.add_reading!(@form, h, "ana", visa, B2.debt_input("2026-09-27", 1, 2199, 0))

          s = scope(@form, h, "ana")
          assert %{balance: -5_000} = r = FindependenceShared.Balances.latest(s, chk)
          refute Map.has_key?(r, :rate_bp) or Map.has_key?(r, :min_payment)

          assert %{balance: 1, rate_bp: 2199, min_payment: 0} =
                   FindependenceShared.Balances.latest(s, visa)

          bad = [
            {%{B2.debt_input("2026-09-27", 1, 2199, 0) | balance: {:ok, 100, true}}, :balance},
            {B2.debt_input("2026-09-27", 1, 10_001, 0), :rate},
            {%{B2.debt_input("2026-09-27", 1, 2199, 0) | rate: :error}, :rate},
            {B2.debt_input("2026-09-27", 1, 2199, -5), :min_payment},
            {%{B2.debt_input("2026-09-27", 1, 2199, 0) | min_payment: nil}, :min_payment}
          ]

          for {input, field} <- bad,
              do:
                assert(
                  {:error, :validation, {^field, _}} =
                    B2.add_reading(@form, h, "ana", visa, input)
                )

          assert {:error, :validation, {:balance, _}} =
                   B2.add_reading(@form, h, "ana", chk, %{
                     B2.account_input("2026-09-27", 1)
                     | balance: :error
                   })

          assert {:error, :validation, :not_a_balance, _} =
                   B2.add_reading(@form, h, "ana", rent, B2.account_input("2026-09-27", 1))

          s = scope(@form, h, "ana")
          assert {:ok, [_]} = FindependenceShared.Balances.readings(s, visa)
          assert {:ok, [_]} = FindependenceShared.Balances.readings(s, chk)
        end

        test "REQ-131 AC-4: a reading with no date or an invalid one is refused" do
          h = household(@form, ~w(ana))
          chk = B2.account(@form, h, "ana")

          assert {:error, :validation, {:on, _}} =
                   B2.add_reading(@form, h, "ana", chk, %{
                     B2.account_input("2026-09-27", 1)
                     | on: :error
                   })

          for bad <- ["2026-02-30", "yesterday", ""],
              do:
                assert(
                  {:error, :validation, :invalid_reading, _} =
                    B2.add_reading(@form, h, "ana", chk, B2.account_input(bad, 1))
                )

          :ok = B2.add_reading!(@form, h, "ana", chk, B2.account_input("2026-09-27", 1))

          assert %{on: "2026-09-27"} =
                   FindependenceShared.Balances.latest(scope(@form, h, "ana"), chk)
        end

        test "REQ-131 AC-5: readings are append-only, earlier ones unchanged and numbered without gaps" do
          h = household(@form, ~w(ana ben))
          visa = B2.debt(@form, h, "ana")
          read = fn -> FindependenceShared.Balances.readings(scope(@form, h, "ana"), visa) end

          check = fn before ->
            {:ok, now} = read.()
            assert Enum.map(now, & &1.seq) == Enum.to_list(1..length(now))
            assert Enum.take(now, length(before)) == before
            now
          end

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-07-27", 560_000, 2199, 16_000)
            )

          r1 = check.([])

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-08-27", 540_000, 2199, 16_000)
            )

          r2 = check.(r1)
          :ok = B2.grant(@form, h, "ana", visa, "ben")
          r3 = check.(r2)
          # a refused reading changes nothing
          {:error, _, _, _} =
            B2.add_reading(@form, h, "ben", visa, B2.debt_input("2026-09-01", 1, 0, 0))

          r4 = check.(r3)
          assert r4 == r3
          :ok = B2.joint(@form, h, "ana", visa, "ben")
          r5 = check.(r4)

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ben",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          r6 = check.(r5)
          assert length(r6) == 3
          {:ok, _} = FindependenceShared.Items.relinquish(scope(@form, h, "ben"), visa)
          assert check.(r6) == r6
        end

        test "REQ-131 AC-6: each reading is recorded in the item's history" do
          h = household(@form, ~w(ana))
          chk = B2.account(@form, h, "ana")
          :ok = B2.add_reading!(@form, h, "ana", chk, B2.account_input("2026-09-20", 1))
          :ok = B2.add_reading!(@form, h, "ana", chk, B2.account_input("2026-09-27", 2))

          {:ok, ledger} = FindependenceShared.Items.ledger(scope(@form, h, "ana"), chk)
          ana = id(@form, h, "ana")

          assert [
                   %{event: :reading_added, by: [^ana], details: %{seq: 1}},
                   %{event: :reading_added, by: [^ana], details: %{seq: 2}}
                 ] = Enum.filter(ledger, &(&1.event == :reading_added))
        end
      end

      describe "REQ-132" do
        # Ana owns a debt with two readings and shares it with Ben; Cara can't see it.
        test "REQ-132 AC-1: an owner and a grantee can read the latest reading" do
          h = household(@form, ~w(ana ben cara))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-08-27", 540_000, 2199, 16_000)
            )

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          :ok = B2.grant(@form, h, "ana", visa, "ben")

          for n <- ~w(ana ben),
              do:
                assert(
                  %{
                    seq: 2,
                    balance: 520_000,
                    rate_bp: 2199,
                    min_payment: 15_000,
                    on: "2026-09-27"
                  } =
                    FindependenceShared.Balances.latest(scope(@form, h, n), visa)
                )
        end

        test "REQ-132 AC-2: owners read every reading; a grantee cannot read the earlier ones" do
          h = household(@form, ~w(ana ben))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-08-27", 540_000, 2199, 16_000)
            )

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          :ok = B2.grant(@form, h, "ana", visa, "ben")

          assert {:ok, [%{seq: 1, balance: 540_000}, %{seq: 2}]} =
                   FindependenceShared.Balances.readings(scope(@form, h, "ana"), visa)

          assert {:ok, [%{seq: 2, balance: 520_000}]} =
                   FindependenceShared.Balances.readings(scope(@form, h, "ben"), visa)

          # the earlier reading is not decrypted for the grantee at all
          assert [:sealed, %{seq: 2}] = B2.view_readings(@form, h, "ben", visa)
          assert [%{seq: 1}, %{seq: 2}] = B2.view_readings(@form, h, "ana", visa)
        end

        test "REQ-132 AC-3: nobody else can read any reading" do
          h = household(@form, ~w(ana ben cara))
          visa = B2.debt(@form, h, "ana", "Zqxv card")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2031-07-18", 540_000, 2199, 16_000)
            )

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2031-07-19", 520_000, 2199, 15_000)
            )

          :ok = B2.grant(@form, h, "ana", visa, "ben")

          s = scope(@form, h, "cara")
          assert FindependenceShared.Balances.latest(s, visa) == nil
          assert {:error, :not_found} = FindependenceShared.Balances.readings(s, visa)
          assert Enum.all?(B2.view_readings(@form, h, "cara", visa), &(&1 == :sealed))

          cara = id(@form, h, "cara")

          for {_seq, holders} <- B2.reading_keys(@form, h, visa),
              do: refute(cara in holders)

          bytes = stored_bytes(@form, h)
          refute Enum.any?(bytes, &(&1 =~ "2031-07-19" or &1 =~ "2031-07-18"))
        end
      end

      describe "REQ-133" do
        test "REQ-133 AC-1: each reading is under its own key: a reader of one reading cannot open another" do
          h = household(@form, ~w(ana ben))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-08-27", 540_000, 2199, 16_000)
            )

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          :ok = B2.grant(@form, h, "ana", visa, "ben")

          # each reading is stored as its own box with its own sealed keys, apart from the item's key
          rec = stored(@form, h).items[visa]
          assert [%{seq: 1, box: b1, keys: k1}, %{seq: 2, box: b2, keys: k2}] = rec.readings
          assert b1 != b2 and k1 != k2
          # Ben holds reading 2's key and the item's key, yet reading 1 stays sealed to him
          assert Map.has_key?(rec.keys, id(@form, h, "ben"))
          assert [:sealed, %{seq: 2}] = B2.view_readings(@form, h, "ben", visa)
        end

        test "REQ-133 AC-2: when written, the latest is sealed to owners and grantees, earlier ones to owners only" do
          h = household(@form, ~w(ana ben cara))
          visa = B2.debt(@form, h, "ana")
          # granted while Ana is the sole owner, so the grant applies at once
          :ok = B2.grant(@form, h, "ana", visa, "ben")
          :ok = B2.joint(@form, h, "ana", visa, "cara")
          owners = B2.ids(@form, h, ~w(ana cara))
          readers = B2.ids(@form, h, ~w(ana ben cara))

          :ok =
            B2.add_reading!(
              @form,
              h,
              "cara",
              visa,
              B2.debt_input("2026-08-27", 540_000, 2199, 16_000)
            )

          assert B2.reading_keys(@form, h, visa) == [{1, readers}]

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          assert B2.reading_keys(@form, h, visa) == [{1, owners}, {2, readers}]
        end

        test "REQ-133 AC-3: a new grantee is sealed the latest; a new owner every earlier reading" do
          h = household(@form, ~w(ana ben cara))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-08-27", 540_000, 2199, 16_000)
            )

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          ana = B2.ids(@form, h, ~w(ana))
          assert B2.reading_keys(@form, h, visa) == [{1, ana}, {2, ana}]

          :ok = B2.grant(@form, h, "ana", visa, "ben")
          assert B2.reading_keys(@form, h, visa) == [{1, ana}, {2, B2.ids(@form, h, ~w(ana ben))}]
          assert %{seq: 2} = FindependenceShared.Balances.latest(scope(@form, h, "ben"), visa)

          :ok = B2.joint(@form, h, "ana", visa, "cara")

          assert B2.reading_keys(@form, h, visa) == [
                   {1, B2.ids(@form, h, ~w(ana cara))},
                   {2, B2.ids(@form, h, ~w(ana ben cara))}
                 ]

          assert {:ok, [%{seq: 1}, %{seq: 2}]} =
                   FindependenceShared.Balances.readings(scope(@form, h, "cara"), visa)
        end

        test "REQ-133 AC-4: a grantee loses their key on revocation and when a newer reading arrives" do
          h = household(@form, ~w(ana ben))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-08-27", 540_000, 2199, 16_000)
            )

          :ok = B2.grant(@form, h, "ana", visa, "ben")
          ben = id(@form, h, "ben")
          assert [{1, holders}] = B2.reading_keys(@form, h, visa)
          assert ben in holders

          # a reading ceasing to be the latest
          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          assert [{1, k1}, {2, k2}] = B2.reading_keys(@form, h, visa)
          refute ben in k1
          assert ben in k2

          # revocation
          {:ok, _} = FindependenceShared.Items.revoke_grant(scope(@form, h, "ana"), visa, ben)
          assert Enum.all?(B2.reading_keys(@form, h, visa), fn {_, k} -> ben not in k end)
          assert FindependenceShared.Balances.latest(scope(@form, h, "ben"), visa) == nil
        end

        test "REQ-133 AC-4: an owner loses their keys on relinquishing and on removal from the owners by agreement" do
          h = household(@form, ~w(ana ben))
          ben = id(@form, h, "ben")
          ana = id(@form, h, "ana")

          # relinquishing
          a = B2.account(@form, h, "ana")
          :ok = B2.joint(@form, h, "ana", a, "ben")
          :ok = B2.add_reading!(@form, h, "ana", a, B2.account_input("2026-08-27", 1))
          :ok = B2.add_reading!(@form, h, "ben", a, B2.account_input("2026-09-27", 2))
          assert Enum.all?(B2.reading_keys(@form, h, a), fn {_, k} -> ben in k end)
          {:ok, _} = FindependenceShared.Items.relinquish(scope(@form, h, "ben"), a)
          assert B2.reading_keys(@form, h, a) == [{1, [ana]}, {2, [ana]}]

          # removal from the owners by agreement
          b = B2.account(@form, h, "ana", "Savings", :savings)
          :ok = B2.joint(@form, h, "ana", b, "ben")
          :ok = B2.add_reading!(@form, h, "ana", b, B2.account_input("2026-08-27", 1))
          :ok = B2.add_reading!(@form, h, "ana", b, B2.account_input("2026-09-27", 2))
          {:ok, _} = FindependenceShared.Items.propose_owners(scope(@form, h, "ana"), b, [ana])

          [%{id: p}] =
            Enum.filter(
              FindependenceShared.Items.pending(scope(@form, h, "ben")),
              &(&1.item_id == b)
            )

          {:ok, _} = FindependenceShared.Items.consent(scope(@form, h, "ben"), p)
          assert B2.reading_keys(@form, h, b) == [{1, [ana]}, {2, [ana]}]
          assert FindependenceShared.Balances.latest(scope(@form, h, "ben"), b) == nil
        end

        test "REQ-133 AC-4: a grantee who leaves the household loses their keys" do
          h = household(@form, ~w(ana ben))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          :ok = B2.grant(@form, h, "ana", visa, "ben")
          ben = id(@form, h, "ben")
          assert [{1, k}] = B2.reading_keys(@form, h, visa)
          assert ben in k

          {:ok, _} = FindependenceShared.Households.leave(scope(@form, h, "ben"))
          assert B2.reading_keys(@form, h, visa) == [{1, B2.ids(@form, h, ~w(ana))}]
        end

        test "REQ-133 AC-5: a member who lost access is never given a key to a later reading" do
          h = household(@form, ~w(ana ben))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-08-27", 540_000, 2199, 16_000)
            )

          :ok = B2.grant(@form, h, "ana", visa, "ben")
          ben = id(@form, h, "ben")
          {:ok, _} = FindependenceShared.Items.revoke_grant(scope(@form, h, "ana"), visa, ben)

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-10-27", 500_000, 2199, 15_000)
            )

          assert Enum.all?(B2.reading_keys(@form, h, visa), fn {_, k} -> ben not in k end)
          refute Map.has_key?(stored(@form, h).items[visa].keys, ben)
          assert FindependenceShared.Balances.latest(scope(@form, h, "ben"), visa) == nil
        end
      end

      describe "REQ-134" do
        test "REQ-134 AC-1: accounts and debts, owned or shared, with readings, are in no bucket of the distribution" do
          h = household(@form, ~w(ana ben))
          chk = B2.account(@form, h, "ana")
          visa = B2.debt(@form, h, "ana")
          bens = B2.account(@form, h, "ben", "Ben's savings", :savings)
          :ok = B2.add_reading!(@form, h, "ana", chk, B2.account_input("2026-09-27", 124_000))

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 520_000, 2199, 15_000)
            )

          :ok = B2.add_reading!(@form, h, "ben", bens, B2.account_input("2026-09-27", 900_000))
          :ok = B2.grant(@form, h, "ben", bens, "ana")
          {:ok, _} = FindependenceShared.Values.add_value(scope(@form, h, "ana"), "Home")
          add_item(@form, h, "ana", "Rent", amount: -100_000, frequency: {:every, 1, :month})

          s = scope(@form, h, "ana")
          assert FindependenceShared.Items.visible?(s, bens)
          d = FindependenceShared.Values.distribution(s)

          assert d.unlinked == %{
                   count: 1,
                   per_month: %{in: 0, out: -100_000},
                   one_off: %{in: 0, out: 0}
                 }

          assert [bucket] = Map.values(d.by_value)
          assert bucket.count == 0
        end

        test "REQ-134 AC-2: no account or debt can be linked to a value" do
          h = household(@form, ~w(ana))
          chk = B2.account(@form, h, "ana")
          visa = B2.debt(@form, h, "ana")
          {:ok, saved} = FindependenceShared.Values.add_value(scope(@form, h, "ana"), "Home")

          value =
            Enum.find_value(saved.household.items, fn {id, i} ->
              i.attrs[:label] == "Home" && id
            end)

          for item <- [chk, visa],
              do:
                assert(
                  {:error, :validation, :cannot_link_a_balance, _} =
                    FindependenceShared.Values.link(scope(@form, h, "ana"), item, value)
                )

          assert FindependenceShared.Values.links(scope(@form, h, "ana")) == []
        end
      end

      describe "REQ-136" do
        test "REQ-136 AC-1: an item's one date is stored on the item (attrs.on)" do
          h = household(@form, ~w(ana))
          i = B2.item!(@form, h, "ana", "Rent", on: "2026-10-01", frequency: {:every, 1, :month})
          assert i.attrs.on == "2026-10-01"
          assert FindependenceShared.CashFlow.date(i) == ~D[2026-10-01]
        end

        test "REQ-136 AC-3: a recurring item happens on its date and on its schedule from it, never before" do
          h = household(@form, ~w(ana))
          i = B2.item!(@form, h, "ana", "Rent", on: "2026-10-15", frequency: {:every, 1, :month})

          assert FindependenceShared.CashFlow.occurrences(i, ~D[2026-09-01], ~D[2027-01-31]) ==
                   [~D[2026-10-15], ~D[2026-11-15], ~D[2026-12-15], ~D[2027-01-15]]

          assert FindependenceShared.CashFlow.occurrences(i, ~D[2026-01-01], ~D[2026-10-14]) == []
        end

        test "REQ-136 AC-4: a one-off with a date happens on that date only" do
          h = household(@form, ~w(ana))
          i = B2.item!(@form, h, "ana", "TV", on: "2026-11-20", frequency: :one_off)

          assert FindependenceShared.CashFlow.occurrences(i, ~D[2026-01-01], ~D[2028-12-31]) ==
                   [~D[2026-11-20]]
        end

        test "REQ-136 AC-5: an irregular item has no date stored even if one is entered, and no occurrences" do
          h = household(@form, ~w(ana))
          i = B2.item!(@form, h, "ana", "Repairs", on: "2026-11-20", frequency: :irregular)
          refute Map.has_key?(i.attrs, :on)
          assert FindependenceShared.CashFlow.date(i) == nil
          assert FindependenceShared.CashFlow.occurrences(i, ~D[2026-01-01], ~D[2028-12-31]) == []
        end

        test "REQ-136 AC-7: an item without a date is added, listed, and counted at its per-month amount" do
          h = household(@form, ~w(ana))

          i =
            B2.item!(@form, h, "ana", "Groceries",
              amount: -50_000,
              frequency: {:every, 1, :month}
            )

          refute Map.has_key?(i.attrs, :on)
          assert FindependenceShared.CashFlow.occurrences(i, ~D[2026-01-01], ~D[2028-12-31]) == []

          s = scope(@form, h, "ana")
          assert Enum.any?(FindependenceShared.Items.visible(s), &(&1.id == i.id))
          assert FindependenceShared.Values.distribution(s).unlinked.per_month.out == -50_000

          p = FindependenceShared.CashFlow.project(s, B2.today())
          assert length(p.months) == 12
          assert Enum.all?(p.months, &(&1.out == -50_000))
        end
      end

      describe "REQ-137" do
        test "REQ-137 AC-1: every N weeks falls on the date plus 7N, 14N, ... days" do
          h = household(@form, ~w(ana))

          for n <- [1, 2, 3] do
            i =
              B2.item!(@form, h, "ana", "Weekly #{n}",
                on: "2026-10-01",
                frequency: {:every, n, :week}
              )

            to = Date.add(~D[2026-10-01], 7 * n * 3)
            expected = for k <- 0..3, do: Date.add(~D[2026-10-01], 7 * n * k)
            assert FindependenceShared.CashFlow.occurrences(i, ~D[2026-09-01], to) == expected
          end
        end

        test "REQ-137 AC-2: every N months falls on the same day of the month every N months" do
          h = household(@form, ~w(ana))

          for n <- [1, 2, 3, 6] do
            i =
              B2.item!(@form, h, "ana", "Monthly #{n}",
                on: "2026-10-15",
                frequency: {:every, n, :month}
              )

            dates = FindependenceShared.CashFlow.occurrences(i, ~D[2026-10-01], ~D[2029-12-31])
            assert hd(dates) == ~D[2026-10-15]
            assert Enum.all?(dates, &(&1.day == 15))

            assert dates
                   |> Enum.chunk_every(2, 1, :discard)
                   |> Enum.all?(fn [a, b] ->
                     b.year * 12 + b.month - (a.year * 12 + a.month) == n
                   end)
          end
        end

        test "REQ-137 AC-3: every N years falls on the same day of the month every N years" do
          h = household(@form, ~w(ana))

          for n <- [1, 2] do
            i =
              B2.item!(@form, h, "ana", "Yearly #{n}",
                on: "2026-10-15",
                frequency: {:every, n, :year}
              )

            expected = for k <- 0..2, do: %{~D[2026-10-15] | year: 2026 + n * k}

            assert FindependenceShared.CashFlow.occurrences(
                     i,
                     ~D[2026-01-01],
                     List.last(expected)
                   ) ==
                     expected
          end
        end

        test "REQ-137 AC-4: in a shorter month the date is its last day; later dates return to the item's day" do
          h = household(@form, ~w(ana))

          m =
            B2.item!(@form, h, "ana", "End of month",
              on: "2027-01-31",
              frequency: {:every, 1, :month}
            )

          assert FindependenceShared.CashFlow.occurrences(m, ~D[2027-01-01], ~D[2027-05-31]) ==
                   [
                     ~D[2027-01-31],
                     ~D[2027-02-28],
                     ~D[2027-03-31],
                     ~D[2027-04-30],
                     ~D[2027-05-31]
                   ]

          y =
            B2.item!(@form, h, "ana", "Leap day", on: "2028-02-29", frequency: {:every, 1, :year})

          assert FindependenceShared.CashFlow.occurrences(y, ~D[2028-01-01], ~D[2032-12-31]) ==
                   [
                     ~D[2028-02-29],
                     ~D[2029-02-28],
                     ~D[2030-02-28],
                     ~D[2031-02-28],
                     ~D[2032-02-29]
                   ]
        end
      end

      describe "REQ-140" do
        # Ana's money out and in at every frequency, and a yearly item Ben shares with her.
        setup do
          h = household(@form, ~w(ana ben))

          add = fn note, amount, f ->
            add_item(@form, h, "ana", note, amount: amount, frequency: f)
          end

          ids = %{
            two_months: add.("Water", -60_000, {:every, 2, :month}),
            three_months: add.("Gas", -90_000, {:every, 3, :month}),
            twice_a_year: add.("Car insurance", -60_000, {:every, 6, :month}),
            yearly: add.("Property tax", -240_000, {:every, 1, :year}),
            irregular: add.("Repairs", -120_000, :irregular),
            weekly: add.("Groceries", -10_000, {:every, 1, :week}),
            biweekly: add.("Cleaner", -10_000, {:every, 2, :week}),
            monthly: add.("Rent", -100_000, {:every, 1, :month}),
            one_off: add.("TV", -80_000, :one_off),
            in_quarterly: add.("Dividends", 90_000, {:every, 3, :month}),
            in_yearly: add.("Bonus", 240_000, {:every, 1, :year}),
            in_irregular: add.("Gifts", 120_000, :irregular)
          }

          shared =
            add_item(@form, h, "ben", "Ben's insurance",
              amount: -120_000,
              frequency: {:every, 1, :year}
            )

          :ok = B2.grant(@form, h, "ben", shared, "ana")
          %{h: h, ids: ids, shared: shared}
        end

        test "REQ-140 AC-1..AC-5: owned money out every 2 or 3 months, twice a year, yearly, or irregular is covered at its monthly share",
             %{h: h, ids: ids} do
          covered = B2.covered(@form, h, "ana")
          assert covered[ids.two_months] == 30_000
          assert covered[ids.three_months] == 30_000
          assert covered[ids.twice_a_year] == 10_000
          assert covered[ids.yearly] == 20_000
          assert covered[ids.irregular] == 10_000
        end

        test "REQ-140 AC-6: money out monthly or more often, and one-off money out, is not covered",
             %{h: h, ids: ids} do
          covered = B2.covered(@form, h, "ana")

          for k <- [:weekly, :biweekly, :monthly, :one_off],
              do: refute(Map.has_key?(covered, ids[k]))
        end

        test "REQ-140 AC-7: money in, however often, is not covered", %{h: h, ids: ids} do
          covered = B2.covered(@form, h, "ana")

          for k <- [:in_quarterly, :in_yearly, :in_irregular],
              do: refute(Map.has_key?(covered, ids[k]))
        end

        test "REQ-140 AC-8: an item others only share with the member is not covered",
             %{h: h, shared: shared} do
          assert FindependenceShared.Items.visible?(scope(@form, h, "ana"), shared)
          refute Map.has_key?(B2.covered(@form, h, "ana"), shared)
          assert B2.covered(@form, h, "ben") == %{shared => 10_000}
        end

        test "REQ-140 AC-9: the total is the sum of the covered items' monthly amounts", %{h: h} do
          sa = FindependenceShared.CashFlow.set_asides(scope(@form, h, "ana"))
          assert sa.total == 30_000 + 30_000 + 10_000 + 20_000 + 10_000
          assert sa.total == sa.items |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        end

        test "REQ-140 AC-10: the covered items are listed, each by name with its own monthly amount",
             %{h: h} do
          sa = FindependenceShared.CashFlow.set_asides(scope(@form, h, "ana"))

          assert sa.items |> Enum.map(fn {i, c} -> {i.attrs.note, c} end) |> Enum.sort() ==
                   Enum.sort([
                     {"Water", 30_000},
                     {"Gas", 30_000},
                     {"Car insurance", 10_000},
                     {"Property tax", 20_000},
                     {"Repairs", 10_000}
                   ])
        end
      end

      describe "REQ-142" do
        test "REQ-142 AC-1: a member creates a plan with a name; an empty name is refused" do
          h = household(@form, ~w(ana))
          p = B2.plan(@form, h, "ana", "If my job stops")

          assert %{name: "If my job stops", steps: []} =
                   FindependenceShared.Planning.plan(scope(@form, h, "ana"), p)

          for bad <- ["", "   ", nil],
              do:
                assert(
                  {:error, :validation, :invalid_plan, _} =
                    FindependenceShared.Planning.new_plan(
                      scope(@form, h, "ana"),
                      B2.new_id("p"),
                      bad
                    )
                )

          assert map_size(FindependenceShared.Planning.plans(scope(@form, h, "ana"))) == 1
        end

        test "REQ-142 AC-2: a member keeps several plans, each with any number of steps" do
          h = household(@form, ~w(ana))

          rent =
            add_item(@form, h, "ana", "Rent", amount: -100_000, frequency: {:every, 1, :month})

          p1 = B2.plan(@form, h, "ana", "One")
          p2 = B2.plan(@form, h, "ana", "Two")

          for mo <- ~w(2026-11 2026-12 2027-01),
              do:
                :ok =
                  B2.step!(@form, h, "ana", p1, %{kind: "switch_off", items: [rent], from: mo})

          :ok =
            B2.step!(@form, h, "ana", p2, %{
              kind: "add",
              note: "Gym",
              amount: {:ok, -4_000},
              frequency: {:every, 1, :month},
              from: "2026-11"
            })

          plans = FindependenceShared.Planning.plans(scope(@form, h, "ana"))
          assert map_size(plans) == 2
          assert length(plans[p1].steps) == 3
          assert length(plans[p2].steps) == 1
        end

        test "REQ-142 AC-3: a switch-off turns off owned items from a month; others' items and non-money items are refused" do
          h = household(@form, ~w(ana ben))

          rent =
            add_item(@form, h, "ana", "Rent", amount: -100_000, frequency: {:every, 1, :month})

          bens =
            add_item(@form, h, "ben", "Ben's rent",
              amount: -50_000,
              frequency: {:every, 1, :month}
            )

          :ok = B2.grant(@form, h, "ben", bens, "ana")
          chk = B2.account(@form, h, "ana")
          {:ok, _} = FindependenceShared.Values.add_value(scope(@form, h, "ana"), "Home")

          value =
            Enum.find_value(view(@form, h, "ana").items, fn {id, i} ->
              i.attrs[:kind] == :value && id
            end)

          p = B2.plan(@form, h, "ana", "Move")

          for other <- [bens, chk, value, "nope"],
              do:
                assert(
                  {:error, :validation, :invalid_step, _} =
                    B2.step(@form, h, "ana", p, %{
                      kind: "switch_off",
                      items: [other],
                      from: "2026-12"
                    })
                )

          :ok =
            B2.step!(@form, h, "ana", p, %{kind: "switch_off", items: [rent], from: "2026-12"})

          with_plan = B2.project(@form, h, "ana", p)
          # only what Ana owns counts in her months; Ben's shared item never does
          assert B2.month(with_plan, "2026-11").out == -100_000
          assert B2.month(with_plan, "2026-12").out == 0
          assert B2.month(with_plan, "2027-09").out == 0
        end

        test "REQ-142 AC-4: a planned money step applies from a month; a planned one-off happens once, in that month" do
          h = household(@form, ~w(ana))
          p = B2.plan(@form, h, "ana", "Side job")

          :ok =
            B2.step!(@form, h, "ana", p, %{
              kind: "add",
              note: "Side job",
              amount: {:ok, 100_000},
              frequency: {:every, 1, :month},
              from: "2026-11"
            })

          :ok =
            B2.step!(@form, h, "ana", p, %{
              kind: "add",
              note: "Tools",
              amount: {:ok, -150_000},
              frequency: :one_off,
              from: "2026-12"
            })

          pr = B2.project(@form, h, "ana", p)
          assert B2.month(pr, "2026-10").in == 0 and B2.month(pr, "2026-10").out == 0
          assert B2.month(pr, "2026-11").in == 100_000 and B2.month(pr, "2026-11").out == 0
          assert B2.month(pr, "2026-12").in == 100_000 and B2.month(pr, "2026-12").out == -150_000
          assert B2.month(pr, "2027-01").in == 100_000 and B2.month(pr, "2027-01").out == 0
          assert B2.month(pr, "2027-09").in == 100_000

          assert {:error, :validation, "Choose how often the planned item happens."} =
                   B2.step(@form, h, "ana", p, %{
                     kind: "add",
                     note: "X",
                     amount: {:ok, 1},
                     frequency: nil,
                     from: "2026-11"
                   })
        end

        test "REQ-142 AC-5: a borrow step takes an amount, a rate, and a monthly payment, from a month" do
          h = household(@form, ~w(ana))
          p = B2.plan(@form, h, "ana", "Borrow")
          b = %{amount: 500_000, rate_bp: 900, payment: 20_000}
          :ok = B2.step!(@form, h, "ana", p, %{kind: "borrow", borrow: {:ok, b}, from: "2026-12"})

          assert [%{n: 1, step: {:borrow, ^b, "2026-12"}}] =
                   FindependenceShared.Planning.plan(scope(@form, h, "ana"), p).steps

          for bad <- [
                {:ok, %{b | amount: 0}},
                {:ok, %{b | rate_bp: 20_000}},
                {:ok, %{b | payment: 0}},
                :error
              ],
              do:
                assert(
                  {:error, :validation, _} =
                    B2.step(@form, h, "ana", p, %{kind: "borrow", borrow: bad, from: "2026-12"})
                )

          assert {:error, :validation, :invalid_step, _} =
                   B2.step(@form, h, "ana", p, %{
                     kind: "borrow",
                     borrow: {:ok, b},
                     from: "December"
                   })
        end

        test "REQ-142 AC-6: steps can be added and removed" do
          h = household(@form, ~w(ana))

          rent =
            add_item(@form, h, "ana", "Rent", amount: -100_000, frequency: {:every, 1, :month})

          p = B2.plan(@form, h, "ana", "Plan")

          :ok =
            B2.step!(@form, h, "ana", p, %{kind: "switch_off", items: [rent], from: "2026-11"})

          :ok =
            B2.step!(@form, h, "ana", p, %{kind: "switch_off", items: [rent], from: "2026-12"})

          assert [%{n: 1}, %{n: 2}] =
                   FindependenceShared.Planning.plan(scope(@form, h, "ana"), p).steps

          {:ok, _} = FindependenceShared.Planning.remove_step(scope(@form, h, "ana"), p, 1)
          assert [%{n: 2}] = FindependenceShared.Planning.plan(scope(@form, h, "ana"), p).steps

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.remove_step(scope(@form, h, "ana"), p, 1)
        end

        test "REQ-142 AC-7: plans are private: another member can't see, open, or add to them" do
          h = household(@form, ~w(ana ben))

          bens =
            add_item(@form, h, "ben", "Ben's rent",
              amount: -50_000,
              frequency: {:every, 1, :month}
            )

          p = B2.plan(@form, h, "ana", "Qzvx secret plan")

          sb = scope(@form, h, "ben")
          assert FindependenceShared.Planning.plans(sb) == %{}
          assert FindependenceShared.Planning.plan(sb, p) == nil

          assert {:error, :not_found, :not_found, _} =
                   B2.step(@form, h, "ben", p, %{
                     kind: "switch_off",
                     items: [bens],
                     from: "2026-12"
                   })

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.remove_step(scope(@form, h, "ben"), p, 1)

          assert %{steps: []} = FindependenceShared.Planning.plan(scope(@form, h, "ana"), p)
          # stored only in Ana's own personal record, never in plaintext
          personal = stored(@form, h).personal
          assert Map.has_key?(personal, id(@form, h, "ana"))
          refute Enum.any?(stored_bytes(@form, h), &(&1 =~ "Qzvx secret plan"))
        end

        test "REQ-142 AC-8: plans never change a real total" do
          h = household(@form, ~w(ana))
          chk = B2.account(@form, h, "ana")
          :ok = B2.add_reading!(@form, h, "ana", chk, B2.account_input("2026-09-27", 500_000))

          rent =
            add_item(@form, h, "ana", "Rent",
              amount: -100_000,
              frequency: {:every, 1, :month},
              on: "2026-10-01"
            )

          pay =
            add_item(@form, h, "ana", "Pay",
              amount: 300_000,
              frequency: {:every, 1, :month},
              on: "2026-10-15"
            )

          add_item(@form, h, "ana", "Insurance", amount: -60_000, frequency: {:every, 6, :month})
          {:ok, _} = FindependenceShared.Planning.set_fund_goal(scope(@form, h, "ana"), 3)
          before = B2.real_totals(@form, h, "ana")

          p = B2.plan(@form, h, "ana", "Everything changes")

          :ok =
            B2.step!(@form, h, "ana", p, %{
              kind: "switch_off",
              items: [rent, pay],
              from: "2026-11"
            })

          :ok =
            B2.step!(@form, h, "ana", p, %{
              kind: "add",
              note: "New cost",
              amount: {:ok, -70_000},
              frequency: {:every, 1, :month},
              from: "2026-11"
            })

          :ok =
            B2.step!(@form, h, "ana", p, %{
              kind: "borrow",
              borrow: {:ok, %{amount: 500_000, rate_bp: 900, payment: 20_000}},
              from: "2026-12"
            })

          assert B2.real_totals(@form, h, "ana") == before
          refute B2.project(@form, h, "ana", p) == before.project
        end
      end

      describe "REQ-143" do
        test "REQ-143 AC-1: for a plan, the twelve months each have a figure without and with the plan" do
          h = household(@form, ~w(ana))
          pay = add_item(@form, h, "ana", "Pay", amount: 300_000, frequency: {:every, 1, :month})
          p = B2.plan(@form, h, "ana", "Job stops")
          :ok = B2.step!(@form, h, "ana", p, %{kind: "switch_off", items: [pay], from: "2027-01"})

          without = B2.project(@form, h, "ana")
          with_plan = B2.project(@form, h, "ana", p)
          months = FindependenceShared.CashFlow.months(B2.today())
          assert length(months) == 12
          assert Enum.map(without.months, & &1.month) == months
          assert Enum.map(with_plan.months, & &1.month) == months

          for {a, b} <- Enum.zip(without.months, with_plan.months) do
            assert a.in == 300_000
            assert b.in == if(a.month < "2027-01", do: 300_000, else: 0)
          end
        end

        test "REQ-143 AC-2: the with-plan figures include interest on planned borrowing" do
          h = household(@form, ~w(ana))
          p = B2.plan(@form, h, "ana", "Borrow")
          b = %{amount: 500_000, rate_bp: 900, payment: 20_000}
          :ok = B2.step!(@form, h, "ana", p, %{kind: "borrow", borrow: {:ok, b}, from: "2026-12"})

          with_plan = B2.project(@form, h, "ana", p)
          assert [loan] = Enum.filter(with_plan.debts, & &1.planned)
          # 5,000 at 9%: 37.50 of interest in January, then 200 paid
          assert Enum.at(loan.months, 3) == 483_750
          assert loan.interest > 0
          # the money borrowed comes in December; the payments go out after it
          assert B2.month(with_plan, "2026-12").net == 500_000
          assert B2.month(with_plan, "2027-01").net == -20_000
          assert B2.project(@form, h, "ana").debts == []
        end
      end

      describe "REQ-144" do
        test "REQ-144 AC-1: a member marks an item they own as depending on an income item they own" do
          h = household(@form, ~w(ana))
          pay = add_item(@form, h, "ana", "Pay", amount: 300_000, frequency: {:every, 1, :month})

          health =
            add_item(@form, h, "ana", "Health", amount: -20_000, frequency: {:every, 1, :month})

          {:ok, _} = FindependenceShared.Planning.mark(scope(@form, h, "ana"), health, pay)
          assert FindependenceShared.Planning.depends(scope(@form, h, "ana")) == [{health, pay}]
        end

        test "REQ-144 AC-2: the job must be an income item the member owns; anything else is refused" do
          h = household(@form, ~w(ana ben))
          pay = add_item(@form, h, "ana", "Pay", amount: 300_000, frequency: {:every, 1, :month})

          health =
            add_item(@form, h, "ana", "Health", amount: -20_000, frequency: {:every, 1, :month})

          bens_pay =
            add_item(@form, h, "ben", "Ben's pay",
              amount: 200_000,
              frequency: {:every, 1, :month}
            )

          bens_cost =
            add_item(@form, h, "ben", "Ben's gym", amount: -4_000, frequency: {:every, 1, :month})

          :ok = B2.grant(@form, h, "ben", bens_pay, "ana")
          :ok = B2.grant(@form, h, "ben", bens_cost, "ana")
          chk = B2.account(@form, h, "ana")
          s = fn -> scope(@form, h, "ana") end

          assert {:error, :validation, :not_income, _} =
                   FindependenceShared.Planning.mark(s.(), pay, health)

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.mark(s.(), health, bens_pay)

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.mark(s.(), bens_cost, pay)

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.mark(s.(), chk, pay)

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.mark(s.(), health, chk)

          assert FindependenceShared.Planning.depends(s.()) == []
        end

        test "REQ-144 AC-3: a member can remove a mark" do
          h = household(@form, ~w(ana))
          pay = add_item(@form, h, "ana", "Pay", amount: 300_000, frequency: {:every, 1, :month})

          health =
            add_item(@form, h, "ana", "Health", amount: -20_000, frequency: {:every, 1, :month})

          {:ok, _} = FindependenceShared.Planning.mark(scope(@form, h, "ana"), health, pay)
          {:ok, _} = FindependenceShared.Planning.unmark(scope(@form, h, "ana"), health, pay)
          assert FindependenceShared.Planning.depends(scope(@form, h, "ana")) == []

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.unmark(scope(@form, h, "ana"), health, pay)
        end

        test "REQ-144 AC-4: switching off the job switches off the items marked on it, from the same month" do
          h = household(@form, ~w(ana))
          pay = add_item(@form, h, "ana", "Pay", amount: 300_000, frequency: {:every, 1, :month})

          health =
            add_item(@form, h, "ana", "Health", amount: -20_000, frequency: {:every, 1, :month})

          add_item(@form, h, "ana", "Rent", amount: -100_000, frequency: {:every, 1, :month})
          {:ok, _} = FindependenceShared.Planning.mark(scope(@form, h, "ana"), health, pay)
          p = B2.plan(@form, h, "ana", "Job stops")
          :ok = B2.step!(@form, h, "ana", p, %{kind: "switch_off", items: [pay], from: "2026-12"})

          pr = B2.project(@form, h, "ana", p)
          assert %{in: 300_000, out: -120_000} = B2.month(pr, "2026-11")
          assert %{in: 0, out: -100_000} = B2.month(pr, "2026-12")
          assert %{in: 0, out: -100_000} = B2.month(pr, "2027-09")
        end

        test "REQ-144 AC-5: marks are private: another member has none and can't make or read them" do
          h = household(@form, ~w(ana ben))
          pay = add_item(@form, h, "ana", "Pay", amount: 300_000, frequency: {:every, 1, :month})

          health =
            add_item(@form, h, "ana", "Health", amount: -20_000, frequency: {:every, 1, :month})

          :ok = B2.grant(@form, h, "ana", pay, "ben")
          :ok = B2.grant(@form, h, "ana", health, "ben")
          {:ok, _} = FindependenceShared.Planning.mark(scope(@form, h, "ana"), health, pay)

          assert FindependenceShared.Planning.depends(scope(@form, h, "ben")) == []

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.mark(scope(@form, h, "ben"), health, pay)

          assert {:error, :not_found, :not_found, _} =
                   FindependenceShared.Planning.unmark(scope(@form, h, "ben"), health, pay)

          assert view(@form, h, "ben").depends == %{id(@form, h, "ben") => MapSet.new()}
          assert FindependenceShared.Planning.depends(scope(@form, h, "ana")) == [{health, pay}]
        end
      end

      describe "REQ-145" do
        # 1,000.00 at 12% (1% a month) with a minimum of 500: 1,000 + 10 - 500 = 510; 510 + 5.10 - 500 =
        # 15.10; 15.10 + 0.15 cleared: three months, 15.25 of interest.
        test "REQ-145 AC-1: the months to clear a debt at the minimum, and the interest over that time" do
          h = household(@form, ~w(ana))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 100_000, 1200, 50_000)
            )

          r = FindependenceShared.Balances.latest(scope(@form, h, "ana"), visa)

          assert FindependenceShared.Balances.payoff(r.balance, r.rate_bp, r.min_payment) ==
                   {:ok, 3, 1_525}

          # a minimum that doesn't cover a month's interest never clears it
          assert FindependenceShared.Balances.payoff(r.balance, r.rate_bp, 1_000) == :never
        end

        test "REQ-145 AC-2: the same with an extra monthly amount" do
          h = household(@form, ~w(ana))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 100_000, 1200, 50_000)
            )

          r = FindependenceShared.Balances.latest(scope(@form, h, "ana"), visa)
          # 1,000 + 10 - 700 = 310; 310 + 3.10 cleared
          assert FindependenceShared.Balances.payoff(r.balance, r.rate_bp, r.min_payment + 20_000) ==
                   {:ok, 2, 1_310}
        end

        test "REQ-145 AC-3: the monthly interest at a different rate" do
          h = household(@form, ~w(ana))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 100_000, 1200, 50_000)
            )

          r = FindependenceShared.Balances.latest(scope(@form, h, "ana"), visa)
          assert FindependenceShared.Balances.monthly_interest(r) == 1_000
          assert FindependenceShared.Balances.monthly_interest(%{r | rate_bp: 2400}) == 2_000
        end

        test "REQ-145 AC-4: every figure is worked out from the latest reading, for owners and others who can see it" do
          h = household(@form, ~w(ana ben))
          visa = B2.debt(@form, h, "ana")
          :ok = B2.grant(@form, h, "ana", visa, "ben")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-08-27", 900_000, 2400, 10_000)
            )

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 100_000, 1200, 50_000)
            )

          for n <- ~w(ana ben) do
            r = FindependenceShared.Balances.latest(scope(@form, h, n), visa)
            assert %{seq: 2, balance: 100_000, rate_bp: 1200, min_payment: 50_000} = r

            assert FindependenceShared.Balances.payoff(r.balance, r.rate_bp, r.min_payment) ==
                     {:ok, 3, 1_525}

            assert FindependenceShared.Balances.monthly_interest(r) == 1_000
          end
        end

        test "REQ-145 AC-5: a member the debt is shared with sees all three figures" do
          h = household(@form, ~w(ana ben))
          visa = B2.debt(@form, h, "ana")

          :ok =
            B2.add_reading!(
              @form,
              h,
              "ana",
              visa,
              B2.debt_input("2026-09-27", 100_000, 1200, 50_000)
            )

          assert FindependenceShared.Balances.latest(scope(@form, h, "ben"), visa) == nil
          :ok = B2.grant(@form, h, "ana", visa, "ben")

          r = FindependenceShared.Balances.latest(scope(@form, h, "ben"), visa)

          refute id(@form, h, "ben") in FindependenceShared.Items.lookup(
                   scope(@form, h, "ben"),
                   visa
                 ).owners

          assert FindependenceShared.Balances.payoff(r.balance, r.rate_bp, r.min_payment) ==
                   {:ok, 3, 1_525}

          assert FindependenceShared.Balances.payoff(r.balance, r.rate_bp, r.min_payment + 20_000) ==
                   {:ok, 2, 1_310}

          assert FindependenceShared.Balances.monthly_interest(%{r | rate_bp: 2400}) == 2_000
        end
      end
    end
  end
end
