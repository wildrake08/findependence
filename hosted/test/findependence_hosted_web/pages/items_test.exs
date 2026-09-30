defmodule FindependenceHostedWeb.Pages.ItemsTest do
  @moduledoc """
  WI-075: the item pages and their actions say what the local form's say (REQ-129 AC-6, REQ-145, REQ-165,
  REQ-166, REQ-172), each criterion as the local form's asserting test checks it (VV-002).
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceHosted.{Accounts, Forms, Repo, Sessions, Tenancy}
  alias FindependenceShared.{Balances, Items, Values, Words}

  @pass "a long passphrase 1"

  # ---------------------------------------------------------------------------
  # helpers

  defp add_item(h, who, note, cents, frequency) do
    {:ok, _} =
      Items.add_item(scope(h, who), %{
        note: note,
        amount: {:ok, cents},
        frequency: frequency,
        on: nil
      })

    id_of(h, who, note)
  end

  defp add_value(h, who, label) do
    {:ok, _} = Values.add_value(scope(h, who), label)
    id_of(h, who, label)
  end

  defp add_balance(h, who, :account, label, type) do
    {:ok, _} = Balances.add_account(scope(h, who), new_id(), label, type)
    id_of(h, who, label)
  end

  defp add_balance(h, who, :debt, label, type) do
    {:ok, _} = Balances.add_debt(scope(h, who), new_id(), label, type)
    id_of(h, who, label)
  end

  defp reading(h, who, id, balance, on, rate \\ nil, min \\ nil) do
    {:ok, _} =
      Balances.add_reading(scope(h, who), id, %{
        balance: {:ok, balance, false},
        on: {:ok, on},
        rate: {:ok, rate},
        min_payment: {:ok, min}
      })
  end

  defp new_id, do: "t" <> Integer.to_string(System.unique_integer([:positive]))

  defp id_of(h, who, title) do
    scope(h, who) |> Items.visible() |> Enum.find(&(Words.title(&1) == title)) |> Map.fetch!(:id)
  end

  defp visible_titles(h, who), do: scope(h, who) |> Items.visible() |> Enum.map(&Words.title/1)

  defp doc(conn), do: LazyHTML.from_document(conn.resp_body)

  defp text(%LazyHTML{} = d),
    do: d |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(conn), do: conn |> doc() |> LazyHTML.query("main") |> text()

  defp forms_to(conn), do: conn |> doc() |> LazyHTML.query("form") |> LazyHTML.attribute("action")

  defp info(conn), do: Phoenix.Flash.get(conn.assigns.flash, :info)

  # everything the household's storage holds (not the audit log), to show a request changed nothing
  defp stored do
    %{rows: tables} =
      Repo.query!(
        "select table_name from information_schema.tables where table_schema = 'public' and table_name not in ('schema_migrations', 'audit_events')"
      )

    for [t] <- Enum.sort(tables), into: %{} do
      {t, Repo.query!(~s(select * from "#{t}")).rows |> Enum.sort()}
    end
  end

  @judgment ~r/\b(good|bad|risky?|healthy|unhealthy|on track|off track|over budget|under budget|warning|danger(ous)?|too much|too little|you can afford|can.t afford)\b/i

  # A member whose email is known here, so they can sign out and sign in again (REQ-165 AC-3, AC-5).
  defp join_as(h, name) do
    email = "#{name}-#{System.unique_integer([:positive])}@example.com"

    {:ok, _, _} =
      Accounts.sign_up(%{
        "email" => email,
        "passphrase" => @pass,
        "passphrase_confirmation" => @pass,
        "disclosure" => "true"
      })

    {:ok, code, _} = Tenancy.create_invitation(session(h["ana"].token))
    conn = sign_in(email)
    token = token_of(conn)

    {:ok, _} =
      Tenancy.join(token, session(token), code, String.capitalize(name), "test")

    %{email: email, conn: recycle(conn), token: token}
  end

  defp sign_in(email) do
    build_conn()
    |> dispatch(@endpoint, :post, "/sign-in", %{
      "account" => %{"email" => email, "passphrase" => @pass}
    })
  end

  defp token_of(conn) do
    conn
    |> recycle()
    |> bypass_through(FindependenceHostedWeb.Router, [:browser])
    |> dispatch(@endpoint, :get, "/", nil)
    |> get_session(:token)
  end

  defp session(token), do: elem(Sessions.fetch(token), 1)

  defp post_as(conn, path, params),
    do: conn |> recycle() |> dispatch(@endpoint, :post, path, params)

  # ---------------------------------------------------------------------------

  test "REQ-129 AC-6: the item's page shows how often it happens beside its amount" do
    h = household(~w(ana ben))
    bus = add_item(h, "ana", "Bus pass", -3250, {:every, 1, :week})
    rent = add_item(h, "ana", "Rent", -215_000, {:every, 1, :month})
    couch = add_item(h, "ana", "Couch", -64_999, :one_off)

    bus_page = text(page(h, "ana", "/items/#{bus}"))
    assert bus_page =~ "−$32.50 a week"
    # 3250 x 52 / 12 = 14083.33
    assert bus_page =~ "Counted as −$140.83 a month in your totals."

    rent_page = text(page(h, "ana", "/items/#{rent}"))
    assert rent_page =~ "−$2,150.00 a month"
    refute rent_page =~ "in your totals"

    couch_page = text(page(h, "ana", "/items/#{couch}"))
    assert couch_page =~ "−$649.99, one-off"
    refute couch_page =~ "in your totals"
  end

  describe "a debt's what-if (REQ-145)" do
    setup do
      h = household(~w(ana ben))
      visa = add_balance(h, "ana", :debt, "Visa", :card)
      reading(h, "ana", visa, 650_000, "2026-08-27", 2499, 25_000)
      reading(h, "ana", visa, 620_000, "2026-09-27", 2499, 19_000)
      car = add_balance(h, "ana", :debt, "Car loan", :loan)
      reading(h, "ana", car, 1_200_000, "2026-09-27", 650, 30_000)
      %{h: h, visa: visa, car: car}
    end

    test "REQ-145 AC-6: the results are stated as facts, with no judgment words", %{
      h: h,
      visa: visa
    } do
      conn = page(h, "ana", "/items/#{visa}?extra=100&rate=10")
      assert conn.status == 200
      section = conn |> doc() |> LazyHTML.query("#what-if") |> text()
      {:ok, _n, int} = Balances.payoff(620_000, 2499, 19_000)

      assert section =~
               "Paying the minimum of $190.00, it would take"

      assert section =~ "with #{Words.plain_amount(int)} of interest."
      assert section =~ "With $100.00 more a month:"
      assert section =~ "At 10%: a month's interest on $6,200.00 would be $51.67."
      assert Regex.scan(@judgment, section) == []

      # a mistake is said at its field, and nothing else changes
      bad = page(h, "ana", "/items/#{visa}?extra=lots&rate=200")
      assert text(bad) =~ "Enter the extra amount like 100 or 100.00."
      assert text(bad) =~ "Enter a rate from 0 to 100."
      assert bad.resp_body =~ ~s(aria-describedby="extra-error")
    end

    test "REQ-145 AC-7: nothing is stored: working out what-ifs leaves storage unchanged", %{
      h: h,
      visa: visa
    } do
      before = stored()

      for q <- ["extra=100&rate=10", "extra=lots", "rate=5", ""],
          who <- ["ana"] do
        assert page(h, who, "/items/#{visa}?#{q}").status == 200
      end

      assert stored() == before
    end

    test "REQ-145 AC-8: no payment order is suggested: neither debt's what-if names the other or an order",
         %{h: h, visa: visa, car: car} do
      for {id, other} <- [{visa, "Car loan"}, {car, "Visa"}] do
        section =
          page(h, "ana", "/items/#{id}?extra=100&rate=10") |> doc() |> LazyHTML.query("#what-if")

        t = text(section)
        assert t =~ "Paying the minimum of"
        refute t =~ other

        assert Regex.scan(
                 ~r/\b(first|before|next|priorit\w*|avalanche|snowball|should|recommend\w*|instead|highest|lowest|focus|target)\b/i,
                 t
               ) == []
      end
    end
  end

  # ---------------------------------------------------------------------------
  # REQ-165: a household-changing form changes the household at most once

  test "REQ-165 AC-1: every form on the item pages, sent again after it finished, changes nothing and says it was already saved" do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -145_000, {:every, 1, :month})
    pay = add_item(h, "ana", "Pay", 400_000, {:every, 1, :month})
    home = add_value(h, "ana", "Home")
    checking = add_balance(h, "ana", :account, "Checking", :checking)
    visa = add_balance(h, "ana", :debt, "Visa", :card)
    ben = id(h, "ben")
    ana = id(h, "ana")
    at = fn id -> "/items/#{id}" end

    firsts = [
      {"ana", "/act/add_value", %{"label" => "Security", "return" => "/"}},
      {"ana", "/act/add_reading",
       %{
         "item" => checking,
         "balance" => "1,000",
         "on" => "2026-09-01",
         "return" => at.(checking)
       }},
      {"ana", "/act/grant", %{"item" => rent, "member" => ben, "return" => at.(rent)}},
      {"ana", "/act/link", %{"item" => rent, "value" => home, "return" => at.(rent)}},
      {"ana", "/act/attach", %{"item" => rent, "account" => checking, "return" => at.(rent)}},
      {"ana", "/act/mark", %{"item" => rent, "job" => pay, "return" => at.(rent)}},
      {"ana", "/act/unmark", %{"item" => rent, "job" => pay, "return" => at.(rent)}},
      {"ana", "/act/unlink", %{"item" => rent, "value" => home, "return" => at.(rent)}},
      {"ana", "/act/attach", %{"item" => rent, "account" => "", "return" => at.(rent)}},
      {"ana", "/act/revoke", %{"item" => rent, "member" => ben, "return" => at.(rent)}},
      {"ana", "/act/owners", %{"item" => home, "owners" => [ana, ben], "return" => at.(home)}}
    ]

    sent = for {who, path, params} <- firsts, do: send_first(h, who, path, params)

    # a waiting request, withdrawn; another, agreed to by ben; then ben stops owning it
    [p1] = Items.pending(scope(h, "ana"))

    sent =
      sent ++
        [
          send_first(h, "ana", "/act/withdraw", %{"proposal" => "#{p1.id}", "return" => at.(home)})
        ]

    sent =
      sent ++
        [
          send_first(h, "ana", "/act/owners", %{
            "item" => home,
            "owners" => [ana, ben],
            "return" => at.(home)
          })
        ]

    [p2] = Items.pending(scope(h, "ben"))

    sent =
      sent ++
        [
          send_first(h, "ben", "/act/consent", %{"proposal" => "#{p2.id}", "return" => at.(home)}),
          send_first(h, "ben", "/act/relinquish", %{"item" => home}),
          send_first(h, "ana", "/act/delete", %{"item" => visa})
        ]

    refute "Visa" in visible_titles(h, "ana")
    before = stored()

    for {who, path, params, where} <- sent do
      again = act(h, who, path, params)
      assert again.status == 302, path
      assert redirected_to(again) == where, path
      assert info(again) == "That was already saved.", path
    end

    assert stored() == before
  end

  defp send_first(h, who, path, params) do
    params = Map.put(params, "_form", form_token())
    first = act(h, who, path, params)
    assert first.status == 302, "#{path}: #{first.status} #{first.resp_body}"
    refute info(first) == "That was already saved."
    {who, path, params, redirected_to(first)}
  end

  test "REQ-165 AC-2: a second sending while the first is being handled changes nothing and says it was already sent" do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -145_000, {:every, 1, :month})
    form = form_token()

    params = %{
      "item" => rent,
      "member" => id(h, "ben"),
      "return" => "/items/#{rent}",
      "_form" => form
    }

    # the first sending of this form is still being handled
    assert Forms.claim(h["ana"].token, id(h, "ana"), form) == :fresh
    before = stored()
    second = act(h, "ana", "/act/grant", params)
    assert redirected_to(second) == "/"
    assert info(second) == "That was already sent. Check below that it was saved."
    assert stored() == before

    # the first finishes (here: changes the household), and a repeat after that is told it was already saved
    Forms.settle(h["ana"].token, id(h, "ana"), form, nil)
    first = act(h, "ana", "/act/grant", params)
    assert redirected_to(first) == "/items/#{rent}"
    assert info(first) == "Ben can now see “Rent”."
    after_first = stored()

    repeat = act(h, "ana", "/act/grant", params)
    assert info(repeat) == "That was already saved."
    assert redirected_to(repeat) == "/items/#{rent}"
    assert stored() == after_first
    assert [_] = scope(h, "ana") |> Items.get(rent) |> elem(1) |> Map.get(:grantees)
  end

  test "REQ-165 AC-3: a saved form sent again after the session ended (sign-out, idle end) changes nothing and says it was already saved" do
    h = household(~w(ana ben))
    cal = join_as(h, "cal")
    form = form_token()
    params = %{"label" => "Security", "return" => "/", "_form" => form}

    first = post_as(cal.conn, "/act/add_value", params)
    assert redirected_to(first) == "/"
    assert info(first) == "Added “Security”."
    saved = stored()

    # after the idle end, the next request is told the form was already saved
    :ets.insert(Sessions, {cal.token, {:idle, session(cal.token).membership.id}})
    idle = post_as(cal.conn, "/act/add_value", params)
    assert redirected_to(idle) == "/sign-in"
    assert info(idle) =~ "That was already saved."
    assert stored() == saved

    # signed out, then signed in again: the same form, sent from the earlier page, is recognised
    again = sign_in(cal.email)
    out = post_as(again, "/sign-out", %{})
    assert redirected_to(out) == "/sign-in"
    assert redirected_to(post_as(again, "/act/add_value", params)) == "/sign-in"
    assert stored() == saved

    later = sign_in(cal.email)
    repeat = post_as(later, "/act/add_value", params)
    assert redirected_to(repeat) == "/"
    assert info(repeat) == "That was already saved."
    assert stored() == saved
  end

  test "REQ-165 AC-4: a form refused for a field or a rule may be sent again, corrected, and is then saved" do
    h = household(~w(ana ben))
    checking = add_balance(h, "ana", :account, "Checking", :checking)
    rent = add_item(h, "ana", "Rent", -145_000, {:every, 1, :month})

    # a mistake in a field: shown at the field, with what was typed kept
    form = form_token()

    bad =
      act(h, "ana", "/act/add_reading", %{
        "item" => checking,
        "balance" => "lots",
        "on" => "2026-09-01",
        "return" => "/items/#{checking}",
        "_form" => form
      })

    assert bad.status == 422
    d = doc(bad)
    assert d |> LazyHTML.query("#balance-error") |> text() =~ "Enter the balance, like 1,240.50"
    assert d |> LazyHTML.query("#balance") |> LazyHTML.attribute("value") == ["lots"]
    assert d |> LazyHTML.query("#balance") |> LazyHTML.attribute("aria-invalid") == ["true"]

    good =
      act(h, "ana", "/act/add_reading", %{
        "item" => checking,
        "balance" => "1,240.50",
        "on" => "2026-09-01",
        "return" => "/items/#{checking}",
        "_form" => form
      })

    assert redirected_to(good) == "/items/#{checking}"
    assert info(good) == "Saved the balance for “Checking”."
    assert Balances.latest(scope(h, "ana"), checking).balance == 124_050

    # a rule: someone who isn't in the household
    form = form_token()

    refused =
      act(h, "ana", "/act/grant", %{
        "item" => rent,
        "member" => "nobody",
        "return" => "/items/#{rent}",
        "_form" => form
      })

    assert refused.status == 422
    assert text(refused) =~ "That person isn't in this household."
    assert text(refused) =~ "Who else can see it"

    ok =
      act(h, "ana", "/act/grant", %{
        "item" => rent,
        "member" => id(h, "ben"),
        "return" => "/items/#{rent}",
        "_form" => form
      })

    assert redirected_to(ok) == "/items/#{rent}"
    assert info(ok) == "Ben can now see “Rent”."
  end

  test "REQ-165 AC-5: a form first sent after the session ended changes nothing, isn't remembered, and is saved in a new session" do
    h = household(~w(ana ben))
    cal = join_as(h, "cal")
    before = stored()

    # after sign-out
    form = form_token()
    params = %{"label" => "Security", "return" => "/", "_form" => form}
    assert redirected_to(post_as(cal.conn, "/sign-out", %{})) == "/sign-in"
    assert redirected_to(post_as(cal.conn, "/act/add_value", params)) == "/sign-in"
    assert stored() == before

    # after the idle end: told it wasn't saved
    s2 = sign_in(cal.email)
    t2 = token_of(s2)
    form2 = form_token()
    params2 = %{"label" => "Time", "return" => "/", "_form" => form2}
    :ets.insert(Sessions, {t2, {:idle, session(t2).membership.id}})
    idle = post_as(s2, "/act/add_value", params2)
    assert redirected_to(idle) == "/sign-in"
    assert info(idle) =~ "Your last action was not saved."
    assert stored() == before

    # sent again in a live session, each is saved, not taken for a repeat
    live = sign_in(cal.email)

    for {p, name} <- [{params, "Security"}, {params2, "Time"}] do
      done = post_as(live, "/act/add_value", p)
      assert redirected_to(done) == "/"
      assert info(done) == "Added “#{name}”."
    end

    cal_scope = Tenancy.scope(session(token_of(live)))

    assert cal_scope |> Items.visible() |> Enum.map(&Words.title/1) |> Enum.sort() == [
             "Security",
             "Time"
           ]
  end

  # ---------------------------------------------------------------------------
  # REQ-166: deleting is shown by name and confirmed first

  defp confirm_and_go_back(h, id, name) do
    item_page = page(h, "ana", "/items/#{id}")
    assert "/confirm/delete" in forms_to(item_page), name
    refute "/act/delete" in forms_to(item_page), name

    before = stored()
    confirm = act(h, "ana", "/confirm/delete", %{"item" => id, "return" => "/items/#{id}"})
    assert confirm.status == 200
    d = doc(confirm)
    assert d |> LazyHTML.query("h1") |> text() == "Delete “#{name}”?"

    assert text(confirm) =~
             "It will be gone for everyone who could see it, with its history. This can't be undone."

    assert forms_to(confirm) -- ["/sign-out"] == ["/act/delete"]
    assert d |> LazyHTML.query("button[type=submit]") |> text() =~ "Yes, delete"

    # showing it deletes nothing, and going back leaves it
    assert stored() == before

    [back] =
      d
      |> LazyHTML.query("main a")
      |> Enum.filter(&(text(&1) =~ "No, go back"))
      |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))

    assert back == "/"
    assert page(h, "ana", back).status == 200
    assert page(h, "ana", "/items/#{id}").status == 200
    assert name in visible_titles(h, "ana")
    assert stored() == before

    # confirming deletes it
    done = act(h, "ana", "/act/delete", %{"item" => id})
    assert redirected_to(done) == "/"
    assert info(done) == "Deleted “#{name}”."
    refute name in visible_titles(h, "ana")
  end

  test "REQ-166 AC-1: deleting an item, an account, or a debt is first shown by name and asked; no page deletes straight away" do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -500, {:every, 1, :month})
    checking = add_balance(h, "ana", :account, "Checking", :checking)
    visa = add_balance(h, "ana", :debt, "Visa", :card)

    for {id, name} <- [{rent, "Rent"}, {checking, "Checking"}, {visa, "Visa"}],
        do: confirm_and_go_back(h, id, name)
  end

  test "REQ-166 AC-2: deleting a value is first shown by name and asked" do
    h = household(~w(ana ben))
    home = add_value(h, "ana", "A safe home")
    confirm_and_go_back(h, home, "A safe home")
  end

  test "REQ-166 AC-4: going back leaves it unchanged, and stopping owning is asked the same way" do
    h = household(~w(ana ben))
    home = add_value(h, "ana", "Home")
    before = stored()
    confirm = act(h, "ana", "/confirm/delete", %{"item" => home, "return" => "/items/#{home}"})
    assert confirm.status == 200
    assert stored() == before
    assert "Home" in visible_titles(h, "ana")
    assert page(h, "ana", "/items/#{home}").status == 200

    # a jointly owned item: stopping owning is asked first, naming who keeps it
    rent = add_item(h, "ana", "Rent", -500, {:every, 1, :month})
    act(h, "ana", "/act/owners", %{"item" => rent, "owners" => [id(h, "ana"), id(h, "ben")]})
    item_page = page(h, "ana", "/items/#{rent}")
    assert "/confirm/relinquish" in forms_to(item_page)
    refute "/act/relinquish" in forms_to(item_page)
    before = stored()
    stop = act(h, "ana", "/confirm/relinquish", %{"item" => rent})
    assert stop.status == 200
    assert text(stop) =~ "Stop owning “Rent”?"
    assert text(stop) =~ "Ben will keep it. To own it again, they would have to agree."
    assert stored() == before
    refute text(stop) =~ id(h, "ben")
  end

  test "REQ-166 AC-6: removing a single link does not ask: the page's form posts straight to it, and one press removes it" do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -500, {:every, 1, :month})
    home = add_value(h, "ana", "Home")
    {:ok, _} = Values.link(scope(h, "ana"), rent, home)

    for id <- [rent, home] do
      item_page = page(h, "ana", "/items/#{id}")
      assert "/act/unlink" in forms_to(item_page)

      refute Enum.any?(
               forms_to(item_page),
               &(&1 =~ "link" and String.starts_with?(&1, "/confirm"))
             )
    end

    removed =
      act(h, "ana", "/act/unlink", %{
        "item" => rent,
        "value" => home,
        "return" => "/items/#{rent}"
      })

    assert redirected_to(removed) == "/items/#{rent}"
    assert info(removed) == "Unlinked “Rent” from “Home”."
    assert Values.links(scope(h, "ana")) |> Enum.to_list() == []
  end

  # ---------------------------------------------------------------------------
  # REQ-172: each account and debt has its own page

  describe "account and debt pages (REQ-172)" do
    setup do
      # cal is in the household but can't see them, so the owner can still share
      h = household(~w(ana ben cal))
      checking = add_balance(h, "ana", :account, "Checking", :checking)
      reading(h, "ana", checking, 100_000, "2026-08-01")
      reading(h, "ana", checking, 124_050, "2026-09-01")
      visa = add_balance(h, "ana", :debt, "Visa", :card)
      reading(h, "ana", visa, 650_000, "2026-08-27", 2499, 25_000)
      reading(h, "ana", visa, 620_000, "2026-09-27", 2499, 19_000)

      for id <- [checking, visa] do
        {:ok, _} = Items.propose_grant(scope(h, "ana"), id, id(h, "ben"))
      end

      %{h: h, checking: checking, visa: visa}
    end

    test "REQ-172 AC-1: an account's page shows its latest reading and the date it is as of", %{
      h: h,
      checking: checking
    } do
      for who <- ["ana", "ben"] do
        latest =
          page(h, who, "/items/#{checking}") |> doc() |> LazyHTML.query("#latest") |> text()

        assert latest =~ "$1,240.50"
        assert latest =~ "As of #{Words.date_text("2026-09-01", today())}."
        refute latest =~ "$1,000.00"
      end

      assert text(page(h, "ana", "/items/#{checking}")) =~ "Checking account"
    end

    test "REQ-172 AC-2: a debt's page shows what's owed, the rate, the minimum, and the date it is as of",
         %{
           h: h,
           visa: visa
         } do
      for who <- ["ana", "ben"] do
        latest = page(h, who, "/items/#{visa}") |> doc() |> LazyHTML.query("#latest") |> text()
        assert latest =~ "$6,200.00 owed"
        assert latest =~ "Interest rate 24.99% · Minimum payment $190.00"
        assert latest =~ "As of #{Words.date_text("2026-09-27", today())}."
      end

      assert text(page(h, "ana", "/items/#{visa}")) =~ "Credit card"
    end

    test "REQ-172 AC-3: owners are offered what owners can do; others see none of it and are told only owners can",
         %{h: h, checking: checking, visa: visa} do
      for id <- [checking, visa] do
        owner = page(h, "ana", "/items/#{id}")
        forms = forms_to(owner)

        for f <- ["/act/add_reading", "/act/grant", "/act/owners", "/confirm/delete"],
            do: assert(f in forms, f)

        assert text(owner) =~ "Update balance"
        assert text(owner) =~ "Give away…"

        shared = page(h, "ben", "/items/#{id}")
        assert shared.status == 200

        for f <- [
              "/act/add_reading",
              "/act/grant",
              "/act/owners",
              "/act/revoke",
              "/confirm/delete",
              "/confirm/relinquish"
            ],
            do: refute(f in forms_to(shared), f)

        assert text(shared) =~
                 "Ana shared this with you. Only owners can change who can see it or view its history."

        refute text(shared) =~ id(h, "ana")
        refute text(owner) =~ id(h, "ben")
        assert text(owner) =~ "Ben can see it"
      end

      # and if someone it's shared with sends an update anyway, they are told only owners can
      refused =
        act(h, "ben", "/act/add_reading", %{
          "item" => checking,
          "balance" => "5",
          "on" => "2026-09-02",
          "return" => "/items/#{checking}"
        })

      assert refused.status == 422
      assert text(refused) =~ "Only an owner can update the balance."
    end

    test "REQ-172 AC-4: owners see earlier readings and history; others see only the latest", %{
      h: h,
      checking: checking,
      visa: visa
    } do
      for id <- [checking, visa] do
        owner = page(h, "ana", "/items/#{id}")
        assert owner |> doc() |> LazyHTML.query("#earlier li") |> Enum.count() == 2
        assert text(owner) =~ "Earlier balances"
        assert text(owner) =~ "History"
        assert text(owner) =~ "Balance updated by Ana"
        assert text(owner) =~ "(you)"

        shared = page(h, "ben", "/items/#{id}")
        refute text(shared) =~ "Earlier balances"
        refute text(shared) =~ "History"
        refute text(shared) =~ "Balance updated by"
      end

      refute text(page(h, "ben", "/items/#{checking}")) =~ "$1,000.00"
      refute text(page(h, "ben", "/items/#{visa}")) =~ "$6,500.00"
    end

    test "REQ-172 AC-5: a debt's page states one month's interest at its rate on its balance, as a fact",
         %{
           h: h,
           visa: visa
         } do
      interest = Balances.monthly_interest(%{balance: 620_000, rate_bp: 2499})

      for who <- ["ana", "ben"] do
        t = page(h, who, "/items/#{visa}") |> doc() |> LazyHTML.query("#latest") |> text()

        assert t =~
                 "At 24.99%, a month's interest on $6,200.00 is #{Words.plain_amount(interest)}."

        assert Regex.scan(@judgment, t) == []
      end
    end
  end
end
