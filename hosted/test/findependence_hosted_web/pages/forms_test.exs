defmodule FindependenceHostedWeb.Pages.FormsTest do
  @moduledoc """
  WI-075 (REV-100 H5; REQ-165, the local form's DEF-035): forms from an out-of-date page, with CSRF checking on
  (the page tests skip it): the page says nothing was saved, unless this member already saved that form, or it
  was a Leave that was done; and REQ-124 AC-2 for the hosted form: no page loads anything from elsewhere.
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceHosted.Forms
  alias FindependenceShared.Items

  # a conn for the member with CSRF checking on, and no token in the form
  defp checked(h, name) do
    conn = conn_of(h, name)
    %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}
  end

  defp items(h, name), do: map_size(scope(h, name).household.items)

  describe "an out-of-date form (REQ-165 AC-3, AC-5; DEF-035)" do
    test "that wasn't saved is refused with a page saying so, and changes nothing" do
      h = household(~w(ana))
      before = items(h, "ana")

      conn =
        post(checked(h, "ana"), "/act/add_item", %{
          "_form" => form_token(),
          "note" => "Rent",
          "amount" => "1,450",
          "direction" => "out",
          "frequency" => "monthly"
        })

      assert html_response(conn, 403) =~ ~r"That wasn(&#39;|')t saved"
      assert html_response(conn, 403) =~ "This page was out of date, so nothing was saved."
      assert items(h, "ana") == before
    end

    test "that this member already saved goes where it went and says so, changing nothing" do
      h = household(~w(ana))
      form = form_token()

      params = %{
        "_form" => form,
        "note" => "Rent",
        "amount" => "1,450",
        "direction" => "out",
        "frequency" => "monthly"
      }

      first = act(h, "ana", "/act/add_item", params)
      assert redirected_to(first) == "/"
      after_first = items(h, "ana")

      # the same form again from a page the new session's CSRF token doesn't match
      again = post(checked(h, "ana"), "/act/add_item", params)
      assert redirected_to(again) == "/"
      assert Phoenix.Flash.get(again.assigns.flash, :info) == "That was already saved."
      assert items(h, "ana") == after_first
    end

    test "a second click on Leave after the first was done says it was already done" do
      h = household(~w(ana))
      form = form_token()
      assert redirected_to(act(h, "ana", "/leave", %{"_form" => form})) == "/sign-in"
      assert Forms.left?(form)

      # a browser signed out by the Leave, CSRF checking on (marked recycled, so the test adapter keeps it)
      again =
        post(%{build_conn() | private: %{phoenix_recycled: true}}, "/leave", %{"_form" => form})

      assert redirected_to(again) == "/sign-in"

      assert Phoenix.Flash.get(again.assigns.flash, :info) ==
               "You have left the household. That was already done."
    end
  end

  describe "every household-changing form on a page carries its one-time token" do
    test "the leave page's form, as the page gives it, leaves the household" do
      h = household(~w(ana))
      html = html_response(page(h, "ana", "/leave"), 200)
      [_, form] = Regex.run(~r/action="\/leave"[^>]*>.*?name="_form"[^>]*value="([^"]+)"/s, html)
      conn = post(conn_of(h, "ana"), "/leave", %{"_form" => form})
      assert redirected_to(conn) == "/sign-in"
    end

    test "every form that posts to /act/ or /leave on the domain pages has a token" do
      h = household(~w(ana ben))
      {:ok, _} = FindependenceShared.Values.add_value(scope(h, "ana"), "Security")

      {:ok, saved} =
        Items.add_item(scope(h, "ana"), %{
          note: "Rent",
          amount: {:ok, -1000},
          frequency: {:every, 1, :month},
          on: ""
        })

      item =
        Enum.find_value(saved.household.items, fn {id, i} ->
          if i.attrs[:note] == "Rent", do: id
        end)

      for path <- ["/", "/items/#{item}", "/balances/new", "/leave", "/next-60-days", "/ahead"] do
        html = html_response(page(h, "ana", path), 200)

        for [form] <- Regex.scan(~r/<form[^>]*action="\/(?:act\/[^"]*|leave)".*?<\/form>/s, html),
            do:
              assert(
                form =~ ~s(name="_form"),
                "#{path}: a form without its token: #{String.slice(form, 0, 120)}"
              )
      end
    end
  end

  describe "where a form returns (as the local form's router)" do
    test "a form from the leave checklist, the plans, goals, or retirement pages goes back there" do
      h = household(~w(ana ben))
      {:ok, v} = FindependenceShared.Values.add_value(scope(h, "ana"), "Security")

      value =
        Enum.find_value(v.household.items, fn {id, i} ->
          if i.attrs[:label] == "Security", do: id
        end)

      # a value's joiner must agree, so the proposal stays open until Ana withdraws it
      {:ok, saved} = Items.propose_owners(scope(h, "ana"), value, [id(h, "ana"), id(h, "ben")])
      [proposal] = Map.keys(saved.household.proposals)

      conn =
        act(h, "ana", "/act/withdraw", %{"proposal" => to_string(proposal), "return" => "/leave"})

      assert redirected_to(conn) == "/leave"

      for path <- ["/plans", "/goals", "/retirement"],
          do: assert(FindependenceHostedWeb.DomainWeb.return_to(path, scope(h, "ana")) == path)

      assert FindependenceHostedWeb.DomainWeb.return_to("/plans/nope", scope(h, "ana")) ==
               "/plans"

      assert FindependenceHostedWeb.DomainWeb.return_to("/elsewhere", scope(h, "ana")) == "/"
    end
  end

  describe "REQ-124 AC-2: nothing is loaded from elsewhere" do
    test "no page names another site for a script, style, image, font, or frame, and the policy forbids it" do
      h = household(~w(ana ben))
      s = scope(h, "ana")
      {:ok, saved} = FindependenceShared.Values.add_value(s, "Security")
      value = Enum.find_value(saved.household.items, fn {id, i} -> if i.attrs[:label], do: id end)
      acct = Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

      {:ok, _} =
        FindependenceShared.Balances.add_account(scope(h, "ana"), acct, "Checking", :checking)

      {:ok, with_item} =
        Items.add_item(scope(h, "ana"), %{
          note: "Rent",
          amount: {:ok, -1000},
          frequency: {:every, 1, :month},
          on: ""
        })

      item =
        Enum.find_value(with_item.household.items, fn {id, i} ->
          if i.attrs[:note] == "Rent", do: id
        end)

      pages =
        [
          "/",
          "/household",
          "/items/#{item}",
          "/items/#{value}",
          "/items/#{acct}",
          "/next-60-days",
          "/ahead"
        ] ++
          ["/balances/new", "/leave", "/passphrase", "/items/no-such-item"]

      for path <- pages do
        conn = page(h, "ana", path)
        body = conn.resp_body

        refute body =~ ~r/(src|href|action|srcset|poster|data)\s*=\s*"(https?:)?\/\//i,
               "#{path} names another site"

        [csp] = Plug.Conn.get_resp_header(conn, "content-security-policy")
        assert csp =~ "default-src 'none'"
        refute csp =~ ~r/https?:/
      end

      for path <- ["/sign-in", "/sign-up", "/recover"] do
        body = get(build_conn(), path).resp_body
        refute body =~ ~r/(src|href|action)\s*=\s*"(https?:)?\/\//i, "#{path} names another site"
      end
    end
  end
end
