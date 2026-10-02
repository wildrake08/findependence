defmodule FindependenceHostedWeb.Pages.WI079PagesTest do
  @moduledoc """
  WI-079: the security assessment's fixes on the domain pages. FND-08: a member who owns nothing can leave even
  after agreeing to a co-owner's proposal still waiting for someone else (the agreement's row used to block the
  membership's deletion). FND-11: the confirmation for giving up an item names no owners of an item the member
  can't see. FND-12: a refusal with no page to return to shows home, not an error. FND-14 and FND-21: pages are
  not kept by the browser, and device features are refused.
  """
  use FindependenceHostedWeb.DomainCase

  import Ecto.Query
  alias FindependenceHosted.Repo
  alias FindependenceHosted.Schemas.Membership
  alias FindependenceHosted.TestStore

  test "a member who agreed to a waiting proposal, then gave up the item, can leave" do
    h = household(~w(ana ben dee))
    [ana, ben, dee] = Enum.map(~w(ana ben dee), &id(h, &1))

    act(h, "ana", "/act/add_item", %{
      "note" => "Joint car",
      "amount" => "300",
      "direction" => "out",
      "frequency" => "monthly"
    })

    [car] = Map.keys(TestStore.all_items())

    # Ana makes it joint with Ben, then with Dee (each change needs the current owners)
    act(h, "ana", "/act/owners", %{"item" => car, "owners" => [ana, ben]})
    # WI-086: each new owner agrees
    agree(h, "ben", car)
    act(h, "ana", "/act/owners", %{"item" => car, "owners" => [ana, ben, dee]})
    # requests are named by the identifier members see (REQ-199, WI-085)
    hid = elem(FindependenceHosted.Sessions.fetch(h["ana"].token), 1).membership.household_id
    ref = &FindependenceHosted.RequestRefs.ref(hid, &1)
    n = hid |> TestStore.held() |> Map.get(:proposals) |> Map.keys() |> Enum.max()
    act(h, "ben", "/act/consent", %{"proposal" => ref.(n)})
    agree(h, "dee", car)

    # Ben proposes owning it alone; Ana agrees; it waits for Dee; Ana gives the car up
    act(h, "ben", "/act/owners", %{"item" => car, "owners" => [ben]})
    waiting = hid |> TestStore.held() |> Map.get(:proposals) |> Map.keys() |> Enum.max()
    act(h, "ana", "/act/consent", %{"proposal" => ref.(waiting)})
    act(h, "ana", "/act/relinquish", %{"item" => car})

    names_ana? = fn p -> ana in p.consents or p.proposed_by == ana end
    assert Enum.any?(Map.values(TestStore.held(hid).proposals), names_ana?)

    conn = act(h, "ana", "/leave", %{})

    assert redirected_to(conn) == "/sign-in"
    refute Repo.exists?(from m in Membership, where: m.id == ^ana)
    # Ben's proposal still waits for Dee and no longer names Ana
    assert Map.has_key?(TestStore.held(hid).proposals, waiting)
    refute Enum.any?(Map.values(TestStore.held(hid).proposals), names_ana?)
  end

  test "the confirmation for giving up an item doesn't name the owners of an item the member can't see" do
    h = household(~w(ana ben cy))

    act(h, "ana", "/act/add_item", %{
      "note" => "Private",
      "amount" => "5",
      "direction" => "out",
      "frequency" => "monthly"
    })

    [item] = Map.keys(TestStore.all_items())
    act(h, "ana", "/act/owners", %{"item" => item, "owners" => [id(h, "ana"), id(h, "ben")]})

    hidden = act(h, "cy", "/confirm/relinquish", %{"item" => item})
    missing = act(h, "cy", "/confirm/relinquish", %{"item" => "doesnotexist"})

    strip = fn conn ->
      conn |> html_response(200) |> String.replace(~r/(value|content)="[^"]*"/, "")
    end

    refute html_response(hidden, 200) =~ "Ana"
    refute html_response(hidden, 200) =~ "Ben"
    assert strip.(hidden) == strip.(missing)
  end

  test "a refused item action with no page to return to shows home with the refusal, not an error" do
    h = household(~w(ana ben))

    for {action, params} <- [
          {"delete", %{"item" => "nothere"}},
          {"grant", %{"item" => "nothere", "member" => id(h, "ben")}},
          {"relinquish", %{"item" => "nothere"}}
        ] do
      conn = act(h, "ben", "/act/" <> action, params)
      assert html_response(conn, 422) =~ "That isn&#39;t available to you."
    end
  end

  test "signed-in pages, the export, and the sign-up page are not kept by the browser" do
    h = household(~w(ana))

    for path <- ["/", "/household", "/export", "/export.json", "/items/nothere"] do
      conn = page(h, "ana", path)
      assert get_resp_header(conn, "cache-control") == ["no-store"], path
      assert [policy] = get_resp_header(conn, "permissions-policy")
      assert policy =~ "camera=()"
    end

    assert get_resp_header(get(build_conn(), "/sign-up"), "cache-control") == ["no-store"]
  end

  test "fields sent in a shape no form uses are refused with 400 and change nothing" do
    h = household(~w(ana ben))
    before = map_size(TestStore.all_items())

    for {path, params} <- [
          {"/act/add_value", %{"label" => %{"x" => "y"}}},
          {"/act/add_item",
           %{
             "note" => "x",
             "amount" => %{"a" => "1"},
             "direction" => "out",
             "frequency" => "monthly"
           }},
          {"/act/add_item",
           %{"note" => ["x"], "amount" => "1", "direction" => "out", "frequency" => "monthly"}},
          {"/act/delete", %{"item" => ["x"]}},
          {"/act/consent", %{"proposal" => ["1"]}},
          {"/act/owners", %{"item" => "x", "owners" => [%{"a" => "b"}]}}
        ] do
      assert act(h, "ana", path, params).status == 400, path
    end

    assert map_size(TestStore.all_items()) == before

    assert post(build_conn(), "/sign-in", %{"account" => %{"account_number" => %{"x" => "a"}}}).status ==
             400

    assert post(build_conn(), "/join", %{"join" => %{"code" => ["x"]}}).status == 400
  end

  test "a household holds a bounded number of items; past it, adding is refused and nothing is saved" do
    Application.put_env(:findependence_hosted, :max_items, 3)
    on_exit(fn -> Application.delete_env(:findependence_hosted, :max_items) end)
    h = household(~w(ana))

    add = fn note ->
      act(h, "ana", "/act/add_item", %{
        "note" => note,
        "amount" => "5",
        "direction" => "out",
        "frequency" => "monthly"
      })
    end

    for n <- 1..3, do: assert(redirected_to(add.("item #{n}")) == "/")
    assert html_response(add.("one too many"), 422) =~ "one member holds at most 2,000"
    assert map_size(TestStore.all_items()) == 3

    # removing still works when full
    item = TestStore.all_items() |> Map.keys() |> hd()
    act(h, "ana", "/act/delete", %{"item" => item})
    assert map_size(TestStore.all_items()) == 2
  end

  test "remembered form tokens are forgotten after a day, so the tables stay bounded" do
    h = household(~w(ana))
    form = form_token()
    act(h, "ana", "/act/add_value", %{"label" => "A safe home", "_form" => form})
    assert FindependenceHosted.Forms.saved(id(h, "ana"), form)
    assert FindependenceHosted.Forms.size() > 0

    # the hourly sweep, as if a day had passed
    FindependenceHosted.Forms.sweep(System.monotonic_time(:millisecond) + 1)

    assert FindependenceHosted.Forms.size() == 0
    refute FindependenceHosted.Forms.saved(id(h, "ana"), form)
  end
end
