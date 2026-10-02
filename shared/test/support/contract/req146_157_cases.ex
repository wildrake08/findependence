defmodule FindependenceShared.Contract.B3 do
  @moduledoc """
  Helpers for the contract cases of REQ-146..157 (REQ-188 AC-1, WI-074, batch 3). Each takes the form module
  first, like `FindependenceShared.Contract.Helpers`.
  """

  alias FindependenceShared.{Balances, Items, Persistence, Planning, Portability, Values}
  alias FindependenceShared.Contract.Helpers, as: H

  @doc "The fixed date the retirement cases use."
  def today, do: ~D[2026-11-15]

  @doc "A sorted list from a list or MapSet."
  def sorted(x), do: x |> Enum.to_list() |> Enum.sort()

  @doc "A reading form's input for an account, as the transport decodes it."
  def reading(on, cents), do: %{balance: {:ok, abs(cents), cents < 0}, on: {:ok, on}}

  @doc "A reading form's input for a debt."
  def debt_reading(on, cents, rate_bp, min),
    do: %{
      balance: {:ok, cents, false},
      on: {:ok, on},
      rate: {:ok, rate_bp},
      min_payment: {:ok, min}
    }

  @doc "Adds an account for the named member and returns its id."
  def account(form, h, name, label, type) do
    id = Persistence.new_id()
    {:ok, _} = Balances.add_account(H.scope(form, h, name), id, label, type)
    id
  end

  @doc "Adds a debt for the named member and returns its id."
  def debt(form, h, name, label, type) do
    id = Persistence.new_id()
    {:ok, _} = Balances.add_debt(H.scope(form, h, name), id, label, type)
    id
  end

  @doc "Adds an account reading as the named member."
  def read!(form, h, name, id, on, cents),
    do: {:ok, _} = Balances.add_reading(H.scope(form, h, name), id, reading(on, cents))

  @doc "Adds a value for the named member and returns its id."
  def value(form, h, name, label) do
    {:ok, saved} = Values.add_value(H.scope(form, h, name), label)
    Enum.find_value(saved.household.items, fn {id, i} -> if i.attrs[:label] == label, do: id end)
  end

  @doc "The named member shares an item with another named member."
  def grant(form, h, name, item, to),
    do: {:ok, _} = Items.propose_grant(H.scope(form, h, name), item, H.id(form, h, to))

  @doc "The named member proposes the named owners for an item."
  def owners(form, h, name, item, names), do: H.change_owners(form, h, name, item, names)

  @doc "An item's owners in the named member's view, as sorted member ids."
  def owners_of(form, h, name, item), do: sorted(H.view(form, h, name).items[item].owners)

  @doc "The ids of the named members, sorted."
  def ids(form, h, names), do: names |> Enum.map(&H.id(form, h, &1)) |> Enum.sort()

  @doc """
  The retirement form's input, as the transport decodes it: every field given (`{:ok, nil}` clears), and
  contributions as `[{account, cents_or_nil}]`.
  """
  def retirement(fields, contributions \\ []) do
    base =
      Map.new(
        [:birth_year, :retire_age, :return_bp, :ss_monthly, :target_monthly],
        &{&1, {:ok, nil}}
      )

    fields
    |> Map.new(fn
      {k, {:error, _} = e} -> {k, e}
      {k, v} -> {k, {:ok, v}}
    end)
    |> then(&Map.merge(base, &1))
    |> Map.put(
      :contributions,
      Enum.map(contributions, fn
        {id, {:error, _} = e} -> {id, e}
        {id, c} -> {id, {:ok, c}}
      end)
    )
  end

  @doc "Saves retirement assumptions as the named member."
  def save_retirement!(form, h, name, fields, contributions \\ []),
    do:
      {:ok, _} =
        Planning.save_retirement(H.scope(form, h, name), retirement(fields, contributions))

  @doc "The named member's retirement assumptions."
  def settings(form, h, name), do: Planning.retirement_settings(H.scope(form, h, name))

  @doc "Adds a plan step as the named member."
  def step!(form, h, name, plan, input),
    do: {:ok, _} = Planning.add_step(H.scope(form, h, name), plan, input)

  def add_step(note, amount, frequency, from),
    do: %{kind: "add", note: note, amount: {:ok, amount}, frequency: frequency, from: from}

  def switch_off(items, from), do: %{kind: "switch_off", items: items, from: from}

  def borrow(amount, rate_bp, payment, from),
    do: %{
      kind: "borrow",
      borrow: {:ok, %{amount: amount, rate_bp: rate_bp, payment: payment}},
      from: from
    }

  @doc "The shared plan items in the named member's view, by id."
  def shared_plans(form, h, name),
    do: for({id, i} <- H.view(form, h, name).items, Planning.plan?(i), do: id)

  @doc "The named member's file, as saved (format data)."
  def file(form, h, name), do: Portability.to_data(Portability.export(H.scope(form, h, name)))

  @doc "Data as file bytes."
  def bytes(data), do: IO.iodata_to_binary(:json.encode(data))

  @doc "The index of the item named `note` in a file."
  def index(data, note),
    do: Enum.find_index(data["items"], &((&1["attrs"]["note"] || &1["attrs"]["label"]) == note))

  @doc "The id in the file of the item named `note`."
  def file_id(data, note), do: Enum.at(data["items"], index(data, note))["id"]

  @doc "Puts `value` at `path` (keys and list indexes) in the data."
  def at(data, path, value), do: put_in(data, Enum.map(path, &access/1), value)
  defp access(i) when is_integer(i), do: Access.at(i)
  defp access(k), do: k

  @doc "The problems the named member's check finds in the data."
  def problems(form, h, name, data) do
    {:error, :validation, {:problems, ps}} =
      Portability.check(H.scope(form, h, name), bytes(data))

    ps
  end

  @doc "Every reference the file makes to an entry, as {where, id}."
  def references(data) do
    List.flatten(
      for(l <- data["links"], do: [{"link", l["item"]}, {"link", l["value"]}]) ++
        for(m <- data["marks"], do: [{"mark", m["item"]}, {"mark", m["job"]}]) ++
        for(a <- data["attached"], do: [{"attached", a["item"]}, {"attached", a["account"]}]) ++
        for(
          p <- data["plans"],
          s <- p["steps"],
          s["kind"] == "switch_off",
          do: Enum.map(s["items"], &{"plan step", &1})
        ) ++
        for(s <- data["goals"]["set_aside"], do: [{"set-aside", s["value"]}]) ++
        for(c <- data["retirement"]["contributions"], do: [{"contribution", c["account"]}])
    )
  end

  @doc "The entries the named member owns, by name (note or label)."
  def owned(form, h, name) do
    s = H.scope(form, h, name)
    m = H.id(form, h, name)

    for i <- Items.visible(s),
        m in i.owners,
        into: %{},
        do: {i.attrs[:note] || i.attrs[:label], i.id}
  end

  @doc """
  Ana's record for the export cases (as in core's import_test.exs): money items, a joint bill, a value and
  a link, an account and a debt with readings, a 401(k), a mark, a plan with every kind of step, goals,
  retirement assumptions, an attachment, and Ben's phone shared with her. Returns the ids by name.
  """
  def ana_record(form, h) do
    pay =
      H.add_item(form, h, "ana", "Paycheck",
        amount: 265_000,
        frequency: {:every, 2, :week},
        on: "2026-10-02"
      )

    health = H.add_item(form, h, "ana", "Health plan", amount: -9_000)
    rent = H.add_item(form, h, "ana", "Rent", amount: -150_000)
    {:ok, _} = owners(form, h, "ana", rent, ~w(ana ben))
    phone = H.add_item(form, h, "ben", "Ben's phone", amount: -5_000)
    grant(form, h, "ben", phone, "ana")
    home = value(form, h, "ana", "A safe home")
    ana = H.scope(form, h, "ana")
    {:ok, _} = Values.link(ana, rent, home)
    chk = account(form, h, "ana", "Checking", :checking)
    read!(form, h, "ana", chk, "2026-09-01", 50_000)
    read!(form, h, "ana", chk, "2026-09-26", -2_500)
    visa = debt(form, h, "ana", "Visa", :card)

    {:ok, _} =
      Balances.add_reading(
        H.scope(form, h, "ana"),
        visa,
        debt_reading("2026-09-26", 620_000, 2499, 19_000)
      )

    k401 = account(form, h, "ana", "401(k)", :retirement_401k)
    read!(form, h, "ana", k401, "2026-09-26", 4_820_000)
    {:ok, _} = Planning.mark(H.scope(form, h, "ana"), health, pay)
    {:ok, _} = Planning.new_plan(H.scope(form, h, "ana"), "p1", "If the job stops")
    step!(form, h, "ana", "p1", switch_off([pay], "2026-11"))
    step!(form, h, "ana", "p1", add_step("Premium", -48_000, {:every, 1, :month}, "2026-11"))
    step!(form, h, "ana", "p1", borrow(600_000, 875, 25_000, "2026-12"))
    {:ok, _} = Planning.set_fund_goal(H.scope(form, h, "ana"), 3)
    {:ok, _} = Planning.set_aside(H.scope(form, h, "ana"), home, 2500)

    save_retirement!(
      form,
      h,
      "ana",
      [
        birth_year: 1976,
        retire_age: 67,
        return_bp: 400,
        ss_monthly: 230_000,
        target_monthly: 550_000
      ],
      [{k401, 40_000}]
    )

    {:ok, _} = Balances.attach(H.scope(form, h, "ana"), pay, chk)

    %{
      pay: pay,
      health: health,
      rent: rent,
      phone: phone,
      home: home,
      chk: chk,
      visa: visa,
      k401: k401
    }
  end

  @doc "The named member checks the file and brings it in."
  def bring_in(form, h, name, data) do
    s = H.scope(form, h, name)
    {:ok, %{bundle: b, fingerprint: fp}} = Portability.check(s, bytes(data))
    Portability.bring_in(s, b, fp, ~D[2026-09-27])
  end

  @doc "The balances of the readings a member can read, from `Balances.readings/2`."
  def readable({:ok, rs}), do: for(r <- rs, is_map(r), Map.has_key?(r, :balance), do: r.balance)
  def readable({:error, _}), do: []

  @doc """
  Ana's retirement projection with one assumption changed: saved, worked out, and the assumptions put
  back as they were.
  """
  def projection_with(form, h, _account, change) do
    current = settings(form, h, "ana")
    fields = fn s -> s |> Map.drop([:contributions]) |> Map.to_list() end
    contributions = Map.to_list(current.contributions)
    save_retirement!(form, h, "ana", Keyword.merge(fields.(current), change), contributions)
    p = Planning.retirement_projection(H.scope(form, h, "ana"), today())
    save_retirement!(form, h, "ana", fields.(current), contributions)
    ^current = settings(form, h, "ana")
    p
  end

  @doc "Ana's 401(k) with 10,000.00 on 2026-11-01; born 1961, retiring at 67, 12%, 100.00 a month."
  def retirement_record(form, h, extra \\ []) do
    k = account(form, h, "ana", "Ana's 401(k)", :retirement_401k)
    read!(form, h, "ana", k, "2026-11-01", 1_000_000)

    save_retirement!(
      form,
      h,
      "ana",
      [birth_year: 1961, retire_age: 67, return_bp: 1200] ++ extra,
      [{k, 10_000}]
    )

    k
  end
