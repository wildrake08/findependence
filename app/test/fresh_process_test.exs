defmodule FindependenceApp.FreshProcessTest do
  @moduledoc """
  WI-016: a vault must be readable and unlockable by a freshly started BEAM, where no app or core
  module has been loaded yet, so no atom they define exists until the Vault module loads.
  """
  use ExUnit.Case, async: true
  import FindependenceApp.TestJoint

  alias FindependenceApp.{Session, Vault}
  alias Findependence.{Alignment, Exit, Household}

  defp act(v, m, fun) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
    end
  end

  test "a fresh process reads and unlocks a vault holding every kind of content" do
    v =
      Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}],
        iterations: 1_000,
        unsafe_test: true
      )

    v = act(v, "ana", &Household.add_item(&1, "ana", "i1", %{note: "rent", amount: -100}))
    v = act(v, "ana", &Household.add_item(&1, "ana", "i2", %{note: "gone", amount: 1}))

    # REQ-127: every frequency must decode in a fresh process
    v =
      for {f, n} <- Enum.with_index(Alignment.frequencies()), reduce: v do
        v ->
          attrs = %{note: "f#{n}", amount: -(n + 1) * 100, unit: :cents, frequency: f}
          act(v, "ana", &Household.add_item(&1, "ana", "f#{n}", attrs))
      end

    # CAP-010: an account and a debt with readings must decode in a fresh process too
    v =
      act(
        v,
        "ana",
        &Findependence.Balances.add_account(&1, "ana", "acct1", "Checking", :checking)
      )

    v =
      act(
        v,
        "ana",
        &Findependence.Balances.add_reading(&1, "ana", "acct1", %{
          on: "2026-09-27",
          balance: 12_345
        })
      )

    v = act(v, "ana", &Findependence.Balances.add_debt(&1, "ana", "debt1", "Card", :heloc))

    v =
      act(
        v,
        "ana",
        &Findependence.Balances.add_reading(&1, "ana", "debt1", %{
          on: "2026-09-27",
          balance: 500,
          rate_bp: 850,
          min_payment: 25
        })
      )

    # v0.3 plans and goals, and v0.4 retirement accounts and assumptions, in the personal record
    v = act(v, "ana", &Findependence.Plans.new_plan(&1, "ana", "p1", "If pay stops"))

    v =
      for step <- [
            {:switch_off, ["i1"], "2026-11"},
            {:add, %{note: "Premium", amount: -60_000, frequency: {:every, 1, :month}},
             "2026-11"},
            {:add, %{note: "Tools", amount: -150_000, frequency: :one_off}, "2026-12"},
            {:borrow, %{amount: 500_000, rate_bp: 900, payment: 20_000}, "2026-12"}
          ],
          reduce: v do
        v -> act(v, "ana", &Findependence.Plans.add_step(&1, "ana", "p1", step))
      end

    v = act(v, "ana", &Findependence.Plans.set_fund_goal(&1, "ana", 3))
    v = act(v, "ana", &Findependence.Balances.add_account(&1, "ana", "ira1", "IRA", :ira))

    v =
      act(
        v,
        "ana",
        &Findependence.Balances.add_reading(&1, "ana", "ira1", %{
          on: "2026-09-27",
          balance: 99_900
        })
      )

    v =
      for {f, x} <- [
            birth_year: 1970,
            retire_age: 67,
            return_bp: -150,
            ss_monthly: 200_000,
            target_monthly: 450_000
          ],
          reduce: v do
        v -> act(v, "ana", &Findependence.Retirement.set(&1, "ana", f, x))
      end

    v = act(v, "ana", &Findependence.Retirement.set_contribution(&1, "ana", "ira1", 50_000))

    # CP-014: which account an item goes through, kept in the personal record
    v = act(v, "ana", &Findependence.Attach.attach(&1, "ana", "i1", "acct1"))

    # v0.5: an entry brought in from a saved file, and the record of that file
    {:ok, bundle} =
      Findependence.Import.check(%{
        "items" => [
          %{"id" => "a", "attrs" => %{"note" => "Brought", "amount" => -500, "unit" => "cents"}}
        ],
        "links" => []
      })

    v =
      act(v, "ana", fn h ->
        Findependence.Import.apply(h, "ana", bundle, fn -> "imp1" end, "fp1", ~D[2026-09-27])
      end)

    v = act(v, "ana", &Alignment.add_value(&1, "ana", "v1", "home"))
    v = act(v, "ana", &Alignment.link(&1, "ana", "i1", "v1"))
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "i1", "ben"))
    v = act(v, "ana", &Household.revoke_grant(&1, "ana", "i1", "ben"))
    v = act(v, "ana", &Exit.delete(&1, "ana", "i2"))
    v = joint_v(v, &act/3, "ana", "i1", ["ana", "cy"])
    v = act(v, "cy", &Household.relinquish(&1, "cy", "i1"))
    v = joint_v(v, &act/3, "ana", "i1", ["ana", "ben"])
    v = act(v, "ana", &Household.propose_owners(&1, "ana", "v1", ["ana", "ben"]))
    v = act(v, "ana", &Household.propose_grant(&1, "ana", "v1", "cy"))
    assert map_size(v.proposals) >= 1

    path = Path.join(System.tmp_dir!(), "fv-fresh-#{System.unique_integer([:positive])}.vault")
    Vault.write!(v, path)
    on_exit(fn -> File.rm(path) end)

    paths =
      Path.wildcard(Path.join(Mix.Project.build_path(), "lib/*/ebin"))
      |> Enum.flat_map(&["-pa", &1])

    script = """
    v = FindependenceApp.Vault.read!(#{inspect(path)})
    for m <- ["ana", "ben"] do
      {:ok, s} = FindependenceApp.Session.open(v, m, "pw-" <> m)
      h = s.household
      IO.puts("\#{m} visible=\#{length(Findependence.View.visible_items(h, m))} pending=\#{length(Findependence.Household.pending(h, m))} links=\#{length(Findependence.Alignment.links(h, m))} deletions=\#{length(Findependence.Ledger.deletions(h, m))} dist=\#{(fn d -> "\#{d.count} \#{d.per_month.in} \#{d.per_month.out} \#{d.one_off.in} \#{d.one_off.out}" end).(Findependence.Alignment.distribution(h, m).unlinked)} bal=\#{(Findependence.Balances.latest(h, m, "acct1") || %{balance: nil}).balance} rate=\#{(Findependence.Balances.latest(h, m, "debt1") || %{rate_bp: nil}).rate_bp} personal=\#{Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary({Findependence.Plans.plans(h, m), Findependence.Plans.goals(h, m)}, [:deterministic])))}")
    end
    """

    {out, status} = System.cmd("elixir", paths ++ ["-e", script], stderr_to_stdout: true)
    assert status == 0, "fresh process failed:\n" <> out
    # the fresh process must see exactly what this (warm) process sees. Totals are printed in a
    # fixed order: `inspect` of a map can order keys differently in another VM (ASM-019).
    dist = fn d ->
      "#{d.count} #{d.per_month.in} #{d.per_month.out} #{d.one_off.in} #{d.one_off.out}"
    end

    expected =
      for m <- ["ana", "ben"], into: "" do
        {:ok, s} = Session.open(v, m, "pw-" <> m)
        h = s.household

        "#{m} visible=#{length(Findependence.View.visible_items(h, m))} pending=#{length(Household.pending(h, m))} links=#{length(Alignment.links(h, m))} deletions=#{length(Findependence.Ledger.deletions(h, m))} dist=#{dist.(Alignment.distribution(h, m).unlinked)} bal=#{(Findependence.Balances.latest(h, m, "acct1") || %{balance: nil}).balance} rate=#{(Findependence.Balances.latest(h, m, "debt1") || %{rate_bp: nil}).rate_bp} personal=#{Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary({Findependence.Plans.plans(h, m), Findependence.Plans.goals(h, m)}, [:deterministic])))}\n"
      end

    # The script names no plan, goal, or retirement field, so it creates none of their atoms: the
    # personal record's plans and goals are compared as hashes and checked by value here.
    assert out == expected, "fresh process saw:\n" <> out
    {:ok, s} = Session.open(v, "ana", "pw-ana")
    assert Findependence.Plans.plans(s.household, "ana")["p1"].steps |> length() == 4
    assert Findependence.Plans.goals(s.household, "ana").fund_months == 3
    assert Findependence.Import.imported_on(s.household, "ana", "fp1") == "2026-09-27"
    assert Findependence.Attach.attached(s.household, "ana")["i1"] == "acct1"
    {:ok, [first]} = Findependence.Ledger.read(s.household, "ana", "imp1")
    assert first.details.imported == true

    assert Findependence.Retirement.settings(s.household, "ana") == %{
             birth_year: 1970,
             retire_age: 67,
             return_bp: -150,
             ss_monthly: 200_000,
             target_monthly: 450_000,
             contributions: %{"ira1" => 50_000}
           }

    assert expected =~ "pending=1"
    # REQ-128 presets in order: one-off -100; weekly -200 -> -867; every 2 weeks -300 -> -650;
    # monthly -400; every 2 months -500 -> -250; every 3 months -600 -> -200; twice a year
    # -700 -> -117; yearly -800 -> -67; irregular -900 a year -> -75. Per month: -2626
    # count, per month in, per month out, one-off in, one-off out
    assert expected =~
             "ana visible=15 pending=1 links=1 deletions=1 dist=10 0 -2626 0 -600 bal=12345 rate=850"
  end
end
