defmodule FindependenceShared.PortabilityWords do
  @moduledoc """
  The words of the export, bring-in, and leave pages (CAP-009, REQ-155..159, UX-001 R8), moved without change
  from the local form's page rendering (web/html.ex) so both forms say the same (WI-076). Plain text only: each
  form escapes and marks it up. Where a member is named, `name_of` turns a member id into what is shown: the
  local form's ids are the names themselves; the hosted form's are membership ids, shown by display name.
  """

  alias FindependenceShared.{Portability, Words}

  # ---------------------------------------------------------------------------
  # Bringing in (REQ-157, REQ-158)

  @doc """
  Why a file was refused, in one line: no file chosen, too large, not an export, or already brought in on a
  date (written out against `today`). All but the last end by saying nothing was brought in.
  """
  def problem_text(problem, today) do
    case problem do
      :no_file ->
        "Choose your saved file first. Nothing was brought in."

      :too_large ->
        "An export file is at most 1 MB, so this one wasn't read. Nothing was brought in."

      :not_json ->
        "This isn't a Findependence export file. Nothing was brought in."

      {:already_imported, on} ->
        "You brought in this file on #{Words.date_text(on, today)}, so it wasn't brought in again."
    end
  end

  @doc "What was wrong with a file that fails the checks, one line per problem: \"Number 2 in the file, amount: ...\"."
  def problem_lines(problems),
    do: Enum.map(problems, fn {where, what} -> "#{where_text(where)}: #{what_text(what)}" end)

  @doc "Where in the file: \"items[3].attrs.amount\" as \"Number 4 in the file, amount\"."
  def where_text(""), do: "The file"

  def where_text(where) do
    where
    |> String.split(".")
    |> Enum.reject(&(&1 == "attrs"))
    |> Enum.map(fn part ->
      case Regex.run(~r/\A(\w+)\[(\d+)\]\z/, part) do
        [_, "items", i] -> "number #{String.to_integer(i) + 1} in the file"
        [_, name, i] -> "#{segment(name)} #{String.to_integer(i) + 1}"
        nil -> segment(part)
      end
    end)
    |> Enum.join(", ")
    |> then(&((String.slice(&1, 0, 1) |> String.upcase()) <> String.slice(&1, 1..-1//1)))
  end

  @segments %{
    "items" => "number",
    "readings" => "balance",
    "links" => "link",
    "plans" => "plan",
    "steps" => "step",
    "marks" => "mark",
    "goals" => "goals",
    "set_aside" => "set-aside",
    "retirement" => "retirement",
    "contributions" => "contribution",
    "note" => "name",
    "label" => "name",
    "name" => "name",
    "amount" => "amount",
    "unit" => "unit",
    "frequency" => "how often",
    "on" => "date",
    "from" => "month",
    "kind" => "kind",
    "account_type" => "kind",
    "debt_type" => "kind",
    "balance" => "balance",
    "rate_bp" => "interest rate",
    "min_payment" => "minimum payment",
    "payment" => "monthly payment",
    "fund_months" => "fund goal",
    "item" => "item",
    "value" => "value",
    "job" => "job",
    "account" => "account",
    "cents" => "amount",
    "id" => "id",
    "version" => "version"
  }

  defp segment(name), do: Map.get(@segments, name, "“#{name}”")

  @doc "What was wrong at that place in the file."
  def what_text(what) do
    case what do
      :not_an_export ->
        "isn't a Findependence export."

      :unknown_version ->
        "is from a newer version of the app."

      :missing ->
        "is missing."

      :not_a_list ->
        "isn't in the expected form."

      :not_an_object ->
        "isn't in the expected form."

      {:too_many, n} ->
        "is longer than the #{n} the app accepts."

      :unknown_field ->
        "isn't part of an export."

      :invalid_id ->
        "isn't a valid id."

      :invalid_amount ->
        "isn't an amount in whole cents within range."

      :invalid_unit ->
        "isn't a known unit."

      :invalid_frequency ->
        "isn't a known way of saying how often."

      :invalid_date ->
        "isn't a valid date."

      :invalid_month ->
        "isn't a valid month."

      :invalid_text ->
        "must be 1 to 200 characters of text."

      :invalid_kind ->
        "isn't a known kind."

      :readings_not_allowed ->
        "has balances, but only accounts and debts do."

      :invalid_rate ->
        "isn't a rate from 0% to 100%."

      {:duplicate_id, _} ->
        "uses the same id twice."

      :bad_reference ->
        "refers to an item or value that isn't in the file, or isn't the right kind."

      :invalid_step ->
        "isn't a known kind of step."

      :invalid_goal ->
        "isn't a number of months from 1 to 60."

      :invalid_retirement ->
        "is outside what the retirement page allows."

      _ ->
        "isn't allowed."
    end
  end

  @doc """
  REQ-158: the preview's lines, counting what the file would bring in and naming the items, values, accounts,
  debts, and plans (the first twelve of each, by name): \"3 items: Health plan, Paycheck, Rent\", \"2 balances\".
  Empty when the file has nothing to bring in.
  """
  def preview_lines(summary) do
    names = fn list ->
      {shown, rest} = Enum.split(Enum.sort_by(list, &String.downcase/1), 12)
      more = if rest == [], do: "", else: ", and #{length(rest)} more"
      Enum.join(shown, ", ") <> more
    end

    lines =
      [
        {summary.items, "item", "items"},
        {summary.values, "value", "values"},
        {summary.accounts, "account", "accounts"},
        {summary.debts, "debt", "debts"}
      ]
      |> Enum.reject(fn {l, _, _} -> l == [] end)
      |> Enum.map(fn {l, one, many} -> "#{count(length(l), one, many)}: #{names.(l)}" end)

    extra =
      [
        {summary.readings, "balance", "balances"},
        {summary.links, "link to a value", "links to values"},
        {summary.marks, "mark on what depends on a job", "marks on what depends on a job"},
        {Map.get(summary, :attached, 0), "choice of the account an item goes through",
         "choices of the account an item goes through"},
        {summary.goals, "goal", "goals"},
        {summary.retirement, "retirement assumption", "retirement assumptions"}
      ]
      |> Enum.reject(fn {n, _, _} -> n == 0 end)
      |> Enum.map(fn {n, one, many} -> count(n, one, many) end)

    plans =
      if summary.plans == [],
        do: [],
        else: ["#{count(length(summary.plans), "plan", "plans")}: #{names.(summary.plans)}"]

    lines ++ extra ++ plans
  end

  @doc "REQ-156: that the file's shared plans aren't brought in, and why; nil when it has none."
  def shared_plans_text(%{shared_plans: n}) when n > 0,
    do:
      "#{count(n, "shared plan isn't", "shared plans aren't")} brought in: #{if n == 1, do: "it was an agreement", else: "they were agreements"} with others in the other household."

  def shared_plans_text(_summary), do: nil

  defp count(n, one, many), do: "#{n} #{if n == 1, do: one, else: many}"

  # ---------------------------------------------------------------------------
  # The export (REQ-155, REQ-169)

  @doc """
  An account or debt on the export page, after its name: its kind, its latest balance and when, and how many
  balances go with it: \"(Checking account). $1,240.00 as of Friday, September 27. 2 balances recorded.\"
  """
  def balance_summary(i, today) do
    readings = Enum.filter(Map.get(i, :readings, []), &is_map/1)

    latest =
      case List.last(readings) do
        nil -> "No balance yet."
        r -> "#{Words.balance_text(i, r)} as of #{Words.date_text(r.on, today)}."
      end

    n = length(readings)

    "(#{Words.kind_words(i)}). #{latest} #{n} #{if n == 1, do: "balance", else: "balances"} recorded."
  end

  @doc "Who owns an item in the export, the member as \"you\": \"Owned by Ben and you.\""
  def owned_by(i, m, name_of \\ &Function.identity/1),
    do: "Owned by #{Words.people(i.owners, m, "No one", name_of)}."

  @doc "Who else can see it: \"Ben can see it too.\", or nil when no one."
  def also_seen_by(i, m, name_of \\ &Function.identity/1)
  def also_seen_by(%{grantees: []}, _m, _name_of), do: nil

  def also_seen_by(i, m, name_of),
    do: "#{Words.people(i.grantees, m, "No one", name_of)} can see it too."

  @doc "The member's own links in the export, by name and in order: \"Rent → A safe home\"."
  def links(links, names) do
    links
    |> Enum.sort_by(fn {i, v} ->
      {String.downcase(names[i] || ""), String.downcase(names[v] || "")}
    end)
    |> Enum.map(fn {i, v} -> "#{names[i]} → #{names[v]}" end)
  end

  @doc """
  The saved file (REQ-155): `Portability.to_data/1`, plus each item's history in words. Wherever the file
  names a member (the member, owners, those it is shared with, and who recorded a balance), `name_of` names
  them, so the hosted form's file shows display names, never membership ids.
  """
  def export_json(export, name_of \\ &Function.identity/1) do
    history =
      Map.new(export.items, fn i ->
        {to_string(i.id), Enum.map(i.ledger, &Words.event_text(&1, name_of))}
      end)

    ids = Map.new(member_ids(export), &{to_string(&1), &1})
    named = fn id -> id |> then(&Map.get(ids, &1, &1)) |> name_of.() |> to_string() end

    export
    |> Portability.to_data()
    |> Map.update!("member", named)
    |> Map.update!("items", fn items ->
      Enum.map(items, fn item ->
        item
        |> Map.put("history", history[item["id"]])
        |> Map.update("owners", [], &Enum.map(&1, named))
        |> Map.update("grantees", [], &Enum.map(&1, named))
        |> Map.update("readings", [], fn readings ->
          Enum.map(readings, fn r ->
            if is_binary(r["by"]), do: Map.update!(r, "by", named), else: r
          end)
        end)
      end)
    end)
    |> :json.encode()
    |> IO.iodata_to_binary()
  end

  # the member ids as the export holds them, so `name_of` is given the id itself, not its text
  defp member_ids(export) do
    [
      export.member
      | Enum.flat_map(export.items, fn i ->
          Enum.to_list(i.owners) ++
            Enum.to_list(i.grantees) ++
            for(r <- Map.get(i, :readings, []), is_map(r), Map.has_key?(r, :by), do: r.by)
        end)
    ]
  end

  # ---------------------------------------------------------------------------
  # The leave checklist (UX-001 R8)

  @doc "What leaving does to what others share with the member, from how many there are; empty for none."
  def shared_text(0), do: ""
  def shared_text(1), do: "You'll stop seeing the 1 item or value others share with you. "

  def shared_text(n),
    do: "You'll stop seeing the #{n} items and values others share with you. "

  @doc """
  An item the member has asked to give away, waiting on others: \"Waiting for Ben to agree.\" `mine` are the
  item's pending changes the member has agreed to.
  """
  def waiting_text(i, mine, m, name_of \\ &Function.identity/1) do
    # REQ-201 (WI-088): a deletion the member scheduled happens when they leave, if not before
    case Enum.find(mine, &(&1.change == :delete)) do
      %{due: due} when is_integer(due) ->
        "Deleted when you leave, or #{Words.when_text(due)}."

      _ ->
        waiting_for(i, mine, m, name_of)
    end
  end

  @doc "Whether the member has scheduled the item's deletion, which leaving completes (REQ-201)."
  def scheduled_deletion?(mine), do: Enum.any?(mine, &(&1.change == :delete))

  defp waiting_for(i, mine, m, name_of) do
    owners = MapSet.new(i.owners)

    who =
      mine
      |> Enum.flat_map(fn p ->
        # every new owner agrees too (WI-086, CP-029)
        needed = Words.needed(p, %{i.id => %{owners: owners, joiners?: true}})

        needed |> MapSet.difference(MapSet.new(p.consents)) |> Enum.to_list()
      end)
      |> Enum.uniq()
      |> Words.people(m, "the others", name_of)

    "Waiting for #{who} to agree."
  end

  @doc "An item owned with others, who keep it when the member stops owning it."
  def owned_with_text(keepers, name_of \\ &Function.identity/1),
    do:
      "Owned with #{Words.people(keepers, nil, "No one", name_of)}, who will keep it. To own it again, you'd need #{if length(keepers) == 1, do: "their", else: "all their"} agreement."

  @doc "A sole owner's choice of giving an item to `name`, which waits for them to agree (every item since WI-086)."
  def give_label(_i, name), do: "Give it to #{name} (waits for #{name} to agree)"
end
