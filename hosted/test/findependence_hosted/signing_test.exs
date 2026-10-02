defmodule FindependenceHosted.SigningTest do
  @moduledoc """
  WI-079 in the hosted form (security review FND-01, FND-04): signing keys published in the accounts table and
  pinned in each member's pins record; every box in the rows signed (the hosted form has nothing from before
  signing, so an unsigned box is always reported); and a seal planted in the rows without a valid commitment is
  never extended new keys. The operator, or anyone who can write the rows, plays the attacker.
  """
  use FindependenceHostedWeb.ConnCase, async: false

  alias FindependenceHosted.TestAccount

  import Ecto.Query
  import FindependenceShared.Contract.Helpers

  alias FindependenceHosted.{Accounts, Limits, Repo, Sessions}

  alias FindependenceHosted.Schemas.{Account, Membership}
  alias FindependenceHosted.TestStore

  alias FindependenceShared.{Crypto, Envelope, Persistence}

  @form FindependenceHosted.ContractForm

  setup do
    Limits.reset()
    :ok
  end

  defp session(token), do: elem(Sessions.fetch(token), 1)
  defp issues(h, name), do: Envelope.integrity_issues(scope(@form, h, name).session)
  defp hh(h), do: session(h |> Map.values() |> hd()).membership.household_id

  defp add_account(h, name, id) do
    s = scope(@form, h, name)
    m = s.member

    {:ok, _} =
      Persistence.run(s, &Findependence.Balances.add_account(&1, m, id, "Checking", :checking))

    {:ok, _} =
      Persistence.run(
        scope(@form, h, name),
        &Findependence.Balances.add_reading(&1, m, id, %{on: "2026-09-01", balance: 100_00})
      )

    id
  end

  test "each account publishes the signing key derived from its private key, never the key itself" do
    h = household(@form, ~w(ana ben))

    for {_, token} <- h do
      %{account_id: a, private_key: priv} = session(token)
      {pub, signing} = Crypto.signing_keypair(priv)
      account = Repo.get!(Account, a)
      assert account.signing_public_key == pub
      refute Enum.any?(stored_bytes(@form, h), &(:binary.match(&1, signing) != :nomatch))
    end
  end

  test "an account made before signing keys publishes its key at its next sign-in" do
    email = "old-#{System.unique_integer([:positive])}@example.com"
    pass = "a long passphrase 1"

    {:ok, id, number, _} =
      Accounts.sign_up(%{
        "passphrase" => pass,
        "passphrase_confirmation" => pass,
        "disclosure" => "true"
      })

    TestAccount.remember_number(email, number)

    Repo.update_all(from(a in Account, where: a.id == ^id), set: [signing_public_key: nil])
    {:ok, token} = Accounts.sign_in(TestAccount.number(email), pass, "test")

    assert Repo.get!(Account, id).signing_public_key ==
             elem(Crypto.signing_keypair(session(token).private_key), 0)
  end

  test "signing keys are pinned; one changed in the accounts table is reported and never trusted" do
    h = household(@form, ~w(ana ben))
    ben = id(@form, h, "ben")
    ben_account = session(h["ben"]).account_id
    # Ana's operation pins Ben's signing key; Ben's own item is shared with her
    _ = add_item(@form, h, "ana", "First")
    item = add_item(@form, h, "ben", "Ben's")

    {:ok, _} =
      FindependenceShared.Items.propose_grant(scope(@form, h, "ben"), item, id(@form, h, "ana"))

    assert issues(h, "ana") == []

    # the pins record holds it
    m = Repo.get!(Membership, id(@form, h, "ana"))
    view = scope(@form, h, "ana").session

    {:ok, bin} =
      Crypto.decrypt(
        view.personal,
        Envelope.decode(m.pins_box),
        Envelope.aad(view.vault.hid, {:pins, m.id})
      )

    assert Envelope.decode(bin).sign_pins[ben] ==
             Repo.get!(Account, ben_account).signing_public_key

    # the operator publishes a key of its own for Ben and re-signs Ben's item content with it
    {evil_pub, evil_priv} = :crypto.generate_key(:eddsa, :ed25519)

    Repo.update_all(from(a in Account, where: a.id == ^ben_account),
      set: [signing_public_key: evil_pub]
    )

    assert {:signing_key_changed, ben} in issues(h, "ana")
    assert reads?(@form, h, "ana", item)

    hid = stored(@form, h).hid
    box = Map.drop(stored(@form, h).items[item].content, [:a, :s])
    sig = Crypto.sign(evil_priv, Envelope.signed_message(hid, {:content, item}, ben, box))
    forged = Map.merge(box, %{a: ben, s: sig})

    # the operator holds the household keys (WI-085, WI-086): it changes the records and writes a fresh block
    TestStore.as_operator(hh(h), &put_in(&1, [:items, item, :content], forged))

    assert {:bad_signature, item, :content} in issues(h, "ana")
    refute reads?(@form, h, "ana", item)
  end

  test "an unsigned box in the rows is reported and not shown: there is nothing from before signing" do
    h = household(@form, ~w(ana ben))
    item = add_item(@form, h, "ana", "Rent")
    acct = add_account(h, "ana", "chk")
    assert issues(h, "ana") == []

    strip = fn box -> Map.drop(box, [:a, :s]) end

    strip_seq = fn boxes, seq ->
      Enum.map(boxes, &if(&1.seq == seq, do: %{&1 | box: strip.(&1.box)}, else: &1))
    end

    # the operator holds the household keys (WI-085, WI-086): it changes the records and writes a fresh block
    TestStore.as_operator(hh(h), fn held ->
      held
      |> update_in([:items, item, :content], strip)
      |> update_in([:items, acct, :ledger], &strip_seq.(&1, 2))
      |> update_in([:items, acct, :readings], &strip_seq.(&1, 1))
    end)

    found = issues(h, "ana")
    assert {:unsigned_box, item, :content} in found
    assert {:unsigned_box, acct, {:entry, 2}} in found
    assert {:unsigned_box, acct, {:reading, 1}} in found
    refute reads?(@form, h, "ana", item)
    assert Envelope.written_before_signing(scope(@form, h, "ana").session, item) == []
  end

  test "a reader planted in the rows with a seal that has no valid commitment gets no new key" do
    h = household(@form, ~w(ana ben))
    ben = id(@form, h, "ben")
    acct = add_account(h, "ana", "chk")
    hid = stored(@form, h).hid
    ben_pub = Repo.get!(Account, session(h["ben"]).account_id).public_key

    junk = Crypto.seal(ben_pub, Crypto.random_key(), Envelope.aad(hid, {:item_key, acct, ben}))

    # the operator holds the household keys (WI-085, WI-086): Ben written in as an owner, with a junk seal
    TestStore.as_operator(hh(h), fn held ->
      held
      |> update_in([:items, acct, :owners], &Enum.sort([ben | &1]))
      |> put_in([:items, acct, :keys, ben], junk)
    end)

    assert {:unverified_seal, acct, ben} in issues(h, "ana")

    m = id(@form, h, "ana")

    {:ok, _} =
      Persistence.run(
        scope(@form, h, "ana"),
        &Findependence.Balances.add_reading(&1, m, acct, %{on: "2026-09-02", balance: 200_00})
      )

    rec = TestStore.held(hh(h)).items[acct]
    refute Enum.any?(rec.ledger ++ rec.readings, &Map.has_key?(&1.keys, ben))

    assert {:unverified_seal, acct, ben} in issues(h, "ana")
  end
