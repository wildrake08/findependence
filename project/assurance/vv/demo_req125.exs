# VV-001 demonstration for REQ-125. From core/: mix run ../project/assurance/vv/demo_req125.exs
# REQ-125 demonstration: a proposer who is removed from ownership while their proposal is pending.
alias Findependence.Household
h = Household.new([:a, :b, :c])
{:ok, h} = Household.add_item(h, :a, :acct)
{:ok, h, _} = Household.propose_owners(h, :a, :acct, [:a, :b])
# with REQ-107 a joint change needs every owner; :a proposes a grant to :c (pending: :b hasn't agreed)
{:ok, h, grant_pid} = Household.propose_grant(h, :a, :acct, :c)
# :b proposes that :b alone owns it; :a agrees, so :a stops owning it
{:ok, h, own_pid} = Household.propose_owners(h, :b, :acct, [:b])
{:ok, h} = Household.consent(h, :a, own_pid)
still_pending = Map.has_key?(h.proposals, grant_pid)
IO.inspect(%{owners_now: MapSet.to_list(h.items[:acct].owners), a_grant_proposal_still_pending: still_pending,
  a_withdraws_own_proposal: (if still_pending, do: Household.withdraw(h, :a, grant_pid) |> elem(0), else: :n_a)})
