defmodule FindependenceApp.WI059Test do
  @moduledoc """
  WI-059 (DEF-049, REQ-157): anything a member can enter by hand, their own saved file can bring back.
  For each form, boundary names and amounts are entered; whatever the form accepts, the member's export must
  then pass the bring-in check.
  """
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}

  setup do
    path = Path.join(System.tmp_dir!(), "fv-wi059-#{System.unique_integer([:positive])}.vault")

    Vault.create([{"ana", "ana passphrase 1"}], iterations: 1_000, unsafe_test: true)
    |> Vault.write!(path)

    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
    first = request(:get, "/")

    ana =
      request(
        :post,
        "/login",
        %{"member" => "ana", "passphrase" => "ana passphrase 1", "_csrf_token" => csrf(first)},
        first
      )

    chk = new_id(post(ana, "/act/add_account", %{"label" => "Checking", "type" => "checking"}))
    visa = new_id(post(ana, "/act/add_debt", %{"label" => "Visa", "type" => "card"}))
    plan = new_id(post(ana, "/act/new_plan", %{"name" => "Plan"}))
    %{ana: ana, ids: %{chk: chk, visa: visa, plan: plan}}
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp csrf(page),
    do: Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last()

  defp form_id(page), do: Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

  defp post(prev, path, params) do
    page = request(:get, "/", %{}, prev)

    request(
      :post,
      path,
      Map.merge(params, %{"_csrf_token" => csrf(page), "_form" => form_id(page)}),
      page
    )
  end

  defp new_id(resp),
    do: resp |> Plug.Conn.get_resp_header("location") |> hd() |> String.split("/") |> List.last()

  @long String.duplicate("a", 201)
  @max String.duplicate("a", 200)
  @over "1,000,000,000.01"
  @top "1,000,000,000.00"

  # {name, form, fields}; :chk, :visa, and :plan stand for the ids made in setup
  @cases [
    {"item name empty", "/act/add_item",
     %{
       "note" => "  ",
       "amount" => "10",
       "direction" => "out",
       "frequency" => "monthly"
     }},
    {"item name 201", "/act/add_item",
     %{
       "note" => @long,
       "amount" => "10",
       "direction" => "out",
       "frequency" => "monthly"
     }},
    {"item name 200", "/act/add_item",
     %{
       "note" => @max,
       "amount" => "10",
       "direction" => "out",
       "frequency" => "monthly"
     }},
    {"item amount over", "/act/add_item",
     %{
       "note" => "Big",
       "amount" => @over,
       "direction" => "in",
       "frequency" => "one_off"
     }},
    {"item amount top", "/act/add_item",
     %{
       "note" => "Big",
       "amount" => @top,
       "direction" => "in",
       "frequency" => "one_off"
     }},
    {"value label empty", "/act/add_value", %{"label" => " "}},
    {"value label 201", "/act/add_value", %{"label" => @long}},
    {"account name 201", "/act/add_account", %{"label" => @long, "type" => "checking"}},
    {"account name empty", "/act/add_account", %{"label" => " ", "type" => "checking"}},
    {"debt name 201", "/act/add_debt", %{"label" => @long, "type" => "card"}},
    {"account balance over", "/act/add_reading",
     %{"item" => :chk, "balance" => @over, "on" => "2026-09-27"}},
    {"debt balance over", "/act/add_reading",
     %{
       "item" => :visa,
       "balance" => @over,
       "rate" => "9",
       "min_payment" => "10",
       "on" => "2026-09-27"
     }},
    {"debt minimum over", "/act/add_reading",
     %{
       "item" => :visa,
       "balance" => "100",
       "rate" => "9",
       "min_payment" => @over,
       "on" => "2026-09-27"
     }},
    {"plan name 201", "/act/new_plan", %{"name" => @long}},
    {"plan name empty", "/act/new_plan", %{"name" => " "}},
    {"planned item name 201", "/act/plan_step",
     %{
       "plan" => :plan,
       "kind" => "add",
       "note" => @long,
       "amount" => "600",
       "direction" => "out",
       "frequency" => "monthly",
       "from" => "2026-11"
     }},
    {"planned item amount over", "/act/plan_step",
     %{
       "plan" => :plan,
       "kind" => "add",
       "note" => "Big",
       "amount" => @over,
       "direction" => "out",
       "frequency" => "monthly",
       "from" => "2026-11"
     }},
    {"borrowing over", "/act/plan_step",
     %{
       "plan" => :plan,
       "kind" => "borrow",
       "amount" => @over,
       "rate" => "9",
       "payment" => "200",
       "from" => "2026-12"
     }},
    {"borrowing payment over", "/act/plan_step",
     %{
       "plan" => :plan,
       "kind" => "borrow",
       "amount" => "5,000",
       "rate" => "9",
       "payment" => @over,
       "from" => "2026-12"
     }}
  ]

  for {name, action, fields} <- @cases do
    @action action
    @fields fields
    test "what hand entry accepts, the member's file brings back: #{name}", %{ana: ana, ids: ids} do
      params = Map.new(@fields, fn {k, v} -> {k, if(is_atom(v), do: ids[v], else: v)} end)
      resp = post(ana, @action, params)
      json = request(:get, "/export.json", %{}, resp).resp_body

      assert {:ok, _} = Findependence.Import.check(:json.decode(json)),
             "#{@action} accepted it (#{resp.status}), but the export is refused"
    end
  end
end
