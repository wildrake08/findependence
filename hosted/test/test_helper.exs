ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(FindependenceHosted.Repo, :manual)

# WI-074 (REQ-188 AC-1): the contract cases shared with the local-first form, from shared/test/support/contract
contract = Path.expand("../../shared/test/support/contract", __DIR__)
Enum.each(~w(form.ex helpers.ex cases.ex), &Code.require_file(&1, contract))

for f <- Path.wildcard(Path.join(contract, "*_cases.ex")) |> Enum.sort(),
    do: Code.require_file(f)