end

defmodule FindependenceHostedWeb.SigningPageTest do
  @moduledoc "WI-079: the hosted item page shows the integrity notice when a box in the rows isn't signed."
  use FindependenceHostedWeb.DomainCase

  alias FindependenceHosted.Repo
  alias FindependenceHosted.TestStore
  alias FindependenceShared.{Envelope, Items}

  test "an item whose content isn't signed is reported on its page, and its content is not shown" do
    h = household(~w(ana))

    input = %{note: "Rent", amount: {:ok, -1000}, frequency: :monthly, on: ""}
    {:ok, _} = Items.add_item(scope(h, "ana"), input)
    other = %{input | note: "Gym"}
    {:ok, saved} = Items.add_item(scope(h, "ana"), other)

    [rent, gym] =
      for n <- ["Rent", "Gym"],
          do:
            Enum.find_value(saved.household.items, fn {id, i} ->
              if i.attrs[:note] == n, do: id
            end)

    clean = page(h, "ana", "/items/#{gym}")
    refute clean.resp_body =~ "may have been changed outside Findependence"
    refute page(h, "ana", "/").resp_body =~ "may have been changed outside Findependence"

    # the operator holds the household keys (WI-085, WI-086): it strips the signature and writes a fresh block
    hid = elem(FindependenceHosted.Sessions.fetch(h["ana"].token), 1).membership.household_id

    TestStore.as_operator(
      hid,
      &update_in(&1, [:items, rent, :content], fn c -> Map.drop(c, [:a, :s]) end)
    )

    body = page(h, "ana", "/items/#{gym}").resp_body

    assert body =~
             "This household&#39;s stored information may have been changed outside Findependence"

    assert body =~ "signed by someone who could have written them"
    refute page(h, "ana", "/items/#{rent}").resp_body =~ "Rent"

    # WI-080: the home page says so too
    home = page(h, "ana", "/").resp_body

    assert home =~
             "This household&#39;s stored information may have been changed outside Findependence"

    assert home =~ ~s(id="integrity")
  end
end
