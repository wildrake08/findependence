defmodule FindependenceHostedWeb.Pages.PortabilityTest do
  @moduledoc """
  WI-076: the export page and file, bringing in a saved record, and the leave checklist say and do what the
  local form's do (REQ-129 AC-6, REQ-156 AC-9, REQ-157 AC-1, REQ-158, REQ-166 AC-5, REQ-191 AC-1), each
  criterion as the local form's asserting test checks it (VV-002: app/test/v05_web_test.exs,
  vv_f05_b_test.exs, vv_f05_d_test.exs).
  """
  use FindependenceHostedWeb.DomainCase

  alias FindependenceHosted.Repo
  alias FindependenceShared.{Balances, Items, Messages, Values, Words}

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

  defp add_account(h, who, label) do
    {:ok, _} = Balances.add_account(scope(h, who), new_id(), label, :checking)
    id = id_of(h, who, label)

    {:ok, _} =
      Balances.add_reading(scope(h, who), id, %{
        balance: {:ok, 124_000, false},
        on: {:ok, "2026-09-27"},
        rate: {:ok, nil},
        min_payment: {:ok, nil}
      })

    id
  end

  defp new_id, do: "t" <> Integer.to_string(System.unique_integer([:positive]))

  defp id_of(h, who, title) do
    scope(h, who) |> Items.visible() |> Enum.find(&(Words.title(&1) == title)) |> Map.fetch!(:id)
  end

  defp titles(h, who), do: scope(h, who) |> Items.visible() |> Enum.map(&Words.title/1)

  defp doc(conn), do: LazyHTML.from_document(conn.resp_body)

  defp text(%LazyHTML{} = d),
    do: d |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(conn), do: conn |> doc() |> LazyHTML.query("main") |> text()

  defp info(conn), do: Phoenix.Flash.get(conn.assigns.flash, :info)

  # everything the household's storage holds (not the audit log), to show a request stored nothing
  defp stored do
    %{rows: tables} =
      Repo.query!(
        "select table_name from information_schema.tables where table_schema = 'public' and table_name not in ('schema_migrations', 'audit_events')"
      )

    for [t] <- Enum.sort(tables), into: %{} do
      {t, Repo.query!(~s(select * from "#{t}")).rows |> Enum.sort()}
    end
  end

  defp audits do
    Repo.query!(
      "select operation, outcome, account_id::text, household_id::text, resource_id from audit_events order by at, id"
    ).rows
  end

  # Ana owns Rent (shared with Ben), a value it is linked to, and a checking account with a balance.
  defp with_records do
    h = household(~w(ana ben))
    rent = add_item(h, "ana", "Rent", -145_000, {:every, 1, :month})
    home = add_value(h, "ana", "A safe home")
    {:ok, _} = Values.link(scope(h, "ana"), rent, home)
    {:ok, _} = Items.propose_grant(scope(h, "ana"), rent, id(h, "ben"))
    add_account(h, "ana", "Checking")
    h
  end

  defp saved_file(h, who \\ "ana"), do: response(page(h, who, "/export.json"), 200)

  defp upload(h, who, bytes, name \\ "findependence-export.json") do
    path = Path.join(System.tmp_dir!(), "fv-#{System.unique_integer([:positive])}.json")
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)

    act(h, who, "/act/bring-in", %{
      "file" => %Plug.Upload{path: path, filename: name, content_type: "application/json"}
    })
  end

  # a request body as a browser sends the bring-in form, through the endpoint's own parsers
  defp multipart(h, who, file_bytes) do
    boundary = "fvtest#{System.unique_integer([:positive])}"

    body =
      "--#{boundary}\r\ncontent-disposition: form-data; name=\"_form\"\r\n\r\n#{form_token()}\r\n" <>
        "--#{boundary}\r\ncontent-disposition: form-data; name=\"file\"; filename=\"big.json\"\r\ncontent-type: application/json\r\n\r\n" <>
        file_bytes <> "\r\n--#{boundary}--\r\n"

    conn_of(h, who)
    |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
    |> Phoenix.ConnTest.dispatch(FindependenceHostedWeb.Endpoint, :post, "/act/bring-in", body)
  end

  # ---------------------------------------------------------------------------
  # The export

  describe "the export" do
    test "REQ-129 AC-6: the export page shows how often beside each amount" do
      h = household(~w(ana))

      for {note, freq, shown} <- [
            {"Weekly", {:every, 1, :week}, "−$10.00 a week"},
            {"Monthly", {:every, 1, :month}, "−$10.00 a month"},
            {"Yearly", {:every, 1, :year}, "−$10.00 a year"},
            {"Irregular", :irregular, "−$10.00 a year, irregular"}
          ] do
        add_item(h, "ana", note, -1000, freq)
        assert text(page(h, "ana", "/export")) =~ "#{note}, #{shown}. Owned by you."
      end

      page = html_response(page(h, "ana", "/export"), 200)
      assert page =~ "<b>Monthly</b>, −$10.00 a month."
    end

    test "the page lists what would be taken, with history, links, and balances; members by display name" do
      h = with_records()
      conn = page(h, "ana", "/export")
      html = html_response(conn, 200)
      d = doc(conn)
      t = text(conn)

      assert d |> LazyHTML.query("h1") |> Enum.count() == 1
      assert d |> LazyHTML.query("h1") |> text() == "What you'd take with you"

      assert d |> LazyHTML.query("h2.pc-card__title") |> Enum.map(&text/1) ==
               ["Items", "What matters to you", "Balances and debts", "Your links"]

      assert t =~
               "Everything you own, with its history, and your own links between them. Nothing that belongs to anyone else."

      assert t =~ "Rent, −$1,450.00 a month. Owned by you. Ben can see it too."
      assert t =~ "Created by Ana"
      assert t =~ "Shared with Ben (agreed by Ana)"

      assert t =~
               "Checking (Checking account). $1,240.00 as of Sunday, September 27. 1 balance recorded."

      assert t =~ "Rent → A safe home"
      assert html =~ ~s(href="/export.json")
      assert html =~ ~s(download="findependence-export.json")
      refute html =~ id(h, "ana")
      refute html =~ id(h, "ben")
    end

    test "the saved file names members by display name, never by id, and has each item's history" do
      h = with_records()
      conn = page(h, "ana", "/export.json")
      body = response(conn, 200)
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="findependence-export.json")
             ]

      data = :json.decode(body)
      assert data["member"] == "Ana"
      rent = Enum.find(data["items"], &(&1["attrs"]["note"] == "Rent"))
      assert rent["owners"] == ["Ana"]
      assert rent["grantees"] == ["Ben"]
      assert rent["history"] == ["Created by Ana", "Shared with Ben (agreed by Ana)"]
      checking = Enum.find(data["items"], &(&1["attrs"]["label"] == "Checking"))
      assert [%{"by" => "Ana", "balance" => 124_000}] = checking["readings"]
      refute body =~ id(h, "ana")
      refute body =~ id(h, "ben")
    end
  end

  # ---------------------------------------------------------------------------
  # Bringing in

  describe "bringing in" do
    test "REQ-156 AC-9: the member is told that owners, sharing, history, and shared plans aren't brought in, and that only they own what came in" do
      h = with_records()
      data = :json.decode(saved_file(h))
      # a shared plan, as a file from a household where Ana had one
      data =
        Map.update!(data, "items", &(&1 ++ [%{"id" => "sp1", "attrs" => %{"kind" => "plan"}}]))

      before = titles(h, "ben")

      preview = upload(h, "ben", IO.iodata_to_binary(:json.encode(data)))
      assert html_response(preview, 200)
      t = text(preview)
      assert doc(preview) |> LazyHTML.query("h1") |> text() == "What would be brought in"

      assert t =~
               "From findependence-export.json, checked. Nothing is saved until you choose “Bring it in”."

      assert t =~ "1 item: Rent"
      assert t =~ "1 value: A safe home"
      assert t =~ "1 account: Checking"
      assert t =~ "1 balance"
      assert t =~ "1 link to a value"

      assert t =~
               "All of it becomes yours alone. Its history, owners, and who it was shared with in the other household stay in your file."

      assert t =~
               "1 shared plan isn't brought in: it was an agreement with others in the other household."

      # nothing saved yet (REQ-158 AC-3)
      assert titles(h, "ben") == before

      done = act(h, "ben", "/act/bring-in/confirm", %{})
      assert redirected_to(done) == "/"

      assert info(done) ==
               "Brought in 1 item, 1 value and 1 account from your file. Only you own them; nobody else can see them until you share."

      ben = id(h, "ben")
      new = scope(h, "ben") |> Items.visible() |> Enum.filter(&(ben in &1.owners))
      assert Enum.sort(Enum.map(new, &Words.title/1)) == ["A safe home", "Checking", "Rent"]
      assert Enum.all?(new, &(Enum.to_list(&1.owners) == [ben] and &1.grantees == []))

      # the same file again is refused, with the date it was brought in
      again = upload(h, "ben", IO.iodata_to_binary(:json.encode(data)))

      assert text(again) =~
               "You brought in this file on Tuesday, September 29, so it wasn't brought in again."
    end

    test "REQ-157 AC-1: an upload over 1 MB is refused with 413 before it is read; a file of exactly 1 MB is checked" do
      h = with_records()
      json = saved_file(h)
      before = stored()

      # the upload itself over the limit: refused by the body parser, with the local form's page
      big = multipart(h, "ana", :binary.copy("a", 1_200_000))
      assert big.status == 413
      assert big.resp_body =~ "That file is too large"

      assert big.resp_body =~
               "An export file is at most 1 MB, so this one wasn't read. Nothing was brought in."

      assert stored() == before

      # exactly 1 MB (1,048,576 bytes) is read and checked
      exact = json <> String.duplicate(" ", 1_048_576 - byte_size(json))
      assert byte_size(exact) == 1_048_576
      checked = multipart(h, "ana", exact)
      assert html_response(checked, 200) =~ "What would be brought in"

      # one byte more fits in the upload, but the file is refused as too large, unread
      over = multipart(h, "ana", exact <> " ")
      assert over.status == 422

      assert text(over) =~
               "An export file is at most 1 MB, so this one wasn't read. Nothing was brought in."

      assert stored() == before
    end

    test "REQ-157: a file that fails a check is refused whole, saying what and where" do
      h = with_records()
      data = :json.decode(saved_file(h))
      i = Enum.find_index(data["items"], &(&1["attrs"]["note"] == "Rent"))
      bad = put_in(data, ["items", Access.at(i), "attrs", "amount"], 1.5)
      before = titles(h, "ana")

      resp = upload(h, "ana", IO.iodata_to_binary(:json.encode(bad)))
      assert resp.status == 422
      t = text(resp)

      assert doc(resp) |> LazyHTML.query("h2.pc-card__title") |> Enum.map(&text/1) == [
               "Nothing was brought in"
             ]

      assert t =~
               "Number #{i + 1} in the file, amount: isn't an amount in whole cents within range."

      assert text(upload(h, "ana", "not json at all")) =~
               "This isn't a Findependence export file. Nothing was brought in."

      assert text(act(h, "ana", "/act/bring-in", %{})) =~
               "Choose your saved file first. Nothing was brought in."

      assert titles(h, "ana") == before
    end

    test "REQ-158: the waiting file is dropped when the member goes to another page; confirming then brings nothing in, and nothing of it is stored" do
      h = with_records()
      file = saved_file(h)
      before = stored()
      titles_before = titles(h, "ben")

      preview = upload(h, "ben", file)
      assert html_response(preview, 200) =~ "What would be brought in"
      # while it waits, nothing of the file is in storage (it is in the session's memory only)
      assert stored() == before

      # the member goes to another page, then comes back and sends the preview's form
      assert html_response(page(h, "ben", "/next-60-days"), 200)
      sent = act(h, "ben", "/act/bring-in/confirm", %{})
      assert redirected_to(sent) == "/bring-in"
      assert info(sent) == "Nothing is waiting to be brought in. Choose the file again."
      assert titles(h, "ben") == titles_before
      assert stored() == before

      # the home page and the household page are other pages too (fixed in WI-076: they had kept the file)
      for other <- ["/", "/household"] do
        assert html_response(upload(h, "ben", file), 200)
        assert FindependenceHosted.Sessions.pending(h["ben"].token)
        assert html_response(page(h, "ben", other), 200)
        refute FindependenceHosted.Sessions.pending(h["ben"].token), other
      end

      # a browser's background fetch is not leaving the page; cancelling brings nothing in
      assert html_response(upload(h, "ben", file), 200)

      conn_of(h, "ben")
      |> put_req_header("sec-fetch-dest", "image")
      |> get("/next-60-days")

      assert FindependenceHosted.Sessions.pending(h["ben"].token)

      cancelled = act(h, "ben", "/act/bring-in/cancel", %{})
      assert redirected_to(cancelled) == "/bring-in"
      assert info(cancelled) == "Nothing was brought in."
      refute FindependenceHosted.Sessions.pending(h["ben"].token)
      assert redirected_to(act(h, "ben", "/act/bring-in/confirm", %{})) == "/bring-in"
      assert titles(h, "ben") == titles_before
      assert stored() == before
    end

    test "the bring-in page offers one file form, labelled, with one h1" do
      h = household(~w(ana))
      conn = page(h, "ana", "/bring-in")
      d = doc(conn)
      html = html_response(conn, 200)
      assert d |> LazyHTML.query("h1") |> text() == "Bring in your record"
      assert html =~ ~s(enctype="multipart/form-data")
      assert html =~ ~s(<label for="file")
      assert html =~ ~s(accept=".json,application/json")
      assert text(conn) =~ "You'll see what's in the file before anything is saved."
    end
  end

  # ---------------------------------------------------------------------------
  # REQ-191 AC-1

  test "REQ-191 AC-1: export and bring-in each write one content-free audit record" do
    h = with_records()
    session = FindependenceHosted.Sessions.fetch(h["ben"].token) |> elem(1)
    account = session.account_id
    household = session.membership.household_id
    start = length(audits())

    file = saved_file(h, "ben")
    assert [["export", "ok", ^account, ^household, nil]] = Enum.drop(audits(), start)

    # the export page itself is only looking; the file is the export
    assert html_response(page(h, "ben", "/export"), 200)
    assert length(audits()) == start + 1

    ana_file = saved_file(h, "ana")
    start = length(audits())
    assert html_response(upload(h, "ben", ana_file), 200)
    assert redirected_to(act(h, "ben", "/act/bring-in/confirm", %{})) == "/"
    assert [["bring_in", "ok", ^account, ^household, nil]] = Enum.drop(audits(), start)

    # a refused file is one refused record
    start = length(audits())
    assert upload(h, "ben", "not json").status == 422
    assert [["bring_in", "refused", ^account, ^household, nil]] = Enum.drop(audits(), start)

    # nothing of the file or the member's words is in the audit log
    columns = Repo.query!("select * from audit_events").rows |> List.flatten()

    for v <- columns, is_binary(v) do
      refute v =~ "Rent"
      refute v =~ "Ben"
      refute v == file
    end
  end

  # ---------------------------------------------------------------------------
  # The leave checklist (UX-001 R8)

  describe "the leave checklist" do
    test "REQ-166 AC-5: deleting needs an explicit choice beside the item's name, from a required list starting with nothing chosen; sent with no choice, nothing is deleted" do
      h = with_records()
      conn = page(h, "ana", "/leave")
      d = doc(conn)
      html = html_response(conn, 200)
      assert d |> LazyHTML.query("h1") |> text() == "Leave the household"

      refute "/act/delete" in (d |> LazyHTML.query("form") |> LazyHTML.attribute("action"))

      for title <- ["A safe home", "Rent", "Checking"] do
        id = id_of(h, "ana", title)
        select = d |> LazyHTML.query(~s(select[id="to-#{id}"]))
        assert LazyHTML.attribute(select, "name") == ["to"]
        assert LazyHTML.attribute(select, "required") == [""]

        assert d |> LazyHTML.query(~s(label[for="to-#{id}"])) |> text() ==
                 "What happens to “#{title}”"

        options = select |> LazyHTML.query("option")

        assert [{"", "Choose…"} | _] =
                 Enum.zip(LazyHTML.attribute(options, "value"), Enum.map(options, &text/1))

        assert {"delete", "Delete it for everyone (can't be undone)"} ==
                 Enum.zip(LazyHTML.attribute(options, "value"), Enum.map(options, &text/1))
                 |> List.last()

        refute select |> LazyHTML.query("option[selected]") |> Enum.any?()
      end

      assert html =~ "Give it to Ben (waits for Ben to agree)"
      assert html =~ ~s(value="give:#{id(h, "ben")}")

      # without that choice, nothing is deleted
      rent = id_of(h, "ana", "Rent")
      refused = act(h, "ana", "/act/let_go", %{"item" => rent, "return" => "/leave"})
      assert refused.status == 422
      assert text(refused) =~ Messages.error_text(:no_choice)
      assert "Rent" in titles(h, "ana")

      # with it, deleted, and back to the checklist saying so
      done =
        act(h, "ana", "/act/let_go", %{"item" => rent, "to" => "delete", "return" => "/leave"})

      assert redirected_to(done) == "/leave"
      assert info(done) =~ "Rent"
      refute "Rent" in titles(h, "ana")
    end

    test "each owned thing has its one action; Leave appears once nothing is owned, and a refused Leave says why" do
      h = with_records()
      # giving the value to Ben waits for Ben to agree
      home = id_of(h, "ana", "A safe home")
      {:ok, _} = Items.propose_owners(scope(h, "ana"), home, [id(h, "ben")])
      t = text(page(h, "ana", "/leave"))
      assert t =~ "1. Save a copy"
      assert t =~ "See everything you'd take with you, and save it as a file."
      assert t =~ "2. What you own (3)"
      assert t =~ "Waiting for Ben to agree."
      assert t =~ "You can leave once you don't own anything."

      conn = page(h, "ana", "/leave")
      refute conn.resp_body =~ ~s(action="/leave")

      refused = act(h, "ana", "/leave", %{})
      assert refused.status == 422
      assert text(refused) =~ Messages.error_text(:still_owner)

      # Ben, owning nothing, sees the button and the consequences
      ben = text(page(h, "ben", "/leave"))
      assert ben =~ "You don't own anything now."

      assert ben =~
               "You'll stop seeing the 1 item or value others share with you. Your links and your passphrase stop working here. This can't be undone."

      left = act(h, "ben", "/leave", %{})
      assert redirected_to(left) == "/sign-in"

      assert info(left) ==
               "You've left the household. Sign in to start or join another, or to delete your account."
    end
  end
end
