defmodule Mix.Tasks.Findependence.Demo do
  @shortdoc "Create the alpha's made-up demo family (ROADMAP-ALPHA)"
  @moduledoc """
    mix findependence.demo PATH

  Creates a household vault at PATH holding the roadmap family (ROADMAP-ALPHA §1): Dad, Mom, and
  three kids (Alex 20 and Blake 18 in college, Casey 16 in high school), with Grandma's support for
  college recorded both ways (REV-038). Every figure is made up. The passphrases are printed,
  because this household is for testing only; never use them anywhere else.
  """
  use Mix.Task

  alias FindependenceApp.{Session, Vault}
  alias Findependence.{Alignment, Household}

  @members [
    {"Dad", "dad demo passphrase"},
    {"Mom", "mom demo passphrase"},
    {"Alex", "alex demo passphrase"},
    {"Blake", "blake demo passphrase"},
    {"Casey", "casey demo passphrase"}
  ]

  @week {:every, 1, :week}
  @two_weeks {:every, 2, :week}
  @month {:every, 1, :month}
  @twice_a_year {:every, 6, :month}

  @doc "The demo's members and passphrases."
  def members, do: @members

  @impl true
  def run([path]) do
    if File.exists?(path), do: Mix.raise("#{path} already exists")
    Mix.shell().info(FindependenceApp.Web.release_notice())
    Mix.shell().info("Creating the demo family. Every figure is made up.")
    build(path)

    Mix.shell().info("""

    Created #{path}. Members and their demo passphrases:
    #{Enum.map_join(@members, "\n", fn {m, p} -> "  #{m}: #{p}" end)}

    Start it with:  ERL_CRASH_DUMP_SECONDS=0 mix findependence.serve #{path} 4848
    """)
  end

  def run(_), do: Mix.raise("usage: mix findependence.demo PATH")

  @doc "Builds the demo household at `path`. `opts` go to `Vault.create/2` (tests pass fewer iterations)."
  def build(path, opts \\ []) do
    vault = Vault.create(@members, opts)

    sessions =
      Map.new(@members, fn {m, p} ->
        {:ok, s} = Session.open(vault, m, p)
        {m, s}
      end)

    st = %{vault: vault, sessions: sessions}

    # Dad and Mom pay the household's bills together.
    st =
      Enum.reduce(
        [
          {"mortgage", "Mortgage", -224_000, @month},
          {"groceries", "Groceries", -21_000, @week},
          {"utilities", "Utilities", -26_000, @month},
          {"phone", "Family phone plan", -15_000, @month},
          {"internet", "Internet", -8_000, @month},
          {"car_ins", "Car insurance", -114_000, @twice_a_year},
          {"card_min", "Credit card payments", -18_000, @month},
          {"heloc", "HELOC payment", -32_000, @month},
          {"repairs", "Home repairs", -240_000, :irregular},
          {"allowance_out", "Casey's allowance", -10_000, @month}
        ],
        st,
        fn {id, note, amount, f}, st ->
          st
          |> add("Dad", id, note, amount, f)
          |> act("Dad", &Household.propose_owners(&1, "Dad", id, ["Dad", "Mom"]))
        end
      )

    # The kids can see the phone plan.
    st =
      Enum.reduce(["Alex", "Blake", "Casey"], st, fn kid, st ->
        {st, pid} = act_p(st, "Dad", &Household.propose_grant(&1, "Dad", "phone", kid))
        act(st, "Mom", &Household.consent(&1, "Mom", pid))
      end)

    # Each parent's own paycheck and private spending.
    st =
      st
      |> add("Dad", "dad_pay", "Dad's paycheck", 265_000, @two_weeks)
      |> add("Dad", "dad_gym", "Gym", -4_500, @month)
      |> add("Mom", "mom_pay", "Mom's paycheck", 198_000, @two_weeks)
      |> add("Mom", "mom_lunch", "Work lunches", -6_000, @month)

    # The college kids own their tuition and Grandma's support for it (REV-038).
    st =
      Enum.reduce(
        [{"Alex", 680_000, 48_000}, {"Blake", 590_000, 30_000}],
        st,
        fn {kid, tuition, wages}, st ->
          k = String.downcase(kid)

          st
          |> add(kid, "#{k}_tuition", "Tuition", -tuition, @twice_a_year)
          |> add(kid, "#{k}_grandma", "Grandma pays tuition", tuition, @twice_a_year)
          |> add(kid, "#{k}_books", "Books", -30_000, @twice_a_year)
          |> add(kid, "#{k}_wages", "Campus job", wages, @two_weeks)
          |> value(kid, "#{k}_college", "Finishing college")
          |> link(kid, "#{k}_tuition", "#{k}_college")
          |> link(kid, "#{k}_grandma", "#{k}_college")
          |> link(kid, "#{k}_books", "#{k}_college")
          |> act(kid, &Household.propose_grant(&1, kid, "#{k}_tuition", "Mom"))
          |> act(kid, &Household.propose_grant(&1, kid, "#{k}_grandma", "Mom"))
        end
      )

    # Casey, 16: a full member with the same privacy as everyone (REV-038).
    st =
      st
      |> add("Casey", "casey_allowance", "Allowance", 10_000, @month)
      |> add("Casey", "casey_summer", "Summer job", 120_000, :irregular)
      |> value("Casey", "casey_car", "Saving for a car")
      |> link("Casey", "casey_summer", "casey_car")

    # The parents' values; one of Dad's is waiting for Mom to agree to own it with him.
    st =
      st
      |> value("Dad", "secure_home", "A secure home")
      |> link("Dad", "mortgage", "secure_home")
      |> link("Dad", "utilities", "secure_home")
      |> value("Mom", "retire", "Retiring without worry")
      |> value("Dad", "own_boss", "Being my own boss")

    {st, _pid} =
      act_p(st, "Dad", &Household.propose_owners(&1, "Dad", "own_boss", ["Dad", "Mom"]))

    Vault.write!(st.vault, path)
    :ok
  end

  defp add(st, m, id, note, cents, frequency),
    do:
      act(
        st,
        m,
        &Household.add_item(&1, m, id, %{
          note: note,
          amount: cents,
          unit: :cents,
          frequency: frequency
        })
      )

  defp value(st, m, id, label), do: act(st, m, &Alignment.add_value(&1, m, id, label))
  defp link(st, m, item, value), do: act(st, m, &Alignment.link(&1, m, item, value))

  # Runs one core operation as `m` on the latest vault and saves it.
  defp act(st, m, fun) do
    {st, _} = act_p(st, m, fun)
    st
  end

  defp act_p(st, m, fun) do
    s = Session.refresh(st.sessions[m], st.vault)

    {h, pid} =
      case fun.(s.household) do
        {:ok, h} -> {h, nil}
        {:ok, h, pid} -> {h, pid}
        {:error, reason} -> raise "demo step failed for #{m}: #{inspect(reason)}"
      end

    saved = Session.save(%{s | household: h})
    {%{st | vault: saved.vault, sessions: Map.put(st.sessions, m, saved)}, pid}
  end
end