end

defmodule FindependenceShared.Contract.Cases.Req146To157 do
  @moduledoc """
  Contract cases for the CORE and PERSIST acceptance criteria of REQ-146..151 and REQ-153..157 (REQ-188 AC-1,
  WI-074, batch 3), run on both forms through the shared contexts. WEB and LOCAL criteria are not here.
  """

  defmacro __using__(_) do
    quote do
      describe "REQ-146" do
        alias FindependenceShared.{Items, Planning}
        alias FindependenceShared.Contract.B3

        test "REQ-146 AC-1: a fund goal can be set and cleared; an out-of-range value is refused" do
          h = household(@form, ~w(ana ben))
          {:ok, _} = Planning.set_fund_goal(scope(@form, h, "ana"), 3)
          assert Planning.goals(scope(@form, h, "ana")).fund_months == 3

          for bad <- [0, 61, -1, 2.5, :invalid] do
            assert {:error, :validation, :invalid_goal, _} =
                     Planning.set_fund_goal(scope(@form, h, "ana"), bad)
          end

          assert Planning.goals(scope(@form, h, "ana")).fund_months == 3
          {:ok, _} = Planning.set_fund_goal(scope(@form, h, "ana"), 60)
          assert Planning.goals(scope(@form, h, "ana")).fund_months == 60
          {:ok, _} = Planning.set_fund_goal(scope(@form, h, "ana"), 1)
          assert Planning.goals(scope(@form, h, "ana")).fund_months == 1
          {:ok, _} = Planning.set_fund_goal(scope(@form, h, "ana"), nil)
          assert Planning.goals(scope(@form, h, "ana")).fund_months == nil
        end

        test "REQ-146 AC-2: cover counts savings the member can see, against money out of items they own" do
          h = household(@form, ~w(ana ben))
          sav = B3.account(@form, h, "ana", "Ana's savings", :savings)
          B3.read!(@form, h, "ana", sav, "2026-09-27", 600_000)
          add_item(@form, h, "ana", "Rent", amount: -200_000)
          add_item(@form, h, "ana", "TV", amount: -120_000, frequency: :one_off)
          bsav = B3.account(@form, h, "ben", "Ben's savings", :savings)
          B3.read!(@form, h, "ben", bsav, "2026-09-27", 300_000)
          gym = add_item(@form, h, "ben", "Gym", amount: -50_000)

          # before Ben shares, Ana sees only her own savings
          assert Planning.cover(scope(@form, h, "ana")).savings == 600_000

          B3.grant(@form, h, "ben", bsav, "ana")
          B3.grant(@form, h, "ben", gym, "ana")
          c = Planning.cover(scope(@form, h, "ana"))
          # 9,000 of savings she can see, against her own 2,000 a month: Ben's gym isn't hers
          assert c.savings == 900_000 and c.monthly_out == 200_000 and c.months == 4.5
          assert Enum.sort(c.accounts) == Enum.sort([sav, bsav])

          # Ben sees his own savings only, against his own gym
          b = Planning.cover(scope(@form, h, "ben"))
          assert b.savings == 300_000 and b.monthly_out == 50_000 and b.months == 6.0
        end

        test "REQ-146 AC-3: with a goal set, the member sees their progress toward it" do
          h = household(@form, ~w(ana ben))
          sav = B3.account(@form, h, "ana", "Savings", :savings)
          B3.read!(@form, h, "ana", sav, "2026-09-27", 600_000)
          add_item(@form, h, "ana", "Rent", amount: -200_000)
          assert Planning.cover(scope(@form, h, "ana")).goal == nil
          {:ok, _} = Planning.set_fund_goal(scope(@form, h, "ana"), 5)
          c = Planning.cover(scope(@form, h, "ana"))
          assert c.goal == 5 and c.months == 3.0
        end

        test "REQ-146 AC-4: the goal is private, even from a member who sees the same savings" do
          h = household(@form, ~w(ana ben))
          sav = B3.account(@form, h, "ana", "Savings", :savings)
          B3.read!(@form, h, "ana", sav, "2026-09-27", 600_000)
          {:ok, _} = Planning.set_fund_goal(scope(@form, h, "ana"), 5)
          B3.grant(@form, h, "ana", sav, "ben")

          ben = scope(@form, h, "ben")
          assert Items.visible?(ben, sav)
          assert Planning.cover(ben).savings == 600_000
          assert Planning.goals(ben).fund_months == nil
          assert Planning.cover(ben).goal == nil
          # Ben's view holds no one else's private record
          refute Map.has_key?(ben.household.goals, id(@form, h, "ana"))
          assert Planning.goals(scope(@form, h, "ana")).fund_months == 5

          # each member's private record is sealed separately
          assert Map.has_key?(stored(@form, h).personal, id(@form, h, "ana"))
        end
      end

      describe "REQ-147" do
        alias FindependenceShared.{Items, Planning, Values}
        alias FindependenceShared.Contract.B3

        test "REQ-147 AC-1: a set-aside rate can be set and removed for a value the member can see" do
          h = household(@form, ~w(ana ben))
          v = B3.value(@form, h, "ana", "Side business")
          {:ok, _} = Planning.set_aside(scope(@form, h, "ana"), v, 2500)
          assert Planning.goals(scope(@form, h, "ana")).set_aside == %{v => 2500}
          {:ok, _} = Planning.set_aside(scope(@form, h, "ana"), v, nil)
          assert Planning.goals(scope(@form, h, "ana")).set_aside == %{}

          # a value shared with the member is one they can see
          bv = B3.value(@form, h, "ben", "Ben's value")
          B3.grant(@form, h, "ben", bv, "ana")
          {:ok, _} = Planning.set_aside(scope(@form, h, "ana"), bv, 1000)
          assert Planning.goals(scope(@form, h, "ana")).set_aside == %{bv => 1000}
        end

        test "REQ-147 AC-2: a rate for a value the member can't see is refused" do
          h = household(@form, ~w(ana ben))
          bv = B3.value(@form, h, "ben", "Ben's value")

          assert {:error, :not_found, :not_found, _} =
                   Planning.set_aside(scope(@form, h, "ana"), bv, 2500)

          assert Planning.goals(scope(@form, h, "ana")).set_aside == %{}
        end

        test "REQ-147 AC-3: the monthly amount set aside from repeating money in linked by the member's own links" do
          h = household(@form, ~w(ana ben))
          v = B3.value(@form, h, "ana", "Side business")
          shop = add_item(@form, h, "ana", "Shop sales", amount: 50_000)
          fair = add_item(@form, h, "ana", "Craft fair", amount: 90_000, frequency: :one_off)
          {:ok, _} = Values.link(scope(@form, h, "ana"), shop, v)
          {:ok, _} = Values.link(scope(@form, h, "ana"), fair, v)

          # Ben links his own money in to the same value: it isn't Ana's link
          B3.grant(@form, h, "ana", v, "ben")
          tips = add_item(@form, h, "ben", "Tips", amount: 30_000)
          {:ok, _} = Values.link(scope(@form, h, "ben"), tips, v)

          {:ok, _} = Planning.set_aside(scope(@form, h, "ana"), v, 2500)

          assert Planning.set_asides(scope(@form, h, "ana")) == [
                   %{value_id: v, rate_bp: 2500, monthly_in: 50_000, set_aside: 12_500}
                 ]
        end

        test "REQ-147 AC-4: the rate is private: another member has no set-aside from it" do
          h = household(@form, ~w(ana ben))
          v = B3.value(@form, h, "ana", "Side business")
          shop = add_item(@form, h, "ana", "Shop sales", amount: 50_000)
          {:ok, _} = Values.link(scope(@form, h, "ana"), shop, v)
          {:ok, _} = Planning.set_aside(scope(@form, h, "ana"), v, 2500)
          B3.grant(@form, h, "ana", v, "ben")
          B3.grant(@form, h, "ana", shop, "ben")

          ben = scope(@form, h, "ben")
          assert Items.visible?(ben, v)
          assert Planning.set_asides(ben) == []
          assert Planning.goals(ben).set_aside == %{}
          assert [%{set_aside: 12_500}] = Planning.set_asides(scope(@form, h, "ana"))
        end
      end

      describe "REQ-148" do
        alias FindependenceShared.{Items, Planning}
        alias FindependenceShared.Contract.B3

        # Ana's plan "Trip": a one-off hotel, and her gym switched off.
        setup do
          h = household(@form, ~w(ana ben cy))
          gym = add_item(@form, h, "ana", "Gym", amount: -5_000)
          {:ok, _} = Planning.new_plan(scope(@form, h, "ana"), "p1", "Trip")
          B3.step!(@form, h, "ana", "p1", B3.add_step("Hotel", -50_000, :one_off, "2026-11"))
          B3.step!(@form, h, "ana", "p1", B3.switch_off([gym], "2026-12"))
          %{h: h, gym: gym}
        end

        test "REQ-148 AC-1: a member proposes their own plan as a shared plan; not another member's",
             %{
               h: h
             } do
          assert {:error, :not_found, :not_found, _} =
                   Planning.share_plan(scope(@form, h, "ben"), "p1", [id(@form, h, "cy")])

          {:ok, _} = Planning.share_plan(scope(@form, h, "ana"), "p1", [id(@form, h, "ben")])
          assert [sp] = B3.shared_plans(@form, h, "ana")
          item = view(@form, h, "ana").items[sp]
          assert %{kind: :plan, label: "Trip", steps: [_, _]} = item.attrs
          assert B3.owners_of(@form, h, "ana", sp) == [id(@form, h, "ana")]
          # it is a snapshot: a new item, beside the private plan
          assert Planning.plan(scope(@form, h, "ana"), "p1").name == "Trip"
        end

        test "REQ-148 AC-2: a named member becomes an owner only with their own consent", %{h: h} do
          {:ok, _} = Planning.share_plan(scope(@form, h, "ana"), "p1", [id(@form, h, "ben")])
          [sp] = B3.shared_plans(@form, h, "ana")
          assert B3.owners_of(@form, h, "ana", sp) == [id(@form, h, "ana")]
          assert [%{id: pid, item_id: ^sp}] = Items.pending(scope(@form, h, "ben"))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), pid)
          assert B3.owners_of(@form, h, "ana", sp) == B3.ids(@form, h, ~w(ana ben))
        end

        test "REQ-148 AC-3: with several named, each becomes an owner only once all have agreed",
             %{
               h: h
             } do
          named = [id(@form, h, "ben"), id(@form, h, "cy")]
          {:ok, _} = Planning.share_plan(scope(@form, h, "ana"), "p1", named)
          [sp] = B3.shared_plans(@form, h, "ana")
          [%{id: pid}] = Items.pending(scope(@form, h, "ben"))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), pid)
          assert B3.owners_of(@form, h, "ana", sp) == [id(@form, h, "ana")]
          assert [%{id: ^pid}] = Items.pending(scope(@form, h, "cy"))
          {:ok, _} = Items.consent(scope(@form, h, "cy"), pid)
          assert B3.owners_of(@form, h, "ana", sp) == B3.ids(@form, h, ~w(ana ben cy))
        end

        test "REQ-148 AC-4: with several owners, a named member joins only with every current owner's consent",
             %{h: h} do
          {:ok, _} = Planning.share_plan(scope(@form, h, "ana"), "p1", [id(@form, h, "ben")])
          [sp] = B3.shared_plans(@form, h, "ana")
          [%{id: pid}] = Items.pending(scope(@form, h, "ben"))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), pid)

          {:ok, _} = B3.owners(@form, h, "ana", sp, ~w(ana ben cy))
          [%{id: pid2}] = Items.pending(scope(@form, h, "ben"))
          # Ben, a current owner, hasn't agreed: Cy doesn't see it and can't agree yet
          assert Items.pending(scope(@form, h, "cy")) == []

          assert {:error, :not_found, :not_found, _} =
                   Items.consent(scope(@form, h, "cy"), pid2)

          {:ok, _} = Items.consent(scope(@form, h, "ben"), pid2)
          assert B3.owners_of(@form, h, "ana", sp) == B3.ids(@form, h, ~w(ana ben))
          {:ok, _} = Items.consent(scope(@form, h, "cy"), pid2)
          assert B3.owners_of(@form, h, "ana", sp) == B3.ids(@form, h, ~w(ana ben cy))
        end

        test "REQ-148 AC-5: until they agree, a named member sees the proposal and the plan's steps",
             %{
               h: h
             } do
          {:ok, _} = Planning.share_plan(scope(@form, h, "ana"), "p1", [id(@form, h, "ben")])
          [sp] = B3.shared_plans(@form, h, "ana")
          steps = view(@form, h, "ana").items[sp].attrs.steps

          ben = scope(@form, h, "ben")

          assert [%{item_id: ^sp, attrs: %{kind: :plan, label: "Trip", steps: ^steps}}] =
                   Items.pending(ben)

          assert Items.lookup(ben, sp).attrs.steps == steps
          # the plan's key is sealed to Ben as well; Cy, not named, holds none and reads nothing
          keys = stored(@form, h).items[sp].keys
          assert Map.has_key?(keys, id(@form, h, "ben"))
          refute Map.has_key?(keys, id(@form, h, "cy"))
          assert Items.pending(scope(@form, h, "cy")) == []
          refute reads?(@form, h, "cy", sp)
        end

        test "REQ-148 AC-6: a shared plan's steps never change", %{h: h, gym: gym} do
          {:ok, _} = Planning.share_plan(scope(@form, h, "ana"), "p1", [id(@form, h, "ben")])
          [sp] = B3.shared_plans(@form, h, "ana")
          steps = view(@form, h, "ana").items[sp].attrs.steps
          assert length(steps) == 2
          same = fn name -> assert view(@form, h, name).items[sp].attrs.steps == steps end

          [%{id: pid}] = Items.pending(scope(@form, h, "ben"))
          {:ok, _} = Items.consent(scope(@form, h, "ben"), pid)
          same.("ana")

          # changing, or deleting, the plan it was made from
          B3.step!(@form, h, "ana", "p1", B3.borrow(100_000, 500, 10_000, "2026-12"))
          {:ok, _} = Planning.remove_step(scope(@form, h, "ana"), "p1", 1)
          same.("ana")
          {:ok, _} = Planning.delete_plan(scope(@form, h, "ana"), "p1")
          same.("ana")

          # deleting an item a step names
          {:ok, _} = Items.delete(scope(@form, h, "ana"), gym)
          same.("ana")

          # no member can add or remove a step of it
          for name <- ~w(ana ben) do
            assert {:error, _, _, _} =
                     Planning.add_step(
                       scope(@form, h, name),
                       sp,
                       B3.add_step("X", -1, :one_off, "2026-12")
                     )

            assert {:error, _, _, _} = Planning.remove_step(scope(@form, h, name), sp, 1)
          end

          # an owner leaving it
          {:ok, _} = Items.relinquish(scope(@form, h, "ana"), sp)
          same.("ben")
        end
      end

      describe "REQ-149" do
        alias FindependenceShared.{Balances, CashFlow, Households, Items, Planning, Portability}
        alias FindependenceShared.Contract.B3

        test "REQ-149 AC-1: a member can add an account of type 401(k) and of type IRA" do
          h = household(@form, ~w(ana ben))

          for type <- [:retirement_401k, :ira] do
            id = B3.account(@form, h, "ana", "Ana's plan", type)
            item = Items.lookup(scope(@form, h, "ana"), id)
            assert item.attrs == %{kind: :account, label: "Ana's plan", account_type: type}
            assert Balances.retirement?(item)
            assert id in Balances.retirement_account_ids(scope(@form, h, "ana"))
          end
        end

        test "REQ-149 AC-2: a new 401(k) or IRA is owned by its creator alone; no one else can see it" do
          h = household(@form, ~w(ana ben cy))

          for type <- [:retirement_401k, :ira] do
            id = B3.account(@form, h, "ana", "Ana's plan", type)
            ana = id(@form, h, "ana")
            assert {:ok, item} = Items.get(scope(@form, h, "ana"), id)
            assert B3.sorted(item.owners) == [ana] and B3.sorted(item.grantees) == []

            for other <- ~w(ben cy) do
              refute Items.visible?(scope(@form, h, other), id)
              refute reads?(@form, h, other, id)
            end

            # its key is sealed to the creator only
            assert Map.keys(stored(@form, h).items[id].keys) == [ana]
          end
        end

        test "REQ-149 AC-3: its name and kind never change" do
          h = household(@form, ~w(ana ben cy))

          for type <- [:retirement_401k, :ira] do
            id = B3.account(@form, h, "ana", "Ana's plan", type)
            attrs = view(@form, h, "ana").items[id].attrs

            assert {:error, :conflict, :item_exists, _} =
                     Balances.add_account(scope(@form, h, "ana"), id, "Renamed", :checking)

            B3.read!(@form, h, "ana", id, "2026-09-01", 100)
            B3.grant(@form, h, "ana", id, "cy")
            {:ok, _} = B3.owners(@form, h, "ana", id, ~w(ana ben))
            {:ok, _} = Items.revoke_grant(scope(@form, h, "ben"), id, id(@form, h, "cy"))
            {:ok, _} = Items.relinquish(scope(@form, h, "ana"), id)
            assert view(@form, h, "ben").items[id].attrs == attrs
          end
        end

        test "REQ-149 AC-4: any owner adds a reading without consent; append-only, validated, in the history" do
          h = household(@form, ~w(ana ben))
          id = B3.account(@form, h, "ana", "Joint", :ira)
          {:ok, _} = B3.owners(@form, h, "ana", id, ~w(ana ben))
          assert B3.owners_of(@form, h, "ana", id) == B3.ids(@form, h, ~w(ana ben))

          B3.read!(@form, h, "ana", id, "2026-08-31", 4_000_000)
          B3.read!(@form, h, "ben", id, "2026-09-30", 4_100_000)
          assert Items.pending(scope(@form, h, "ana")) == []
          assert Items.pending(scope(@form, h, "ben")) == []
          {ana, ben} = {id(@form, h, "ana"), id(@form, h, "ben")}

          assert {:ok,
                  [
                    %{seq: 1, by: ^ana, on: "2026-08-31", balance: 4_000_000},
                    %{seq: 2, by: ^ben, on: "2026-09-30", balance: 4_100_000}
                  ] = two} = Balances.readings(scope(@form, h, "ben"), id)

          # a later reading adds to the list; the earlier ones are kept unchanged, as stored too
          stored_two = Enum.map(stored(@form, h).items[id].readings, & &1.box)
          B3.read!(@form, h, "ana", id, "2026-10-31", 1)
          {:ok, three} = Balances.readings(scope(@form, h, "ana"), id)
          assert Enum.take(three, 2) == two and length(three) == 3

          assert Enum.take(Enum.map(stored(@form, h).items[id].readings, & &1.box), 2) ==
                   stored_two

          {:ok, ledger} = Items.ledger(scope(@form, h, "ana"), id)

          assert [%{by: [^ana]}, %{by: [^ben]}, %{by: [^ana]}] =
                   Enum.filter(ledger, &(&1.event == :reading_added))

          # validated like any account's
          assert {:error, :validation, :invalid_reading, _} =
                   Balances.add_reading(
                     scope(@form, h, "ana"),
                     id,
                     B3.reading("2026-02-30", 1)
                   )

          assert {:error, :validation, {:on, _}} =
                   Balances.add_reading(scope(@form, h, "ana"), id, %{
                     balance: {:ok, 1, false},
                     on: :error
                   })

          assert {:ok, [_, _, _]} = Balances.readings(scope(@form, h, "ana"), id)
        end

        test "REQ-149 AC-5: a member it is shared with can't add a reading; one who can't see it is told it isn't there" do
          h = household(@form, ~w(ana ben cy))

          for type <- [:retirement_401k, :ira] do
            id = B3.account(@form, h, "ana", "Ana's plan", type)
            B3.read!(@form, h, "ana", id, "2026-09-01", 100)
            B3.grant(@form, h, "ana", id, "ben")
            r = B3.reading("2026-09-30", 200)

            assert {:error, :unauthorized, :not_owner, _} =
                     Balances.add_reading(scope(@form, h, "ben"), id, r)

            assert {:error, :not_found, :not_found, _} =
                     Balances.add_reading(scope(@form, h, "cy"), id, r)

            assert {:ok, [%{balance: 100}]} = Balances.readings(scope(@form, h, "ana"), id)
            assert length(stored(@form, h).items[id].readings) == 1
          end
        end

        test "REQ-149 AC-6: owners read every reading; a grantee only the latest; nobody else any" do
          h = household(@form, ~w(ana ben cy))
          id = B3.account(@form, h, "ana", "Ana's plan", :ira)
          B3.read!(@form, h, "ana", id, "2026-08-31", 4_000_000)
          B3.read!(@form, h, "ana", id, "2026-09-30", 4_100_000)
          B3.grant(@form, h, "ana", id, "ben")

          assert {:ok, [%{balance: 4_000_000}, %{balance: 4_100_000}]} =
                   Balances.readings(scope(@form, h, "ana"), id)

          ben = scope(@form, h, "ben")
          assert Balances.latest(ben, id).balance == 4_100_000
          assert B3.readable(Balances.readings(ben, id)) == [4_100_000]

          cy = scope(@form, h, "cy")
          assert Balances.readings(cy, id) == {:error, :not_found}
          assert Balances.latest(cy, id) == nil

          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), id, id(@form, h, "ben"))
          ben = scope(@form, h, "ben")
          assert Balances.readings(ben, id) == {:error, :not_found}
          assert Balances.latest(ben, id) == nil

          assert B3.readable(Balances.readings(scope(@form, h, "ana"), id)) == [
                   4_000_000,
                   4_100_000
                 ]
        end

        test "REQ-149 AC-7: each reading has its own key, sealed only to those AC-6 allows" do
          h = household(@form, ~w(ana ben cy))
          {ana, ben} = {id(@form, h, "ana"), id(@form, h, "ben")}
          id = B3.account(@form, h, "ana", "Ana's IRA", :ira)
          B3.read!(@form, h, "ana", id, "2026-10-01", 1)
          B3.read!(@form, h, "ana", id, "2026-11-01", 2)
          B3.grant(@form, h, "ana", id, "ben")

          [r1, r2] = stored(@form, h).items[id].readings
          refute r1.keys[ana] == r2.keys[ana]
          assert Map.keys(r1.keys) == [ana]
          assert Enum.sort(Map.keys(r2.keys)) == Enum.sort([ana, ben])

          # stopping sharing removes Ben's key, and a later reading is never sealed to him
          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), id, ben)
          B3.read!(@form, h, "ana", id, "2026-12-01", 3)
          readings = stored(@form, h).items[id].readings
          assert length(readings) == 3
          assert Enum.all?(readings, &(Map.keys(&1.keys) == [ana]))
          assert Balances.latest(scope(@form, h, "ana"), id).balance == 3
          assert Balances.latest(scope(@form, h, "ben"), id) == nil
        end

        test "REQ-149 AC-8: the item rules apply: export, leaving, joint deletion, withdrawing, deletion" do
          h = household(@form, ~w(ana ben))
          id = B3.account(@form, h, "ana", "Ana's plan", :retirement_401k)
          B3.read!(@form, h, "ana", id, "2026-09-30", 100)
          B3.grant(@form, h, "ana", id, "ben")

          # the owner's export carries it with its readings; the grantee's doesn't
          assert [%{id: ^id, readings: [%{balance: 100}]}] =
                   Portability.export(scope(@form, h, "ana")).items

          assert Portability.export(scope(@form, h, "ben")).items == []

          # an owner can't leave while owning it
          assert {:error, _, :still_owner, _} = Households.leave(scope(@form, h, "ana"))

          # joint: neither owner can delete it alone; a pending proposal can be withdrawn
          j = B3.account(@form, h, "ana", "Joint IRA", :ira)
          {:ok, _} = B3.owners(@form, h, "ana", j, ~w(ana ben))

          assert {:error, :unauthorized, :not_sole_owner, _} =
                   Items.delete(scope(@form, h, "ana"), j)

          {:ok, _} = B3.owners(@form, h, "ben", j, ~w(ben))
          assert [%{id: pid, item_id: ^j}] = Items.pending(scope(@form, h, "ana"))
          {:ok, _} = Items.withdraw(scope(@form, h, "ana"), pid)
          assert Items.pending(scope(@form, h, "ana")) == []
          assert Items.pending(scope(@form, h, "ben")) == []

          # the sole owner deletes it, and its readings go with it, from storage too
          {:ok, _} = Items.delete(scope(@form, h, "ana"), id)
          refute Map.has_key?(stored(@form, h).items, id)
          refute Items.visible?(scope(@form, h, "ben"), id)
          assert Balances.readings(scope(@form, h, "ana"), id) == {:error, :not_found}
        end

        test "REQ-149 AC-9: a retirement account's balance is never counted as cash" do
          h = household(@form, ~w(ana ben))
          chk = B3.account(@form, h, "ana", "Checking", :checking)
          B3.read!(@form, h, "ana", chk, "2026-11-01", 100_000)
          sav = B3.account(@form, h, "ana", "Savings", :savings)
          B3.read!(@form, h, "ana", sav, "2026-11-01", 600_000)
          k = B3.account(@form, h, "ana", "401(k)", :retirement_401k)
          B3.read!(@form, h, "ana", k, "2026-11-01", 1_000_000)
          ira = B3.account(@form, h, "ana", "IRA", :ira)
          B3.read!(@form, h, "ana", ira, "2026-11-01", 5_000_000)
          add_item(@form, h, "ana", "Rent", amount: -150_000)

          ana = scope(@form, h, "ana")
          assert CashFlow.cash_flow(ana, B3.today(), 1).start.balance == 100_000
          p = CashFlow.project(ana, B3.today())
          assert p.start.cash == 700_000
          assert Enum.sort(p.start.accounts) == Enum.sort([chk, sav])
          assert Planning.cover(ana).savings == 600_000
          assert Planning.cover(ana).accounts == [sav]
        end
      end

      describe "REQ-150" do
        alias FindependenceShared.{Balances, Households, Items, Planning}
        alias FindependenceShared.Contract.B3

        @b3_nothing %{
          birth_year: nil,
          retire_age: nil,
          return_bp: nil,
          ss_monthly: nil,
          target_monthly: nil,
          contributions: %{}
        }

        test "REQ-150 AC-1: a member can save every retirement assumption" do
          h = household(@form, ~w(ana ben))
          k = B3.account(@form, h, "ana", "401(k)", :retirement_401k)

          B3.save_retirement!(
            @form,
            h,
            "ana",
            [
              birth_year: 1961,
              retire_age: 67,
              return_bp: 1200,
              ss_monthly: 200_000,
              target_monthly: 300_000
            ],
            [{k, 10_000}]
          )

          assert B3.settings(@form, h, "ana") == %{
                   birth_year: 1961,
                   retire_age: 67,
                   return_bp: 1200,
                   ss_monthly: 200_000,
                   target_monthly: 300_000,
                   contributions: %{k => 10_000}
                 }
        end

        test "REQ-150 AC-2: the assumptions are private; each member's are their own" do
          h = household(@form, ~w(ana ben))
          k = B3.account(@form, h, "ana", "401(k)", :retirement_401k)
          B3.grant(@form, h, "ana", k, "ben")
          B3.save_retirement!(@form, h, "ana", [birth_year: 1961, retire_age: 67], [{k, 10_000}])
          assert B3.settings(@form, h, "ben") == @b3_nothing

          B3.save_retirement!(@form, h, "ben", retire_age: 60, return_bp: 300)
          assert B3.settings(@form, h, "ben").retire_age == 60
          assert B3.settings(@form, h, "ana").retire_age == 67
          assert B3.settings(@form, h, "ana").contributions == %{k => 10_000}
          assert B3.settings(@form, h, "ben").contributions == %{}

          # Ben's session holds no one else's record; each is sealed on its own
          refute Map.has_key?(view(@form, h, "ben").goals, id(@form, h, "ana"))
          personal = stored(@form, h).personal
          assert Map.has_key?(personal, id(@form, h, "ana"))
          assert Map.has_key?(personal, id(@form, h, "ben"))
          refute personal[id(@form, h, "ana")] == personal[id(@form, h, "ben")]
        end

        test "REQ-150 AC-3: a contribution only for a retirement account the member can see; it stops counting after" do
          h = household(@form, ~w(ana ben))
          chk = B3.account(@form, h, "ben", "Checking", :checking)
          bk = B3.account(@form, h, "ben", "Ben's 401(k)", :retirement_401k)
          ira = B3.account(@form, h, "ana", "Ana's IRA", :ira)
          hidden = B3.account(@form, h, "ana", "Ana's 401(k)", :retirement_401k)

          B3.save_retirement!(@form, h, "ben", [birth_year: 1961, retire_age: 67, return_bp: 0], [
            {bk, 10_000}
          ])

          for not_his <- [chk, hidden] do
            assert {:error, :not_found, :not_found, _} =
                     Planning.save_retirement(
                       scope(@form, h, "ben"),
                       B3.retirement([birth_year: 1961, retire_age: 67, return_bp: 0], [
                         {not_his, 5_000}
                       ])
                     )
          end

          assert Balances.retirement_account_ids(scope(@form, h, "ben")) == [bk]

          # once shared, Ben can contribute to Ana's IRA; it stops counting once it isn't
          B3.grant(@form, h, "ana", ira, "ben")

          B3.save_retirement!(@form, h, "ben", [birth_year: 1961, retire_age: 67, return_bp: 0], [
            {bk, 10_000},
            {ira, 20_000}
          ])

          assert Planning.retirement_projection(scope(@form, h, "ben"), B3.today()).monthly_contribution ==
                   30_000

          {:ok, _} = Items.revoke_grant(scope(@form, h, "ana"), ira, id(@form, h, "ben"))
          p = Planning.retirement_projection(scope(@form, h, "ben"), B3.today())
          assert p.monthly_contribution == 10_000 and p.start.accounts == [bk]
        end

        test "REQ-150 AC-4: the return is accepted from -5% to 15% and refused outside" do
          h = household(@form, ~w(ana))

          for ok <- [-500, 0, 1_500] do
            B3.save_retirement!(@form, h, "ana", return_bp: ok)
            assert B3.settings(@form, h, "ana").return_bp == ok
          end

          for bad <- [-501, 1_501] do
            assert {:error, :validation, [{:return_bp, _}]} =
                     Planning.save_retirement(
                       scope(@form, h, "ana"),
                       B3.retirement(return_bp: bad)
                     )

            assert B3.settings(@form, h, "ana").return_bp == 1_500
          end
        end

        test "REQ-150 AC-5: each assumption is optional" do
          h = household(@form, ~w(ana))
          k = B3.account(@form, h, "ana", "401(k)", :retirement_401k)
          B3.save_retirement!(@form, h, "ana", [])
          assert B3.settings(@form, h, "ana") == @b3_nothing

          all = [
            birth_year: 1961,
            retire_age: 67,
            return_bp: 400,
            ss_monthly: 1,
            target_monthly: 2
          ]

          for {f, v} <- all do
            B3.save_retirement!(@form, h, "ana", [{f, v}])
            assert B3.settings(@form, h, "ana") == Map.put(@b3_nothing, f, v)
          end

          B3.save_retirement!(@form, h, "ana", [], [{k, 5_000}])
          assert B3.settings(@form, h, "ana") == %{@b3_nothing | contributions: %{k => 5_000}}
        end

        test "REQ-150 AC-6: each assumption can be cleared" do
          h = household(@form, ~w(ana))
          k = B3.account(@form, h, "ana", "401(k)", :retirement_401k)

          B3.save_retirement!(
            @form,
            h,
            "ana",
            [
              birth_year: 1961,
              retire_age: 67,
              return_bp: 400,
              ss_monthly: 200_000,
              target_monthly: 300_000
            ],
            [{k, 10_000}]
          )

          assert B3.settings(@form, h, "ana").ss_monthly == 200_000
          B3.save_retirement!(@form, h, "ana", [], [{k, nil}])
          assert B3.settings(@form, h, "ana") == @b3_nothing
        end

        test "REQ-150 AC-7: an invalid value in any field is refused at that field, and nothing is saved" do
          h = household(@form, ~w(ana))
          k = B3.account(@form, h, "ana", "401(k)", :retirement_401k)

          good = [
            birth_year: 1961,
            retire_age: 67,
            return_bp: 400,
            ss_monthly: 100,
            target_monthly: 200
          ]

          B3.save_retirement!(@form, h, "ana", good, [{k, 10_000}])
          before = B3.settings(@form, h, "ana")

          changed = [
            birth_year: 1970,
            retire_age: 60,
            return_bp: 500,
            ss_monthly: 1,
            target_monthly: 2
          ]

          for {field, bad} <- [
                birth_year: 1800,
                birth_year: 2101,
                retire_age: 39,
                retire_age: 91,
                return_bp: 1_501,
                ss_monthly: {:error, "Enter the estimate."},
                target_monthly: {:error, "Enter the target."}
              ] do
            assert {:error, :validation, [{^field, message}]} =
                     Planning.save_retirement(
                       scope(@form, h, "ana"),
                       B3.retirement(Keyword.put(changed, field, bad), [{k, 20_000}])
                     )

            assert is_binary(message)
            assert B3.settings(@form, h, "ana") == before
          end

          # a contribution the transport couldn't read, named by its account
          assert {:error, :validation, [{{:contribution, ^k}, _}]} =
                   Planning.save_retirement(
                     scope(@form, h, "ana"),
                     B3.retirement(changed, [{k, {:error, "Enter the amount."}}])
                   )

          # amounts out of range are refused by the core's rules, and nothing is saved
          for {field, bad} <- [ss_monthly: -1, target_monthly: 100_000_001] do
            assert {:error, :validation, :invalid_retirement, _} =
                     Planning.save_retirement(
                       scope(@form, h, "ana"),
                       B3.retirement(Keyword.put(changed, field, bad), [{k, 20_000}])
                     )
          end

          assert {:error, :validation, :invalid_retirement, _} =
                   Planning.save_retirement(
                     scope(@form, h, "ana"),
                     B3.retirement(changed, [{k, -5}])
                   )

          assert B3.settings(@form, h, "ana") == before
        end

        # DEF-061 (fixed by WI-076): it failed on both forms before
        test "REQ-150 AC-9: deleting a retirement account removes every member's contribution to it" do
          h = household(@form, ~w(ana ben))
          k = B3.account(@form, h, "ana", "Ana's 401(k)", :retirement_401k)
          B3.grant(@form, h, "ana", k, "ben")
          B3.save_retirement!(@form, h, "ana", [retire_age: 67], [{k, 10_000}])
          B3.save_retirement!(@form, h, "ben", [retire_age: 60], [{k, 20_000}])
          {:ok, _} = Items.delete(scope(@form, h, "ana"), k)

          assert B3.settings(@form, h, "ana").contributions == %{}
          assert B3.settings(@form, h, "ana").retire_age == 67
          assert B3.settings(@form, h, "ben").retire_age == 60
          assert B3.settings(@form, h, "ben").contributions == %{}
        end

        test "REQ-150 AC-9: a member who leaves has their assumptions removed" do
          h = household(@form, ~w(ana ben))
          ben = id(@form, h, "ben")
          B3.save_retirement!(@form, h, "ben", retire_age: 65, return_bp: 300)
          assert Map.has_key?(stored(@form, h).personal, ben)

          {:ok, _} = Households.leave(scope(@form, h, "ben"))
          s = stored(@form, h)
          refute Map.has_key?(s.personal, ben)
          refute Map.has_key?(s.members, ben)
          refute Map.has_key?(view(@form, h, "ana").goals, ben)
        end
      end

      describe "REQ-151" do
        alias FindependenceShared.{Balances, Planning}
        alias FindependenceShared.Contract.B3

        test "REQ-151 AC-1: without a birth year, a retirement age, and a return there is no projection" do
          h = household(@form, ~w(ana))
          B3.account(@form, h, "ana", "401(k)", :retirement_401k)

          assert Planning.retirement_projection(scope(@form, h, "ana"), B3.today()) ==
                   {:missing, [:birth_year, :retire_age, :return_bp]}

          B3.save_retirement!(@form, h, "ana", birth_year: 1961)

          assert Planning.retirement_projection(scope(@form, h, "ana"), B3.today()) ==
                   {:missing, [:retire_age, :return_bp]}

          B3.save_retirement!(@form, h, "ana", birth_year: 1961, return_bp: 0)

          assert Planning.retirement_projection(scope(@form, h, "ana"), B3.today()) ==
                   {:missing, [:retire_age]}
        end

        test "REQ-151 AC-2: year by year until January of the retirement year; no rows when that is this year or earlier" do
          h = household(@form, ~w(ana))
          k = B3.retirement_record(@form, h)
          p = Planning.retirement_projection(scope(@form, h, "ana"), B3.today())
          assert p.retire_year == 2028
          assert Enum.map(p.rows, &{&1.year, &1.age}) == [{2026, 65}, {2027, 66}]

          for age <- [65, 64] do
            B3.save_retirement!(
              @form,
              h,
              "ana",
              [birth_year: 1961, retire_age: age, return_bp: 1200],
              [{k, 10_000}]
            )

            p = Planning.retirement_projection(scope(@form, h, "ana"), B3.today())
            assert p.rows == [] and p.at_retirement == 1_000_000
          end
        end

        test "REQ-151 AC-3: it starts from the latest balances of the retirement accounts the member can see, and only those" do
          h = household(@form, ~w(ana ben))
          k = B3.retirement_record(@form, h)
          chk = B3.account(@form, h, "ana", "Checking", :checking)
          B3.read!(@form, h, "ana", chk, "2026-11-01", 999_999)
          ira = B3.account(@form, h, "ben", "Ben's IRA", :ira)
          B3.read!(@form, h, "ben", ira, "2026-10-01", 1)
          B3.read!(@form, h, "ben", ira, "2026-11-01", 5_000_000)

          p = Planning.retirement_projection(scope(@form, h, "ana"), B3.today())
          assert p.start == %{balance: 1_000_000, accounts: [k], read: [k]}

          # once shared, Ana's projection starts from the IRA's latest balance too
          B3.grant(@form, h, "ben", ira, "ana")
          p = Planning.retirement_projection(scope(@form, h, "ana"), B3.today())
          assert p.start.balance == 6_000_000
          assert p.start.accounts == Enum.sort([k, ira]) and p.start.read == Enum.sort([k, ira])

          # an account with no balance yet counts as zero
          new = B3.account(@form, h, "ana", "New 401(k)", :retirement_401k)
          p = Planning.retirement_projection(scope(@form, h, "ana"), B3.today())
          assert p.start.balance == 6_000_000 and new in p.start.accounts
          refute new in p.start.read
          assert Balances.latest(scope(@form, h, "ana"), new) == nil
        end

        test "REQ-151 AC-4: each month it grows at the return and adds that month's contributions" do
          h = household(@form, ~w(ana))
          B3.retirement_record(@form, h)
          p = Planning.retirement_projection(scope(@form, h, "ana"), B3.today())
          assert p.monthly_contribution == 10_000

          # 1% a month: November 10,000.00 + 100.00 + 100.00; December 10,200.00 + 102.00 + 100.00;
          # 2027 computed independently (core's retirement_test.exs)
          assert p.rows == [
                   %{
                     year: 2026,
                     age: 65,
                     contributed: 20_000,
                     growth: 20_200,
                     balance: 1_040_200
                   },
                   %{
                     year: 2027,
                     age: 66,
                     contributed: 120_000,
                     growth: 138_747,
                     balance: 1_298_947
                   }
                 ]

          assert p.at_retirement == 1_298_947
        end
      end

      describe "REQ-153" do
        alias FindependenceShared.Planning
        alias FindependenceShared.Contract.B3

        test "REQ-153 AC-1: the result with the return two points either way and retiring two years either way" do
          h = household(@form, ~w(ana))
          k = B3.retirement_record(@form, h, target_monthly: 300_000, ss_monthly: 200_000)
          [base | others] = Planning.retirement_sensitivity(scope(@form, h, "ana"), B3.today())
          assert base.change == :as_entered and base.at_retirement == 1_298_947

          assert Enum.map(others, & &1.change) == [
                   return: -200,
                   return: 200,
                   retire_age: -2,
                   retire_age: 2
                 ]

          # each is the projection with that one change: saved, worked out, then put back
          for {alt, change} <-
                Enum.zip(others, [
                  [return_bp: 1_000],
                  [return_bp: 1_400],
                  [retire_age: 65],
                  [retire_age: 69]
                ]) do
            p = B3.projection_with(@form, h, k, change)
            assert alt.at_retirement == p.at_retirement, inspect(alt.change)
          end

          [lower, higher, earlier, later] = others
          assert lower.at_retirement < base.at_retirement
          assert higher.at_retirement > base.at_retirement
          assert earlier.at_retirement == 1_000_000
          assert later.at_retirement > base.at_retirement
        end

        test "REQ-153 AC-2: for each alternative, how long the balance would last, with that one change" do
          h = household(@form, ~w(ana))
          k = B3.retirement_record(@form, h, target_monthly: 300_000, ss_monthly: 200_000)
          [base | others] = Planning.retirement_sensitivity(scope(@form, h, "ana"), B3.today())
          assert base.lasts == {:months, 13}

          for {alt, change} <-
                Enum.zip(others, [
                  [return_bp: 1_000],
                  [return_bp: 1_400],
                  [retire_age: 65],
                  [retire_age: 69]
                ]) do
            assert {:months, n} = alt.lasts
            assert n > 0 and alt.lasts == B3.projection_with(@form, h, k, change).lasts
          end

          # no difference to pay, and some remaining at 100, are said for every row
          B3.save_retirement!(
            @form,
            h,
            "ana",
            [
              birth_year: 1961,
              retire_age: 67,
              return_bp: 1200,
              target_monthly: 200_000,
              ss_monthly: 250_000
            ],
            [{k, 10_000}]
          )

          assert Enum.all?(
                   Planning.retirement_sensitivity(scope(@form, h, "ana"), B3.today()),
                   &(&1.lasts == :covered)
                 )

          B3.save_retirement!(
            @form,
            h,
            "ana",
            [birth_year: 1961, retire_age: 67, return_bp: 1200, target_monthly: 1_000],
            [{k, 10_000}]
          )

          assert Enum.all?(
                   Planning.retirement_sensitivity(scope(@form, h, "ana"), B3.today()),
                   &(&1.lasts == :beyond)
                 )
        end

        test "REQ-153 AC-4: nothing about the alternatives is saved" do
          h = household(@form, ~w(ana))
          B3.retirement_record(@form, h, target_monthly: 300_000, ss_monthly: 200_000)
          before = B3.settings(@form, h, "ana")
          stored_before = stored(@form, h)

          assert [_, _, _, _, _] =
                   Planning.retirement_sensitivity(scope(@form, h, "ana"), B3.today())

          assert B3.settings(@form, h, "ana") == before
          assert stored(@form, h) == stored_before
        end
      end

      describe "REQ-155" do
        alias FindependenceShared.{Balances, Items, Planning, Portability, Values}
        alias FindependenceShared.Contract.B3

        test "REQ-155 AC-1: the file names its format and version" do
          h = household(@form, ~w(ana ben))
          B3.ana_record(@form, h)
          data = B3.file(@form, h, "ana")
          assert data["format"] == "findependence-export" and data["version"] == 3
          # and it is a file the check reads back
          assert {:ok, _} = Portability.check(scope(@form, h, "ben"), B3.bytes(data))
        end

        test "REQ-155 AC-2: it carries the member's own plans with their steps" do
          h = household(@form, ~w(ana ben))
          r = B3.ana_record(@form, h)
          data = B3.file(@form, h, "ana")
          assert [%{"name" => "If the job stops", "steps" => [s1, s2, s3]}] = data["plans"]
          assert s1 == %{"kind" => "switch_off", "items" => [r.pay], "from" => "2026-11"}

          assert s2 == %{
                   "kind" => "add",
                   "note" => "Premium",
                   "amount" => -48_000,
                   "frequency" => %{"every" => 1, "unit" => "month"},
                   "from" => "2026-11"
                 }

          assert s3 == %{
                   "kind" => "borrow",
                   "amount" => 600_000,
                   "rate_bp" => 875,
                   "payment" => 25_000,
                   "from" => "2026-12"
                 }
        end

        test "REQ-155 AC-3: it carries the member's marks on items they own" do
          h = household(@form, ~w(ana ben))
          r = B3.ana_record(@form, h)
          assert B3.file(@form, h, "ana")["marks"] == [%{"item" => r.health, "job" => r.pay}]
        end

        test "REQ-155 AC-4: it carries the member's goals: the fund goal and set-aside rates" do
          h = household(@form, ~w(ana ben))
          r = B3.ana_record(@form, h)

          assert B3.file(@form, h, "ana")["goals"] == %{
                   "fund_months" => 3,
                   "set_aside" => [%{"value" => r.home, "rate_bp" => 2500}]
                 }
        end

        test "REQ-155 AC-5: it carries all of the member's retirement assumptions" do
          h = household(@form, ~w(ana ben))
          r = B3.ana_record(@form, h)

          assert B3.file(@form, h, "ana")["retirement"] == %{
                   "birth_year" => 1976,
                   "retire_age" => 67,
                   "return_bp" => 400,
                   "ss_monthly" => 230_000,
                   "target_monthly" => 550_000,
                   "contributions" => [%{"account" => r.k401, "cents" => 40_000}]
                 }
        end

        test "REQ-155 AC-6: a set-aside and a contribution for what the member doesn't own are left out" do
          h = household(@form, ~w(ana ben))
          r = B3.ana_record(@form, h)
          bv = B3.value(@form, h, "ben", "Ben's value")
          B3.grant(@form, h, "ben", bv, "ana")
          {:ok, _} = Planning.set_aside(scope(@form, h, "ana"), bv, 1000)
          ira = B3.account(@form, h, "ben", "Ben's IRA", :ira)
          B3.grant(@form, h, "ben", ira, "ana")

          B3.save_retirement!(
            @form,
            h,
            "ana",
            [
              birth_year: 1976,
              retire_age: 67,
              return_bp: 400,
              ss_monthly: 230_000,
              target_monthly: 550_000
            ],
            [{r.k401, 40_000}, {ira, 5_000}]
          )

          # both are set in Ana's own record
          assert Planning.goals(scope(@form, h, "ana")).set_aside == %{r.home => 2500, bv => 1000}
          assert map_size(B3.settings(@form, h, "ana").contributions) == 2

          data = B3.file(@form, h, "ana")
          assert data["goals"]["set_aside"] == [%{"value" => r.home, "rate_bp" => 2500}]

          assert data["retirement"]["contributions"] == [
                   %{"account" => r.k401, "cents" => 40_000}
                 ]
        end

        test "REQ-155 AC-7: marks, steps, and links naming entries the member doesn't own are left out" do
          h = household(@form, ~w(ana ben))
          r = B3.ana_record(@form, h)
          # Ben's phone, shared with Ana, linked to her value
          {:ok, _} = Values.link(scope(@form, h, "ana"), r.phone, r.home)
          # a second plan step names the health plan; it becomes joint, then Ana relinquishes it
          B3.step!(@form, h, "ana", "p1", B3.switch_off([r.health], "2026-12"))
          {:ok, _} = B3.owners(@form, h, "ana", r.health, ~w(ana ben))
          {:ok, _} = Items.relinquish(scope(@form, h, "ana"), r.health)
          # an item she deleted is still named by a plan step
          gone = add_item(@form, h, "ana", "Gone", amount: -1)
          B3.step!(@form, h, "ana", "p1", B3.switch_off([gone], "2027-01"))
          {:ok, _} = Items.delete(scope(@form, h, "ana"), gone)

          data = B3.file(@form, h, "ana")
          ids = MapSet.new(data["items"], & &1["id"])
          refute r.health in ids or r.phone in ids or gone in ids
          assert data["links"] == [%{"item" => r.rent, "value" => r.home}]
          assert data["marks"] == []
          assert [%{"steps" => steps}] = data["plans"]

          refute Enum.any?(
                   steps,
                   &(&1["kind"] == "switch_off" and &1["from"] in ["2026-12", "2027-01"])
                 )

          for {where, id} <- B3.references(data),
              do: assert(id in ids, "#{where} names #{id}, which isn't in the file")

          assert {:ok, _} = Portability.check(scope(@form, h, "ben"), B3.bytes(data))
        end

        test "REQ-155 AC-8: nothing in it belongs to anyone else" do
          h = household(@form, ~w(ana ben))
          r = B3.ana_record(@form, h)
          # Ben's own private record, some of it naming Ana's items he can see
          B3.grant(@form, h, "ana", r.pay, "ben")
          bv = B3.value(@form, h, "ben", "Ben's value")
          ben = fn -> scope(@form, h, "ben") end
          {:ok, _} = Values.link(ben.(), r.pay, bv)
          {:ok, _} = Values.link(ben.(), r.rent, bv)
          bpay = add_item(@form, h, "ben", "Ben's pay", amount: 1)
          {:ok, _} = Planning.mark(ben.(), r.phone, bpay)
          {:ok, _} = Planning.new_plan(ben.(), "bp", "Ben's plan")
          B3.step!(@form, h, "ben", "bp", B3.switch_off([r.rent], "2026-11"))
          {:ok, _} = Planning.set_fund_goal(ben.(), 9)
          {:ok, _} = Planning.set_aside(ben.(), bv, 700)
          B3.save_retirement!(@form, h, "ben", retire_age: 55)
          bchk = B3.account(@form, h, "ben", "Ben's checking", :checking)
          {:ok, _} = Balances.attach(ben.(), r.rent, bchk)

          ana = scope(@form, h, "ana")
          export = Portability.export(ana)
          data = Portability.to_data(export)
          a = id(@form, h, "ana")

          assert Enum.all?(export.items, &(a in &1.owners))

          assert Enum.sort(Enum.map(export.items, & &1.id)) ==
                   Enum.sort(for i <- Items.visible(ana), a in i.owners, do: i.id)

          assert data["links"] == [%{"item" => r.rent, "value" => r.home}]
          assert data["marks"] == [%{"item" => r.health, "job" => r.pay}]
          assert Enum.map(data["plans"], & &1["name"]) == ["If the job stops"]
          assert data["goals"]["fund_months"] == 3
          assert data["retirement"]["retire_age"] == 67
          assert data["attached"] == [%{"item" => r.pay, "account" => r.chk}]

          text = B3.bytes(data)

          for other <- [
                "Ben's value",
                "Ben's pay",
                "Ben's plan",
                "Ben's checking",
                "Ben's phone",
                ~s("#{bv}"),
                ~s("#{bchk}"),
                ~s("#{bpay}"),
                ~s("#{r.phone}")
              ],
              do: refute(text =~ other, "#{other} is in Ana's file")
        end
      end

      describe "REQ-156" do
        alias FindependenceShared.{Balances, Items, Planning, Portability, Values}
        alias FindependenceShared.Contract.B3

        # Ana's file (with a shared plan she owns), brought in by Kid, who already sees Ben's Wi-Fi.
        setup do
          h = household(@form, ~w(ana ben kid))
          r = B3.ana_record(@form, h)
          {:ok, _} = Planning.share_plan(scope(@form, h, "ana"), "p1", [id(@form, h, "ben")])
          wifi = add_item(@form, h, "ben", "Wi-Fi", amount: -6_000)
          B3.grant(@form, h, "ben", wifi, "kid")
          data = B3.file(@form, h, "ana")
          %{h: h, r: r, data: data, wifi: wifi}
        end

        test "REQ-156 AC-1: a member brings an export into their household by checking it, then confirming",
             %{
               h: h,
               data: data
             } do
          kid = scope(@form, h, "kid")
          assert {:ok, %{summary: summary}} = Portability.check(kid, B3.bytes(data))
          assert Enum.sort(summary.items) == ["Health plan", "Paycheck", "Rent"]
          assert summary.shared_plans == 1
          assert {:ok, _} = B3.bring_in(@form, h, "kid", data)
          assert Map.has_key?(B3.owned(@form, h, "kid"), "Paycheck")
        end

        test "REQ-156 AC-2: every entry in the file becomes a new entry, owned by the member alone",
             %{
               h: h,
               data: data
             } do
          {:ok, _} = B3.bring_in(@form, h, "kid", data)
          kid = id(@form, h, "kid")
          file_ids = MapSet.new(data["items"], & &1["id"])
          mine = for i <- Items.visible(scope(@form, h, "kid")), kid in i.owners, do: i

          names =
            for i <- data["items"],
                i["attrs"]["kind"] != "plan",
                do: i["attrs"]["note"] || i["attrs"]["label"]

          assert Enum.sort(Enum.map(mine, &(&1.attrs[:note] || &1.attrs[:label]))) ==
                   Enum.sort(names)

          for i <- mine do
            refute i.id in file_ids
            assert B3.sorted(i.owners) == [kid] and B3.sorted(i.grantees) == []
            assert Map.keys(stored(@form, h).items[i.id].keys) == [kid]
          end
        end

        test "REQ-156 AC-3: readings come in on the new entries, with the same dates and values",
             %{
               h: h,
               data: data
             } do
          {:ok, _} = B3.bring_in(@form, h, "kid", data)
          new = B3.owned(@form, h, "kid")
          kid = scope(@form, h, "kid")

          assert {:ok,
                  [%{on: "2026-09-01", balance: 50_000}, %{on: "2026-09-26", balance: -2_500}]} =
                   Balances.readings(kid, new["Checking"])

          assert {:ok,
                  [%{on: "2026-09-26", balance: 620_000, rate_bp: 2499, min_payment: 19_000}]} =
                   Balances.readings(kid, new["Visa"])

          assert {:ok, [%{on: "2026-09-26", balance: 4_820_000}]} =
                   Balances.readings(kid, new["401(k)"])
        end

        test "REQ-156 AC-4: links join the corresponding new entries", %{h: h, data: data} do
          {:ok, _} = B3.bring_in(@form, h, "kid", data)
          new = B3.owned(@form, h, "kid")

          assert B3.sorted(Values.links(scope(@form, h, "kid"))) == [
                   {new["Rent"], new["A safe home"]}
                 ]
        end

        test "REQ-156 AC-5: plans, marks, set-asides, contributions, and attachments name the new entries",
             %{
               h: h,
               data: data
             } do
          {:ok, _} = B3.bring_in(@form, h, "kid", data)
          new = B3.owned(@form, h, "kid")
          kid = scope(@form, h, "kid")

          assert [%{name: "If the job stops", steps: [%{step: step} | _]}] =
                   Map.values(Planning.plans(kid))

          assert step == {:switch_off, [new["Paycheck"]], "2026-11"}
          assert B3.sorted(Planning.depends(kid)) == [{new["Health plan"], new["Paycheck"]}]
          assert Planning.goals(kid).set_aside == %{new["A safe home"] => 2500}
          assert Planning.retirement_settings(kid).contributions == %{new["401(k)"] => 40_000}
          assert Balances.attached(kid) == %{new["Paycheck"] => new["Checking"]}
        end

        test "REQ-156 AC-6: goals and assumptions already set are kept; only unset ones are filled",
             %{
               h: h,
               data: data
             } do
          {:ok, _} = Planning.set_fund_goal(scope(@form, h, "kid"), 6)
          B3.save_retirement!(@form, h, "kid", retire_age: 60)
          {:ok, _} = B3.bring_in(@form, h, "kid", data)
          assert Planning.goals(scope(@form, h, "kid")).fund_months == 6
          s = B3.settings(@form, h, "kid")
          assert s.retire_age == 60 and s.birth_year == 1976 and s.return_bp == 400
          assert s.ss_monthly == 230_000 and s.target_monthly == 550_000
        end

        test "REQ-156 AC-7, AC-10: no owners, sharing, or history come in; each history begins with its bringing in",
             %{h: h, data: data} do
          {:ok, _} = B3.bring_in(@form, h, "kid", data)
          kid = id(@form, h, "kid")
          new = B3.owned(@form, h, "kid")
          assert map_size(new) == 7

          for {name, id} <- new do
            {:ok, [first | rest]} = Items.ledger(scope(@form, h, "kid"), id)

            assert first.event == :created and first.by == [kid] and
                     first.details.imported == true

            assert Enum.all?(rest, &(&1.event == :reading_added and &1.by == [kid])), name
          end

          # the joint bill arrives without its owner change or its co-owners
          {:ok, rent} = Items.ledger(scope(@form, h, "kid"), new["Rent"])
          assert Enum.map(rent, & &1.event) == [:created]
          refute inspect(rent) =~ id(@form, h, "ana") or inspect(rent) =~ id(@form, h, "ben")
        end

        test "REQ-156 AC-8: shared plans are not brought in", %{h: h, data: data} do
          assert Enum.any?(data["items"], &(&1["attrs"]["kind"] == "plan"))
          {:ok, _} = B3.bring_in(@form, h, "kid", data)
          kid = scope(@form, h, "kid")
          refute Enum.any?(Items.visible(kid), &Planning.plan?/1)
          assert Items.pending(kid) == []
        end
      end

      describe "REQ-157" do
        alias FindependenceShared.{Items, Planning, Portability}
        alias FindependenceShared.Contract.B3

        test "REQ-157 AC-2: a file that isn't valid JSON is refused" do
          h = household(@form, ~w(ana))

          for bytes <- ["", "not json", "{\"format\": ", <<0xFF, 0xFE>>] do
            assert Portability.check(scope(@form, h, "ana"), bytes) ==
                     {:error, :validation, :not_json}
          end
        end

        test "REQ-157 AC-3: a file of an unknown format or version is refused" do
          h = household(@form, ~w(ana ben))
          B3.ana_record(@form, h)
          d = B3.file(@form, h, "ana")

          assert {"", :not_an_export} in B3.problems(
                   @form,
                   h,
                   "ben",
                   Map.put(d, "format", "other")
                 )

          assert {"", :not_an_export} in B3.problems(@form, h, "ben", [1, 2])

          assert {"version", :unknown_version} in B3.problems(
                   @form,
                   h,
                   "ben",
                   Map.put(d, "version", 4)
                 )
        end

        test "REQ-157 AC-4: every field is checked" do
          h = household(@form, ~w(ana ben))
          B3.ana_record(@form, h)
          d = B3.file(@form, h, "ana")
          pay = B3.index(d, "Paycheck")
          chk = B3.index(d, "Checking")
          visa = B3.index(d, "Visa")
          home = B3.index(d, "A safe home")

          cases = [
            {["items", pay, "attrs", "amount"], 1.5, "items[#{pay}].attrs.amount",
             :invalid_amount},
            {["items", pay, "attrs", "amount"], "100", "items[#{pay}].attrs.amount",
             :invalid_amount},
            {["items", pay, "attrs", "amount"], 100_000_000_001, "items[#{pay}].attrs.amount",
             :invalid_amount},
            {["items", pay, "attrs", "frequency"], "daily", "items[#{pay}].attrs.frequency",
             :invalid_frequency},
            {["items", pay, "attrs", "on"], "2026-02-30", "items[#{pay}].attrs.on",
             :invalid_date},
            {["items", pay, "attrs", "note"], String.duplicate("a", 201),
             "items[#{pay}].attrs.note", :invalid_text},
            {["items", pay, "attrs", "kind"], "admin", "items[#{pay}].attrs.kind", :invalid_kind},
            {["items", chk, "attrs", "account_type"], "crypto",
             "items[#{chk}].attrs.account_type", :invalid_kind},
            {["items", home, "readings"], [%{"on" => "2026-09-01", "balance" => 1}],
             "items[#{home}].readings", :readings_not_allowed},
            {["items", visa, "readings", 0, "rate_bp"], 10_001,
             "items[#{visa}].readings[0].rate_bp", :invalid_rate},
            {["links", 0, "value"], "nope", "links[0].value", :bad_reference},
            {["plans", 0, "steps", 0, "items"], ["nope"], "plans[0].steps[0].items",
             :bad_reference},
            {["plans", 0, "steps", 1, "from"], "2026-13", "plans[0].steps[1].from",
             :invalid_month},
            {["marks", 0, "job"], "nope", "marks[0].job", :bad_reference},
            {["goals", "fund_months"], 61, "goals.fund_months", :invalid_goal},
            {["retirement", "return_bp"], 1_600, "retirement.return_bp", :invalid_retirement},
            {["items", pay, "attrs", "script"], "x", "items[#{pay}].attrs.script", :unknown_field}
          ]

          for {path, value, where, what} <- cases do
            ps = B3.problems(@form, h, "ben", B3.at(d, path, value))
            assert {where, what} in ps, "#{where}: got #{inspect(ps)}"
          end

          assert {"admin", :unknown_field} in B3.problems(
                   @form,
                   h,
                   "ben",
                   Map.put(d, "admin", true)
                 )
        end

        test "REQ-157 AC-5: the checks are the same rules as entering by hand" do
          h = household(@form, ~w(ana ben))
          ana = fn -> scope(@form, h, "ana") end
          longest = String.duplicate("n", 200)
          too_long = longest <> "n"

          # what hand entry accepts at the edges, the member's file brings back
          add_item(@form, h, "ana", longest, amount: -1)
          B3.account(@form, h, "ana", "Account " <> String.duplicate("a", 192), :savings)
          k = B3.account(@form, h, "ana", "401(k)", :retirement_401k)
          {:ok, _} = Planning.set_fund_goal(ana.(), 60)

          B3.save_retirement!(
            @form,
            h,
            "ana",
            [birth_year: 1900, retire_age: 90, return_bp: -500],
            [{k, 1}]
          )

          d = B3.file(@form, h, "ana")
          assert {:ok, _} = Portability.check(scope(@form, h, "ben"), B3.bytes(d))

          # and what hand entry refuses, the file refuses
          assert {:error, :validation, {:note, _}} =
                   Items.add_item(ana.(), %{
                     note: too_long,
                     amount: {:ok, -1},
                     frequency: :monthly,
                     on: ""
                   })

          i = B3.index(d, longest)

          assert {"items[#{i}].attrs.note", :invalid_text} in B3.problems(
                   @form,
                   h,
                   "ben",
                   B3.at(d, ["items", i, "attrs", "note"], too_long)
                 )

          assert {:error, :validation, {:on, _}} =
                   Items.add_item(ana.(), %{
                     note: "x",
                     amount: {:ok, -1},
                     frequency: :monthly,
                     on: "2026-02-30"
                   })

          assert {"items[#{i}].attrs.on", :invalid_date} in B3.problems(
                   @form,
                   h,
                   "ben",
                   B3.at(d, ["items", i, "attrs", "on"], "2026-02-30")
                 )

          assert {:error, :validation, :invalid_goal, _} = Planning.set_fund_goal(ana.(), 61)

          assert {"goals.fund_months", :invalid_goal} in B3.problems(
                   @form,
                   h,
                   "ben",
                   B3.at(d, ["goals", "fund_months"], 61)
                 )

          for {field, bad} <- [return_bp: -501, retire_age: 91, birth_year: 1899] do
            assert {:error, :validation, [{^field, _}]} =
                     Planning.save_retirement(ana.(), B3.retirement([{field, bad}]))

            where = "retirement.#{field}"

            assert {where, :invalid_retirement} in B3.problems(
                     @form,
                     h,
                     "ben",
                     B3.at(d, ["retirement", Atom.to_string(field)], bad)
                   )
          end
        end

        test "REQ-157 AC-6: if any check fails, nothing is brought in, and the problem says what and where" do
          h = household(@form, ~w(ana ben))
          B3.ana_record(@form, h)
          d = B3.file(@form, h, "ana")
          rent = B3.index(d, "Rent")
          before = stored(@form, h)
          ben_items = Items.visible(scope(@form, h, "ben"))

          where = "items[#{rent}].attrs.amount"

          assert {:error, :validation, {:problems, [{^where, :invalid_amount}]}} =
                   Portability.check(
                     scope(@form, h, "ben"),
                     B3.bytes(B3.at(d, ["items", rent, "attrs", "amount"], 1.5))
                   )

          assert Items.visible(scope(@form, h, "ben")) == ben_items
          assert stored(@form, h) == before
        end

        test "REQ-157 AC-7: nothing in the file creates an atom" do
          h = household(@form, ~w(ana ben))
          B3.ana_record(@form, h)
          d = B3.file(@form, h, "ana")
          pay = B3.index(d, "Paycheck")
          key = "zz_b3_not_an_atom_#{System.unique_integer([:positive])}"
          ben = fn -> scope(@form, h, "ben") end
          _ = Portability.check(ben.(), B3.bytes(B3.at(d, ["items", pay, "attrs", key], "x")))

          _ =
            Portability.check(
              ben.(),
              B3.bytes(B3.at(d, ["items", pay, "attrs", "frequency"], key))
            )

          _ = Portability.check(ben.(), B3.bytes(Map.put(d, key, 1)))
          _ = Portability.check(ben.(), B3.bytes(B3.at(d, ["items", pay, "attrs", "kind"], key)))
          assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
        end
      end
    end
  end
end
