defmodule FindependenceApp.WI079SecurityTest do
  @moduledoc """
  WI-079: the security review's findings FND-01 (a planted seal made a later honest save extend keys), FND-04
  (content, history, and balances could be forged from public keys alone), and FND-02 (stored bytes could decode
  to functions). Each attack is by a household member who can edit the vault file (threat model T1), as the
  review's reproductions did.
  """
  use ExUnit.Case, async: true

  alias FindependenceApp.{Session, Vault}
  alias FindependenceShared.{Crypto, Envelope, SafeTerm}
  alias Findependence.{Balances, Household, Ledger}

  @opts [iterations: 1_000, unsafe_test: true]

  defp vault, do: Vault.create([{"ana", "pw-ana"}, {"ben", "pw-ben"}, {"cy", "pw-cy"}], @opts)

  defp session(v, m) do
    {:ok, s} = Session.open(v, m, "pw-" <> m)
    s
  end

  defp act(v, m, fun) do
    s = session(v, m)

    case fun.(s.household) do
      {:ok, h} -> Session.save(%{s | household: h}).vault
      {:ok, h, _} -> Session.save(%{s | household: h}).vault
      {:error, _} = e -> flunk("#{m}: #{inspect(e)}")
    end
  end

  defp issues(v, m), do: Session.integrity_issues(session(v, m))

  @doc false
  def called(pid), do: send(pid, :called)

  defp reading(on, balance),
    do: %{on: on, balance: balance, rate_bp: 2199, min_payment: 15_000}

  # Ana owns a debt with two balances (the review's scenario).
  defp debt_vault do
    vault()
    |> act("ana", &Balances.add_debt(&1, "ana", "visa", "Visa", :card))
    |> act("ana", &Balances.add_reading(&1, "ana", "visa", reading("2026-08-27", 540_000)))
    |> act("ana", &Balances.add_reading(&1, "ana", "visa", reading("2026-09-27", 520_000)))
  end

  # A seal of a random key to cy: structurally a real seal, as cy can make with public keys alone.
  defp junk(v, ctx),
    do: Crypto.seal(v.members["cy"].pub, Crypto.random_key(), Vault.aad(v.hid, ctx))

  # Every key cy can open from the file with cy's own secrets that actually decrypts its box: the real ones.
  defp cy_real_keys(v, id) do
    s = session(v, "cy")
    rec = v.items[id]

    open = fn sealed, ctx ->
      sealed && Crypto.open(s.pub, s.priv, sealed, Vault.aad(v.hid, ctx))
    end

    boxes =
      for {kind, key_kind, list} <- [
            {:entry, :entry_key, rec.ledger},
            {:reading, :reading_key, Map.get(rec, :readings, [])}
          ],
          b <- list,
          {:ok, k} <- [open.(b.keys["cy"], {key_kind, id, b.seq, "cy"})],
          {:ok, _} <- [Crypto.decrypt(k, b.box, Vault.aad(v.hid, {kind, id, b.seq}))],
          do: {kind, b.seq}

    item =
      with {:ok, k} <- open.(rec.keys["cy"], {:item_key, id, "cy"}),
           {:ok, _} <- Crypto.decrypt(k, rec.content, Vault.aad(v.hid, {:content, id})),
           do: [:item],
           else: (_ -> [])

    item ++ boxes
  end

  describe "FND-01: a planted seal does not make an honest save extend keys" do
    test "scenario B: a planted grantee with a junk item-key seal gets no balance key, and it stays reported" do
      v = debt_vault()

      v =
        update_in(v, [:items, "visa"], fn rec ->
          %{
            rec
            | grantees: Enum.sort(["cy" | rec.grantees]),
              keys: Map.put(rec.keys, "cy", junk(v, {:item_key, "visa", "cy"}))
          }
        end)

      assert {:unverified_seal, "visa", "cy"} in issues(v, "ana")

      # Ana's unrelated save re-encrypts every item she can read; then she records a new balance
      v = act(v, "ana", &Household.add_item(&1, "ana", "i2", %{note: "unrelated"}))
      assert cy_real_keys(v, "visa") == []
      assert {:unverified_seal, "visa", "cy"} in issues(v, "ana")

      v = act(v, "ana", &Balances.add_reading(&1, "ana", "visa", reading("2026-10-27", 500_000)))
      assert cy_real_keys(v, "visa") == []
      assert {:unverified_seal, "visa", "cy"} in issues(v, "ana")
    end

    test "scenario C: a planted owner with junk seals on the item, its history, and its balances gets nothing" do
      v = debt_vault()

      v =
        update_in(v, [:items, "visa"], fn rec ->
          %{
            rec
            | owners: Enum.sort(["cy" | rec.owners]),
              keys: Map.put(rec.keys, "cy", junk(v, {:item_key, "visa", "cy"})),
              ledger:
                Enum.map(rec.ledger, fn e ->
                  %{e | keys: Map.put(e.keys, "cy", junk(v, {:entry_key, "visa", e.seq, "cy"}))}
                end),
              readings:
                Enum.map(rec.readings, fn r ->
                  %{r | keys: Map.put(r.keys, "cy", junk(v, {:reading_key, "visa", r.seq, "cy"}))}
                end)
          }
        end)

      assert {:unverified_seal, "visa", "cy"} in issues(v, "ana")

      v = act(v, "ana", &Balances.add_reading(&1, "ana", "visa", reading("2026-10-27", 500_000)))
      assert cy_real_keys(v, "visa") == []
      after_save = issues(v, "ana")
      assert {:unverified_seal, "visa", "cy"} in after_save

      # and again after a further unrelated save: the report persists
      v = act(v, "ana", &Household.add_item(&1, "ana", "i3", %{note: "unrelated"}))
      assert cy_real_keys(v, "visa") == []
      assert {:unverified_seal, "visa", "cy"} in issues(v, "ana")
    end

    test "scenario C2: a planted owner with junk item and history seals gets no earlier balance on a save" do
      v = debt_vault()

      v =
        update_in(v, [:items, "visa"], fn rec ->
          %{
            rec
            | owners: Enum.sort(["cy" | rec.owners]),
              keys: Map.put(rec.keys, "cy", junk(v, {:item_key, "visa", "cy"})),
              ledger:
                Enum.map(rec.ledger, fn e ->
                  %{e | keys: Map.put(e.keys, "cy", junk(v, {:entry_key, "visa", e.seq, "cy"}))}
                end)
          }
        end)

      before = issues(v, "ana")
      assert before != []
      v = act(v, "ana", &Household.add_item(&1, "ana", "i9", %{note: "unrelated"}))
      assert cy_real_keys(v, "visa") == []
      assert {:unverified_seal, "visa", "cy"} in issues(v, "ana")
    end

    test "a planted seal with a made-up commitment is refused the same way" do
      v = debt_vault()
      sealed = Map.put(junk(v, {:item_key, "visa", "cy"}), :k, :crypto.strong_rand_bytes(32))

      v =
        update_in(v, [:items, "visa"], fn rec ->
          %{rec | grantees: ["cy"], keys: Map.put(rec.keys, "cy", sealed)}
        end)

      v = act(v, "ana", &Balances.add_reading(&1, "ana", "visa", reading("2026-10-27", 500_000)))
      assert cy_real_keys(v, "visa") == []
      assert {:unverified_seal, "visa", "cy"} in issues(v, "ana")
    end

    test "legitimate sharing still reaches the new reader, with commitments, and nothing is reported" do
      v = debt_vault() |> act("ana", &Household.propose_grant(&1, "ana", "visa", "cy"))
      assert {:reading, 2} in cy_real_keys(v, "visa")
      assert :item in cy_real_keys(v, "visa")

      for {r, sealed} <- v.items["visa"].keys,
          do: assert(Crypto.commitment_valid?(session(v, "ana").item_keys["visa"], r, sealed.k))

      v = act(v, "ana", &Balances.add_reading(&1, "ana", "visa", reading("2026-10-27", 500_000)))
      assert {:reading, 3} in cy_real_keys(v, "visa")
      for m <- ~w(ana ben cy), do: assert(issues(v, m) == [])
    end
  end

  describe "FND-04: forged content, history, and balances are reported and not shown" do
    test "scenario D: a forged history entry and a forged item made from public keys alone" do
      v = debt_vault()
      ana_pub = v.members["ana"].pub
      seq = length(v.items["visa"].ledger) + 1

      ek = Crypto.random_key()
      fake_entry = %{seq: seq, event: :granted, by: ["ana"], details: %{grantee: "ben"}}

      forged = %{
        seq: seq,
        box:
          Crypto.encrypt(ek, Vault.encode(fake_entry), Vault.aad(v.hid, {:entry, "visa", seq})),
        keys: %{
          "ana" => Crypto.seal(ana_pub, ek, Vault.aad(v.hid, {:entry_key, "visa", seq, "ana"}))
        }
      }

      nk = Crypto.random_key()
      attrs = %{note: "Transfer to Cy (agreed)", amount: -250_000, unit: :cents}

      v =
        v
        |> update_in([:items, "visa", :ledger], &(&1 ++ [forged]))
        |> put_in([:items, "fake"], %{
          owners: ["ana"],
          grantees: ["cy"],
          content: Crypto.encrypt(nk, Vault.encode(attrs), Vault.aad(v.hid, {:content, "fake"})),
          keys: %{
            "ana" => Crypto.seal(ana_pub, nk, Vault.aad(v.hid, {:item_key, "fake", "ana"}))
          },
          ledger: [],
          readings: []
        })

      s = session(v, "ana")
      assert {:ok, entries} = Ledger.read(s.household, "ana", "visa")
      assert List.last(entries) == :sealed
      assert s.household.items["fake"].attrs == %{}
      refute Map.has_key?(s.item_keys, "fake")

      assert {:unsigned_box, "visa", {:entry, seq}} in Session.integrity_issues(s)
      assert {:unsigned_box, "fake", :content} in Session.integrity_issues(s)
    end

    test "a forged balance is reported and is never the balance shown" do
      v = debt_vault()
      rk = Crypto.random_key()
      fake = Map.merge(reading("2026-09-30", 1), %{seq: 3, by: "ana"})

      forged = %{
        seq: 3,
        box: Crypto.encrypt(rk, Vault.encode(fake), Vault.aad(v.hid, {:reading, "visa", 3})),
        keys: %{
          "ana" =>
            Crypto.seal(
              v.members["ana"].pub,
              rk,
              Vault.aad(v.hid, {:reading_key, "visa", 3, "ana"})
            )
        }
      }

      v = update_in(v, [:items, "visa", :readings], &(&1 ++ [forged]))
      s = session(v, "ana")
      assert {:unsigned_box, "visa", {:reading, 3}} in Session.integrity_issues(s)
      # the forged balance is never shown; the genuine ones are still there
      assert Balances.latest(s.household, "ana", "visa") == nil

      assert {:ok, [%{balance: 540_000}, %{balance: 520_000}, :sealed]} =
               Balances.readings(s.household, "ana", "visa")
    end

    test "a member's own valid signature doesn't entitle them to write into an item they don't own" do
      v = debt_vault()
      cy = session(v, "cy")
      {_, cy_signing} = Crypto.signing_keypair(cy.priv)

      sign = fn box, ctx, author ->
        Map.merge(box, %{
          a: author,
          s: Crypto.sign(cy_signing, Envelope.signed_message(v.hid, ctx, author, box))
        })
      end

      # a new history entry on Ana's debt, signed by cy but claiming Ana acted
      seq = length(v.items["visa"].ledger) + 1
      ek = Crypto.random_key()
      entry = %{seq: seq, event: :granted, by: ["ana"], details: %{grantee: "cy"}}
      box = Crypto.encrypt(ek, Vault.encode(entry), Vault.aad(v.hid, {:entry, "visa", seq}))

      forged = %{
        seq: seq,
        box: sign.(box, {:entry, "visa", seq}, "cy"),
        keys: %{
          "ana" =>
            Crypto.seal(
              v.members["ana"].pub,
              ek,
              Vault.aad(v.hid, {:entry_key, "visa", seq, "ana"})
            )
        }
      }

      # a new balance on it, signed by cy as cy
      rk = Crypto.random_key()
      fake = Map.merge(reading("2026-09-30", 1), %{seq: 3, by: "cy"})
      rbox = Crypto.encrypt(rk, Vault.encode(fake), Vault.aad(v.hid, {:reading, "visa", 3}))

      forged_reading = %{
        seq: 3,
        box: sign.(rbox, {:reading, "visa", 3}, "cy"),
        keys: %{
          "ana" =>
            Crypto.seal(
              v.members["ana"].pub,
              rk,
              Vault.aad(v.hid, {:reading_key, "visa", 3, "ana"})
            )
        }
      }

      v =
        v
        |> update_in([:items, "visa", :ledger], &(&1 ++ [forged]))
        |> update_in([:items, "visa", :readings], &(&1 ++ [forged_reading]))

      s = session(v, "ana")
      assert {:signer_not_entitled, "visa", {:entry, seq}} in Session.integrity_issues(s)
      assert {:signer_not_entitled, "visa", {:reading, 3}} in Session.integrity_issues(s)
      # the forged balance is never shown; the genuine ones are still there
      assert Balances.latest(s.household, "ana", "visa") == nil

      assert {:ok, [%{balance: 540_000}, %{balance: 520_000}, :sealed]} =
               Balances.readings(s.household, "ana", "visa")

      assert {:ok, entries} = Ledger.read(s.household, "ana", "visa")
      assert List.last(entries) == :sealed
    end

    test "a signature that doesn't verify, or names someone else as author, is reported" do
      v = debt_vault()
      <<b, rest::binary>> = v.items["visa"].content.s
      flipped = put_in(v, [:items, "visa", :content, :s], <<Bitwise.bxor(b, 1), rest::binary>>)
      assert {:bad_signature, "visa", :content} in issues(flipped, "ana")
      assert session(flipped, "ana").household.items["visa"].attrs == %{}

      renamed = put_in(v, [:items, "visa", :content, :a], "ben")
      assert {:bad_signature, "visa", :content} in issues(renamed, "ana")

      unsigned = update_in(v, [:items, "visa", :content], &Map.drop(&1, [:a, :s]))
      assert {:unsigned_box, "visa", :content} in issues(unsigned, "ana")
    end

    test "signing keys are pinned in each member's secret; a changed one is reported and never trusted" do
      v = debt_vault() |> act("ben", &Household.add_item(&1, "ben", "b1", %{note: "Ben's"}))
      v = act(v, "ben", &Household.propose_grant(&1, "ben", "b1", "ana"))

      # every member's secret pins every member's signing key, derived from their private key
      for m <- ~w(ana ben cy) do
        s = session(v, m)

        for o <- ~w(ana ben cy),
            do:
              assert(s.secret.sign_pins[o] == elem(Crypto.signing_keypair(session(v, o).priv), 0))
      end

      # cy publishes a signing key of its own as Ben's, and signs Ben's item content with it
      {evil_pub, evil_priv} = :crypto.generate_key(:eddsa, :ed25519)
      box = Map.drop(v.items["b1"].content, [:a, :s])
      sig = Crypto.sign(evil_priv, Envelope.signed_message(v.hid, {:content, "b1"}, "ben", box))

      v2 =
        v
        |> put_in([:members, "ben", :sign_pub], evil_pub)
        |> put_in([:items, "b1", :content], Map.merge(box, %{a: "ben", s: sig}))

      found = issues(v2, "ana")
      assert {:signing_key_changed, "ben"} in found
      assert {:bad_signature, "b1", :content} in found

      # Ben's genuine boxes still verify under the pinned key
      only_key = put_in(v, [:members, "ben", :sign_pub], evil_pub)
      assert issues(only_key, "ana") == [{:signing_key_changed, "ben"}]
    end

    test "what a member who left had signed still verifies after they leave" do
      v =
        vault()
        |> act("ana", &Household.add_item(&1, "ana", "rent", %{note: "Rent"}))
        |> act("ana", &Household.propose_grant(&1, "ana", "rent", "cy"))

      cy_pub = v.members["cy"].sign_pub
      v = act(v, "cy", &Findependence.Exit.leave(&1, "cy"))
      refute Map.has_key?(v.members, "cy")
      assert v.signers["cy"] == cy_pub

      ana = session(v, "ana")
      assert Session.integrity_issues(ana) == []
      assert {:ok, entries} = Ledger.read(ana.household, "ana", "rent")
      # cy's own departure entry, signed by cy, verifies
      assert %{event: :grantee_departed} = List.last(entries)
      assert ana.sign_pins["cy"] == cy_pub
    end

    test "the member's own save republishes their signing key" do
      {evil_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
      v = put_in(debt_vault(), [:members, "ana", :sign_pub], evil_pub)
      assert {:signing_key_changed, "ana"} in issues(v, "ben")
      v = act(v, "ana", &Household.add_item(&1, "ana", "i2", %{note: "x"}))
      assert issues(v, "ben") == []
    end
  end

  describe "a vault written before signing (v0.8.1-alpha; fixture from test/fixtures/pre_signing.exs)" do
    # WI-080 (REV-107): such a file is refused; testers make a new household (their data is made up)
    test "it was written without signatures or commitments" do
      v = "test/fixtures/pre_signing.vault" |> File.read!() |> Envelope.decode()

      for {_, rec} <- v.items do
        refute Map.has_key?(rec.content, :s)
        for {_, sealed} <- rec.keys, do: refute(Map.has_key?(sealed, :k))
        for e <- rec.ledger, do: refute(Map.has_key?(e.box, :s))
      end

      for {_, m} <- v.members, do: refute(Map.has_key?(m, :sign_pub))
    end

    test "it is refused before anything is opened" do
      assert_raise Vault.OutdatedError, fn -> Vault.read!("test/fixtures/pre_signing.vault") end
    end

    test "a file whose member's signing key was taken out is refused the same way" do
      path = Path.join(System.tmp_dir!(), "fv-wi080-#{System.unique_integer([:positive])}.vault")
      on_exit(fn -> File.rm(path) end)

      debt_vault()
      |> update_in([:members, "ben"], &Map.delete(&1, :sign_pub))
      |> Vault.write!(path)

      assert_raise Vault.OutdatedError, fn -> Vault.read!(path) end
    end
  end

  describe "FND-02: stored bytes decode to plain data only" do
    test "a function in the bytes is refused by decode, and never called" do
      me = self()
      fun = fn _acc, _reducer -> called(me) end
      bin = :erlang.term_to_binary(%{member_order: fun, members: %{}})
      assert_raise SafeTerm.UnsafeTermError, fn -> Envelope.decode(bin) end
      assert_raise SafeTerm.UnsafeTermError, fn -> Vault.decode(bin) end
      refute_received :called

      # an external function too
      assert_raise SafeTerm.UnsafeTermError, fn ->
        Envelope.decode(:erlang.term_to_binary(&__MODULE__.called/1))
      end
    end

    test "functions, pids, and references are found anywhere in the term" do
      fun = fn -> :ok end

      for bad <- [
            [1, 2 | fun],
            %{fun => 1},
            {:a, {:b, [self()]}},
            MapSet.new([make_ref()]),
            [%{a: [{1, fun}]}]
          ] do
        assert_raise SafeTerm.UnsafeTermError, fn ->
          Envelope.decode(:erlang.term_to_binary(bad))
        end
      end

      assert Envelope.decode(:erlang.term_to_binary([1, 2 | 3])) == [1, 2 | 3]

      assert Envelope.decode(:erlang.term_to_binary(%{a: MapSet.new(["x"])})) == %{
               a: MapSet.new(["x"])
             }
    end

    test "a vault file holding a function is refused before any use" do
      me = self()
      v = %{vault() | member_order: fn _acc, _reducer -> called(me) end}
      path = Path.join(System.tmp_dir!(), "fv-fun-#{System.unique_integer([:positive])}.vault")
      File.write!(path, :erlang.term_to_binary(v))
      on_exit(fn -> File.rm(path) end)

      assert_raise SafeTerm.UnsafeTermError, fn -> Vault.read!(path) end
      refute_received :called
    end

    test "a vault file of the wrong shape is refused with a clear error" do
      path = Path.join(System.tmp_dir!(), "fv-shape-#{System.unique_integer([:positive])}.vault")
      on_exit(fn -> File.rm(path) end)
      good = act(debt_vault(), "ana", &Household.propose_grant(&1, "ana", "visa", "ben"))

      proposal = %{
        item_id: "visa",
        change: {:grant, "cy"},
        consents: MapSet.new(["ana"]),
        proposed_by: "ana"
      }

      good = %{good | proposals: %{7 => proposal}}

      Vault.write!(good, path)
      assert Vault.read!(path) == good

      bad = [
        {"the file", [1, 2]},
        {"the file", Map.put(good, :extra, 1)},
        {"member_order", %{good | member_order: %{"ana" => 1}}},
        {"member_order", %{good | member_order: ["ana", :ben]}},
        {"members", put_in(good, [:members, "ana", :pub], 42)},
        {"members", put_in(good, [:members, "ana", :salt], nil)},
        {"items", %{good | items: []}},
        {~s(item "visa"), put_in(good, [:items, "visa", :owners], MapSet.new(["ana"]))},
        {~s(item "visa"), put_in(good, [:items, "visa", :ledger], [%{seq: "1"}])},
        {~s(item "visa"), put_in(good, [:items, "visa", :keys, "ben"], "not a seal")},
        {"proposals", put_in(good, [:proposals, 7, :change], {:delete, "visa"})},
        {"proposals", put_in(good, [:proposals, 7, :consents], ["ana"])},
        {"personal", put_in(good, [:personal, "ana"], %{n: 1})}
      ]

      for {where, v} <- bad do
        File.write!(path, :erlang.term_to_binary(v))
        e = assert_raise Vault.MalformedError, fn -> Vault.read!(path) end
        assert Exception.message(e) =~ where
      end

      File.write!(path, "not a term")
      assert_raise Vault.MalformedError, fn -> Vault.read!(path) end
    end
  end
end

defmodule FindependenceApp.WI079WebTest do
  @moduledoc """
  WI-079 through the local web interface: a forged item (the review's forge_web.exs) is reported in the
  integrity banner and not shown, and an item saved before signing carries the neutral note.
  """
  use ExUnit.Case, async: false
  import Plug.Test

  alias FindependenceApp.{Sessions, Store, Vault, Web}
  alias FindependenceShared.Crypto

  defp start(path) do
    start_supervised!({Store, path: path})
    start_supervised!(Sessions)
    on_exit(fn -> File.rm(path) end)
  end

  defp request(method, path, params \\ %{}, prev \\ nil) do
    conn = %{conn(method, path, params) | host: "127.0.0.1", port: 4848}
    conn = if prev, do: recycle_cookies(conn, prev), else: conn
    Web.call(conn, Web.init(port: 4848))
  end

  defp unlock(member, pass) do
    page = request(:get, "/")
    csrf = Regex.run(~r/name=_csrf_token value="([^"]+)"/, page.resp_body) |> List.last()
    form = Regex.run(~r/name=_form value="([^"]+)"/, page.resp_body) |> List.last()

    request(
      :post,
      "/login",
      %{"_csrf_token" => csrf, "_form" => form, "member" => member, "passphrase" => pass},
      page
    )
  end

  test "a forged item is reported in the banner and its content is not shown" do
    path =
      Path.join(System.tmp_dir!(), "fv-wi079-web-#{System.unique_integer([:positive])}.vault")

    v =
      Vault.create([{"ana", "pw-ana 123456"}, {"cy", "pw-cy 1234567"}],
        iterations: 1_000,
        unsafe_test: true
      )

    nk = Crypto.random_key()

    forged = %{
      owners: ["ana"],
      grantees: [],
      content:
        Crypto.encrypt(
          nk,
          Vault.encode(%{note: "Forged transfer", amount: -100, unit: :cents}),
          Vault.aad(v.hid, {:content, "forged1"})
        ),
      keys: %{
        "ana" =>
          Crypto.seal(v.members["ana"].pub, nk, Vault.aad(v.hid, {:item_key, "forged1", "ana"}))
      },
      ledger: [],
      readings: []
    }

    v |> put_in([:items, "forged1"], forged) |> Vault.write!(path)
    start(path)

    home = request(:get, "/", %{}, unlock("ana", "pw-ana 123456"))
    assert home.status == 200
    assert home.resp_body =~ "may have been changed outside Findependence"
    assert home.resp_body =~ "signed by someone who could have written them"
    refute home.resp_body =~ "Forged transfer"

    page = request(:get, "/items/forged1", %{}, home)
    assert page.status in [200, 404]
    refute page.resp_body =~ "Forged transfer"
  end

  test "the new words use the glossary's terms and carry no judgment" do
    alias FindependenceApp.Web.Glossary
    alias FindependenceShared.Words

    {heading, lines} =
      Words.integrity_notice(
        [{:unsigned_box, "i", :content}, {:unverified_seal, "i", "m"}],
        :file
      )

    {hosted, _} = Words.integrity_notice([{:bad_signature, "i", :content}], :stored)

    notes =
      for parts <- [[:content], [:history], [:readings], [:content, :history, :readings]],
          do: Words.before_signing_note(parts)

    for text <- [heading, hosted | lines ++ notes] do
      assert Glossary.violations(text) == [], text
      assert Glossary.judgments(text) == [], text
    end
  end

  test "a household file from before signing is not opened, and says what to do (WI-080)" do
    error =
      assert_raise Vault.OutdatedError, fn -> Vault.read!("test/fixtures/pre_signing.vault") end

    assert Exception.message(error) =~ "Make a new household with mix findependence.setup"
    text = Exception.message(error)
    assert FindependenceApp.Web.Glossary.violations(text) == [], text
    assert FindependenceApp.Web.Glossary.judgments(text) == [], text
  end
end
