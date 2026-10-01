defmodule FindependenceHosted.ContractForm do
  @moduledoc """
  The hosted form for the contract cases (REQ-188 AC-1, WI-074): accounts signed up and signed in, a household
  started by the first member and joined by the others with invitation codes, in the test's database sandbox.
  """
  @behaviour FindependenceShared.Contract.Form

  alias FindependenceHosted.{Accounts, Domain, Repo, Sessions, Tenancy}
  alias FindependenceShared.Scope

  @pass "a long passphrase 1"

  @impl true
  def household([first | rest]) do
    a = new_member(first)
    {:ok, _} = Tenancy.create_household(a, session(a), first)

    others =
      for n <- rest do
        {:ok, code, _} = Tenancy.create_invitation(session(a))
        t = new_member(n)
        {:ok, _} = Tenancy.join(t, session(t), code, n, "test")
        {n, t}
      end

    Map.new([{first, a} | others])
  end

  @impl true
  def scope(token), do: token |> session() |> Domain.view() |> Scope.new()

  @impl true
  def member(token), do: session(token).membership.id

  @impl true
  # the stored state with its requests keyed as members see them (REQ-199), so ids from a view compare
  def stored(token) do
    hid = session(token).membership.household_id
    state = Domain.load(hid)

    %{
      state
      | proposals:
          Map.new(state.proposals, fn {n, p} ->
            {FindependenceHosted.RequestRefs.ref(hid, n), p}
          end)
    }
  end

  # Every value in every table: the household's rows and everything else the database holds.
  @impl true
  def stored_bytes(_token) do
    %{rows: tables} =
      Repo.query!(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'"
      )

    for [t] <- tables,
        row <- Repo.query!(~s(SELECT * FROM "#{t}")).rows,
        v <- row,
        v != nil,
        do: if(is_binary(v), do: v, else: to_string(v))
  end

  @impl true
  def fixed_membership?, do: false

  defp new_member(_name) do
    {:ok, _, number, _} =
      Accounts.sign_up(%{
        "passphrase" => @pass,
        "passphrase_confirmation" => @pass,
        "disclosure" => "true"
      })

    {:ok, token} = Accounts.sign_in(number, @pass, "test")
    token
  end

  defp session(token), do: elem(Sessions.fetch(token), 1)
end
