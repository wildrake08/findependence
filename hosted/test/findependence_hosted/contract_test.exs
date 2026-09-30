defmodule FindependenceHosted.ContractTest do
  @moduledoc "REQ-188 AC-1 (WI-074): the contract cases on the hosted form, against PostgreSQL."
  use FindependenceHostedWeb.ConnCase, async: false

  @form FindependenceHosted.ContractForm
  import FindependenceShared.Contract.Helpers

  setup do
    FindependenceHosted.Limits.reset()
    :ok
  end

  use FindependenceShared.Contract
end
