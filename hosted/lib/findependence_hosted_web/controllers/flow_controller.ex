defmodule FindependenceHostedWeb.FlowController do
  @moduledoc """
  The next sixty days (REQ-161, REQ-173, REQ-140), the next twelve months (REQ-162), and adding an account or
  a debt (REQ-130, REQ-171), as the local form's routes have them (WI-075). The domain is reached only through
  the shared contexts; no rule is decided here.
  """
  use FindependenceHostedWeb, :controller

  alias FindependenceShared.{Balances, CashFlow, Decode}
  alias FindependenceHostedWeb.DomainWeb

  def next_60_days(conn, _params) do
    scope = DomainWeb.scope(conn)
    today = DomainWeb.today()

    render(conn, :next_60_days,
      page_title: "The next 60 days",
      scope: scope,
      today: today,
      name_of: DomainWeb.name_of(conn),
      flow: CashFlow.cash_flow(scope, today, 60),
      set_asides: CashFlow.set_asides(scope),
      waiting: DomainWeb.waiting(scope)
    )
  end

  def ahead(conn, _params) do
    scope = DomainWeb.scope(conn)

    render(conn, :ahead,
      page_title: "The next 12 months",
      scope: scope,
      name_of: DomainWeb.name_of(conn),
      projection: CashFlow.project(scope, DomainWeb.today()),
      waiting: DomainWeb.waiting(scope)
    )
  end

  def new_balance(conn, _params), do: new_balance_page(conn, %{})

  def add_account(conn, _params),
    do: add_balance(conn, "account", &Balances.add_account/4, Decode.account_types())

  def add_debt(conn, _params),
    do: add_balance(conn, "debt", &Balances.add_debt/4, Decode.debt_types())

  # As the local form's add_balance: a new item id, and on success its page is where the form returns; a
  # refusal shows home with its message, as the local form does (DomainWeb.act/4's default).
  defp add_balance(conn, which, add, types) do
    p = conn.body_params
    id = Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
    conn = %{conn | body_params: Map.merge(p, %{"return" => "/items/" <> id, "item" => id})}

    DomainWeb.act(
      conn,
      "add_" <> which,
      &add.(&1, id, p["label"], Map.get(types, p["type"])),
      invalid: fn conn, {_field, message} ->
        new_balance_page(conn, %{which: which, label: p["label"], type: p["type"], error: message})
      end
    )
  end

  defp new_balance_page(conn, form) do
    render(conn, :new_balance,
      page_title: "Add an account or debt",
      form: form,
      waiting: DomainWeb.waiting(DomainWeb.scope(conn))
    )
  end
end
