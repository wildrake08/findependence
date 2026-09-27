defmodule Findependence.Import do
  @moduledoc """
  CAP-009 bringing one's own record into a household (MEC-022).

  `check/1` takes an export as decoded JSON (string keys; `nil` or `:null` for null) and checks
  every field with the same rules as entering it by hand (REQ-157). It never creates an atom:
  strings become atoms only through the explicit tables below. Any problem refuses the whole
  file, with where and what for each problem found (at most 20).

  `apply/6` brings a checked file in as new entries owned by the member alone (REQ-156), through
  the same core functions the interface uses, so their rules apply again. Goals and retirement
  assumptions already set are kept. A fingerprint of the file is kept in the member's private
  record, and the same file is refused a second time (REQ-159).
  """

  alias Findependence.{Alignment, Balances, Household, Plans, Retirement}

  @max_problems 20
  @max_items 2_000
  @max_links 5_000
  @max_plans 100
  @max_steps 100
  @max_readings 500
  @max_text 200
  @max_ref 64
  @max_cents 100_000_000_000

  @frequency_names %{
    "one_off" => :one_off,
    "irregular" => :irregular,
    "weekly" => {:every, 1, :week},
    "biweekly" => {:every, 2, :week},
    "monthly" => {:every, 1, :month},
    "yearly" => {:every, 1, :year}
  }
  @units %{"week" => :week, "month" => :month, "year" => :year}
  @account_types Map.new(Balances.account_types(), &{Atom.to_string(&1), &1})
  @debt_types Map.new(Balances.debt_types(), &{Atom.to_string(&1), &1})
  @retirement_fields %{
    "birth_year" => :birth_year,
    "retire_age" => :retire_age,
    "return_bp" => :return_bp,
    "ss_monthly" => :ss_monthly,
    "target_monthly" => :target_monthly
  }

  @doc "Every atom the import record can contain, for decoders that must know them in advance."
  def format_atoms, do: [:imports, :imported]

  # ---------------------------------------------------------------------------
  # The file format (REQ-155): what `check/1` reads, written from `Exit.export/2`

  @doc """
  The export as JSON-ready data in format version 2: string keys, `:null` for nothing, atoms as
  strings, intervals as `{"every": n, "unit": u}`, and plan steps as objects. The interface adds
  each item's history in words.
  """
  def to_data(export) do
    %{
      "format" => "findependence-export",
      "version" => 2,
      "member" => to_string(export.member),
      "items" =>
        Enum.map(export.items, fn i ->
          %{
            "id" => to_string(i.id),
            "attrs" => Map.new(i.attrs, fn {k, v} -> {Atom.to_string(k), attr_data(k, v)} end),
            "owners" => Enum.map(i.owners, &to_string/1),
            "grantees" => Enum.map(i.grantees, &to_string/1),
            "readings" =>
              for r <- Map.get(i, :readings, []), is_map(r) do
                Map.new(r, fn {k, v} -> {Atom.to_string(k), json(v)} end)
              end
          }
        end),
      "links" =>
        Enum.map(export.links, fn {i, v} -> %{"item" => to_string(i), "value" => to_string(v)} end),
      "plans" =>
        Enum.map(Map.get(export, :plans, []), fn p ->
          %{"id" => to_string(p.id), "name" => p.name, "steps" => Enum.map(p.steps, &step_data/1)}
        end),
      "marks" =>
        Enum.map(Map.get(export, :marks, []), fn {i, j} ->
          %{"item" => to_string(i), "job" => to_string(j)}
        end),
      "goals" => goals_data(Map.get(export, :goals)),
      "retirement" => retirement_data(Map.get(export, :retirement))
    }
  end

  # a shared plan's steps are stored as %{n, step}
  defp attr_data(:steps, steps) when is_list(steps),
    do: Enum.map(steps, fn %{step: s} -> step_data(s) end)

  defp attr_data(_k, v), do: json(v)

  defp json(nil), do: :null
  defp json(v) when is_boolean(v), do: v
  defp json(v) when is_atom(v), do: Atom.to_string(v)
  defp json({:every, n, unit}), do: %{"every" => n, "unit" => Atom.to_string(unit)}
  defp json(v), do: v

  defp step_data({:switch_off, ids, from}),
    do: %{"kind" => "switch_off", "items" => Enum.map(ids, &to_string/1), "from" => from}

  defp step_data({:add, a, from}),
    do: %{
      "kind" => "add",
      "note" => a.note,
      "amount" => a.amount,
      "frequency" => json(a.frequency),
      "from" => from
    }

  defp step_data({:borrow, b, from}),
    do: %{
      "kind" => "borrow",
      "amount" => b.amount,
      "rate_bp" => b.rate_bp,
      "payment" => b.payment,
      "from" => from
    }

  defp goals_data(nil), do: %{"fund_months" => :null, "set_aside" => []}

  defp goals_data(g),
    do: %{
      "fund_months" => json(g.fund_months),
      "set_aside" =>
        Enum.map(g.set_aside, fn {v, bp} -> %{"value" => to_string(v), "rate_bp" => bp} end)
    }

  defp retirement_data(nil), do: %{"contributions" => []}

  defp retirement_data(r) do
    fields = for {k, f} <- @retirement_fields, into: %{}, do: {k, json(Map.get(r, f))}

    Map.put(
      fields,
      "contributions",
      Enum.map(r.contributions, fn {a, c} -> %{"account" => to_string(a), "cents" => c} end)
    )
  end

  # ---------------------------------------------------------------------------
  # Checking (REQ-157)

  @doc """
  `{:ok, bundle}` or `{:error, problems}`, each problem `{where, what}`: `where` is a path such as
  `"items[3].attrs.amount"`, `what` an atom the interface words.
  """
  def check(data) when is_map(data) do
    {version, p0} = version(data)

    if version == nil do
      {:error, p0}
    else
      data = if version == 1, do: legacy_nils(data), else: data
      {items, p1} = list(data, "items", "items", @max_items, &item/2, true)

      # references resolve to every entry with a valid id and kind, even one failing another check,
      # so a fault is reported once, at the entry, and not again at everything that refers to it
      refs = raw_refs(data["items"])
      dupes = items |> Enum.map(& &1.ref) |> duplicates()
      p2 = for r <- dupes, do: {"items", {:duplicate_id, r}}
      {links, p3} = list(data, "links", "links", @max_links, &link(&1, &2, refs), false)

      {personal, p4} =
        if version >= 2,
          do: personal(data, refs),
          else: extra_keys(data, ["member", "items", "links"], "")

      problems = p0 ++ p1 ++ p2 ++ p3 ++ p4

      if problems == [] do
        {:ok,
         Map.merge(
           %{
             version: version,
             items: Enum.reject(items, &(&1.kind == :shared_plan)),
             shared_plans: Enum.count(items, &(&1.kind == :shared_plan)),
             links: Enum.uniq(links)
           },
           personal
         )}
      else
        {:error, Enum.take(problems, @max_problems)}
      end
    end
  end

  def check(_), do: {:error, [{"", :not_an_export}]}

  defp raw_refs(items) when is_list(items) do
    for %{"id" => id, "attrs" => %{} = a} <- items,
        {:ok, r} <- [ref(id)],
        kind = raw_kind(a["kind"]),
        kind != nil,
        into: %{} do
      type = if kind == :account, do: @account_types[a["account_type"]]
      {r, %{kind: kind, attrs: %{kind: kind, account_type: type}}}
    end
  end

  defp raw_refs(_), do: %{}

  defp raw_kind(k) when k in [nil, :null], do: :money
  defp raw_kind("value"), do: :value
  defp raw_kind("account"), do: :account
  defp raw_kind("debt"), do: :debt
  defp raw_kind("plan"), do: :shared_plan
  defp raw_kind(_), do: nil

  defp duplicates(list),
    do:
      list |> Enum.frequencies() |> Enum.filter(fn {_, n} -> n > 1 end) |> Enum.map(&elem(&1, 0))

  # Files before version 2 were written by an encoder that turned a missing value into "nil".
  defp legacy_nils(%{"items" => items} = data) when is_list(items) do
    fix = fn
      %{"attrs" => %{} = a} = i ->
        %{i | "attrs" => Map.new(a, fn {k, v} -> {k, if(v == "nil", do: :null, else: v)} end)}

      i ->
        i
    end

    %{data | "items" => Enum.map(items, fix)}
  end

  defp legacy_nils(data), do: data

  # Version 2 names itself; files written before it have no format, only member, items, and links.
  defp version(data) do
    case {Map.get(data, "format"), Map.get(data, "version")} do
      {"findependence-export", 2} -> {2, []}
      {nil, nil} when is_map_key(data, "items") -> {1, []}
      {"findependence-export", _} -> {nil, [{"version", :unknown_version}]}
      _ -> {nil, [{"", :not_an_export}]}
    end
  end

  # A list field: each element checked by `fun.(element, where)`, returning {:ok, v} or problems.
  defp list(map, key, where, max, fun, required?) do
    case Map.get(map, key) do
      v when v in [nil, :null] and not required? -> {[], []}
      l when is_list(l) and length(l) > max -> {[], [{where, {:too_many, max}}]}
      l when is_list(l) -> collect(l, where, fun)
      nil -> {[], [{where, :missing}]}
      _ -> {[], [{where, :not_a_list}]}
    end
  end

  defp collect(l, where, fun) do
    {oks, problems} =
      l
      |> Enum.with_index()
      |> Enum.map(fn {e, i} -> fun.(e, "#{where}[#{i}]") end)
      |> Enum.split_with(&match?({:ok, _}, &1))

    {Enum.map(oks, &elem(&1, 1)), Enum.flat_map(problems, &elem(&1, 1))}
  end

  defp extra_keys(map, allowed, where) do
    case Map.keys(map) -- allowed do
      [] -> {%{}, []}
      extra -> {%{}, for(k <- Enum.sort(extra), do: {join(where, safe(k)), :unknown_field})}
    end
  end

  defp join("", k), do: k
  defp join(w, k), do: "#{w}.#{k}"

  # a key shown back to the member, never longer than a reference
  defp safe(k) when is_binary(k), do: String.slice(k, 0, @max_ref)
  defp safe(_), do: "?"

  defp null?(v), do: v in [nil, :null]

  defp text(v, max \\ @max_text) do
    with true <- is_binary(v) and String.valid?(v),
         t = String.trim(v),
         true <- t != "" and String.length(t) <= max do
      {:ok, t}
    else
      _ -> :error
    end
  end

  defp ref(v), do: text(v, @max_ref)

  defp cents(v, min \\ -@max_cents),
    do: if(is_integer(v) and v >= min and v <= @max_cents, do: {:ok, v}, else: :error)

  defp date(v) do
    with true <- is_binary(v),
         {:ok, d} <- Date.from_iso8601(v),
         do: {:ok, Date.to_iso8601(d)},
         else: (_ -> :error)
  end

  defp month(v), do: if(is_binary(v) and Plans.month?(v), do: {:ok, v}, else: :error)

  defp frequency(v) when is_binary(v) do
    case Map.fetch(@frequency_names, v) do
      {:ok, f} -> {:ok, f}
      :error -> :error
    end
  end

  defp frequency(%{"every" => n, "unit" => u} = f) when map_size(f) == 2 do
    if is_integer(n) and n in 1..99 and is_map_key(@units, u),
      do: {:ok, {:every, n, @units[u]}},
      else: :error
  end

  defp frequency(_), do: :error

  # Checks the fields of `map` against `spec`: [{key, required?, checker, what}]; unknown keys refused.
  defp fields(map, where, spec, ignored \\ []) do
    known = Enum.map(spec, &elem(&1, 0)) ++ ignored

    {vals, problems} =
      Enum.reduce(spec, {%{}, []}, fn {key, required?, check, what}, {acc, ps} ->
        v = Map.get(map, key)

        cond do
          null?(v) and required? ->
            {acc, ps ++ [{join(where, key), :missing}]}

          null?(v) ->
            {acc, ps}

          true ->
            case check.(v) do
              {:ok, x} -> {Map.put(acc, key, x), ps}
              :error -> {acc, ps ++ [{join(where, key), what}]}
            end
        end
      end)

    {_, extra} = extra_keys(map, known, where)
    {vals, problems ++ extra}
  end

  defp item(%{} = i, where) do
    {base, p0} =
      fields(i, where, [{"id", true, &ref/1, :invalid_id}], [
        "attrs",
        "owners",
        "grantees",
        "history",
        "readings"
      ])

    attrs = Map.get(i, "attrs")

    {kind, attrs, p1} =
      if is_map(attrs),
        do: attrs(attrs, "#{where}.attrs"),
        else: {nil, %{}, [{"#{where}.attrs", :missing}]}

    p2 =
      for k <- ["owners", "grantees", "history"],
          (v = Map.get(i, k)) != nil,
          not (is_list(v) and Enum.all?(v, &is_binary/1)),
          do: {"#{where}.#{k}", :not_a_list}

    {readings, p3} =
      case kind do
        k when k in [:account, :debt] ->
          list(i, "readings", "#{where}.readings", @max_readings, &reading(&1, &2, k), false)

        _ ->
          if Map.get(i, "readings") in [nil, :null, []],
            do: {[], []},
            else: {[], [{"#{where}.readings", :readings_not_allowed}]}
      end

    case p0 ++ p1 ++ p2 ++ p3 do
      [] -> {:ok, %{ref: base["id"], kind: kind, attrs: attrs, readings: readings}}
      ps -> {:error, ps}
    end
  end

  defp item(_, where), do: {:error, [{where, :not_an_object}]}

  defp attrs(a, where) do
    case Map.get(a, "kind") do
      k when k in [nil, :null] ->
        {v, ps} =
          fields(a, where, [
            {"note", true, &text/1, :invalid_text},
            {"amount", false, &cents/1, :invalid_amount},
            {"unit", false, &if(&1 == "cents", do: {:ok, :cents}, else: :error), :invalid_unit},
            {"frequency", false, &frequency/1, :invalid_frequency},
            {"on", false, &date/1, :invalid_date}
          ])

        ps =
          if v["amount"] != nil and v["unit"] == nil,
            do: ps ++ [{join(where, "unit"), :missing}],
            else: ps

        attrs =
          %{note: v["note"]}
          |> put_if(:amount, v["amount"])
          |> put_if(:unit, v["unit"])
          |> put_if(:frequency, v["frequency"])
          |> put_if(:on, v["on"])

        {:money, attrs, ps}

      "value" ->
        {v, ps} = fields(a, where, [{"label", true, &text/1, :invalid_text}], ["kind"])
        {:value, %{kind: :value, label: v["label"]}, ps}

      "account" ->
        {v, ps} =
          fields(
            a,
            where,
            [
              {"label", true, &text/1, :invalid_text},
              {"account_type", true, &table(&1, @account_types), :invalid_kind}
            ],
            ["kind"]
          )

        {:account, %{kind: :account, label: v["label"], account_type: v["account_type"]}, ps}

      "debt" ->
        {v, ps} =
          fields(
            a,
            where,
            [
              {"label", true, &text/1, :invalid_text},
              {"debt_type", true, &table(&1, @debt_types), :invalid_kind}
            ],
            ["kind"]
          )

        {:debt, %{kind: :debt, label: v["label"], debt_type: v["debt_type"]}, ps}

      # a shared plan was an agreement with others: counted, never brought in (REQ-156)
      "plan" ->
        {:shared_plan, %{}, []}

      _ ->
        {nil, %{}, [{join(where, "kind"), :invalid_kind}]}
    end
  end

  defp table(v, t), do: if(is_binary(v) and is_map_key(t, v), do: {:ok, t[v]}, else: :error)

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)

  defp reading(%{} = r, where, kind) do
    spec =
      [{"on", true, &date/1, :invalid_date}] ++
        if kind == :debt,
          do: [
            {"balance", true, &cents(&1, 0), :invalid_amount},
            {"rate_bp", true,
             &if(is_integer(&1) and &1 in 0..10_000, do: {:ok, &1}, else: :error), :invalid_rate},
            {"min_payment", true, &cents(&1, 0), :invalid_amount}
          ],
          else: [{"balance", true, &cents/1, :invalid_amount}]

    case fields(r, where, spec, ["seq", "by"]) do
      {v, []} -> {:ok, Map.new(v, fn {k, x} -> {reading_key(k), x} end)}
      {_, ps} -> {:error, ps}
    end
  end

  defp reading(_, where, _), do: {:error, [{where, :not_an_object}]}

  defp reading_key("on"), do: :on
  defp reading_key("balance"), do: :balance
  defp reading_key("rate_bp"), do: :rate_bp
  defp reading_key("min_payment"), do: :min_payment

  # A reference to an entry in this file, of one of `kinds`.
  defp refers(v, refs, kinds) do
    with {:ok, r} <- ref(v),
         %{kind: k} <- refs[r],
         true <- k in kinds,
         do: {:ok, r},
         else: (_ -> :error)
  end

  # a contribution goes only to a 401(k) or an IRA in this file
  defp retirement_ref(v, refs) do
    with {:ok, r} <- refers(v, refs, [:account]),
         true <- Balances.retirement?(%{attrs: refs[r].attrs}),
         do: {:ok, r},
         else: (_ -> :error)
  end

  defp link(%{} = l, where, refs) do
    case fields(l, where, [
           {"item", true, &refers(&1, refs, [:money]), :bad_reference},
           {"value", true, &refers(&1, refs, [:value]), :bad_reference}
         ]) do
      {v, []} -> {:ok, {v["item"], v["value"]}}
      {_, ps} -> {:error, ps}
    end
  end

  defp link(_, where, _), do: {:error, [{where, :not_an_object}]}

  defp personal(data, refs) do
    {_, p0} =
      extra_keys(
        data,
        [
          "format",
          "version",
          "member",
          "items",
          "links",
          "plans",
          "marks",
          "goals",
          "retirement"
        ],
        ""
      )

    {plans, p1} = list(data, "plans", "plans", @max_plans, &plan(&1, &2, refs), false)
    {marks, p2} = list(data, "marks", "marks", @max_links, &mark(&1, &2, refs), false)
    {goals, p3} = goals(Map.get(data, "goals"), refs)
    {retirement, p4} = retirement(Map.get(data, "retirement"), refs)

    {%{plans: plans, marks: Enum.uniq(marks), goals: goals, retirement: retirement},
     p0 ++ p1 ++ p2 ++ p3 ++ p4}
  end

  defp plan(%{} = p, where, refs) do
    {v, p0} = fields(p, where, [{"name", true, &text/1, :invalid_text}], ["id", "steps"])
    {steps, p1} = list(p, "steps", "#{where}.steps", @max_steps, &step(&1, &2, refs), true)

    case p0 ++ p1 do
      [] -> {:ok, %{name: v["name"], steps: steps}}
      ps -> {:error, ps}
    end
  end

  defp plan(_, where, _), do: {:error, [{where, :not_an_object}]}

  defp step(%{"kind" => "switch_off"} = s, where, refs) do
    items =
      case Map.get(s, "items") do
        l when is_list(l) and l != [] and length(l) <= @max_links ->
          rs = Enum.map(l, &refers(&1, refs, [:money]))

          if Enum.all?(rs, &match?({:ok, _}, &1)),
            do: {:ok, Enum.map(rs, &elem(&1, 1))},
            else: :error

        _ ->
          :error
      end

    case {fields(s, where, [{"from", true, &month/1, :invalid_month}], ["kind", "items"]), items} do
      {{v, []}, {:ok, ids}} -> {:ok, {:switch_off, ids, v["from"]}}
      {{_, ps}, :error} -> {:error, ps ++ [{"#{where}.items", :bad_reference}]}
      {{_, ps}, _} -> {:error, ps}
    end
  end

  defp step(%{"kind" => "add"} = s, where, _refs) do
    case fields(
           s,
           where,
           [
             {"note", true, &text/1, :invalid_text},
             {"amount", true, &if(&1 != 0, do: cents(&1), else: :error), :invalid_amount},
             {"frequency", true, &frequency/1, :invalid_frequency},
             {"from", true, &month/1, :invalid_month}
           ],
           ["kind"]
         ) do
      {v, []} ->
        {:ok,
         {:add, %{note: v["note"], amount: v["amount"], frequency: v["frequency"]}, v["from"]}}

      {_, ps} ->
        {:error, ps}
    end
  end

  defp step(%{"kind" => "borrow"} = s, where, _refs) do
    positive = &if is_integer(&1) and &1 > 0 and &1 <= @max_cents, do: {:ok, &1}, else: :error

    case fields(
           s,
           where,
           [
             {"amount", true, positive, :invalid_amount},
             {"rate_bp", true,
              &if(is_integer(&1) and &1 in 0..10_000, do: {:ok, &1}, else: :error),
              :invalid_rate},
             {"payment", true, positive, :invalid_amount},
             {"from", true, &month/1, :invalid_month}
           ],
           ["kind"]
         ) do
      {v, []} ->
        {:ok,
         {:borrow, %{amount: v["amount"], rate_bp: v["rate_bp"], payment: v["payment"]},
          v["from"]}}

      {_, ps} ->
        {:error, ps}
    end
  end

  defp step(_, where, _), do: {:error, [{where, :invalid_step}]}

  defp mark(%{} = m, where, refs) do
    case fields(m, where, [
           {"item", true, &refers(&1, refs, [:money]), :bad_reference},
           {"job", true, &refers(&1, refs, [:money]), :bad_reference}
         ]) do
      {v, []} -> {:ok, {v["item"], v["job"]}}
      {_, ps} -> {:error, ps}
    end
  end

  defp mark(_, where, _), do: {:error, [{where, :not_an_object}]}

  defp goals(g, _refs) when g in [nil, :null], do: {%{fund_months: nil, set_aside: []}, []}

  defp goals(%{} = g, refs) do
    {v, p0} =
      fields(
        g,
        "goals",
        [
          {"fund_months", false, &if(is_integer(&1) and &1 in 1..60, do: {:ok, &1}, else: :error),
           :invalid_goal}
        ],
        ["set_aside"]
      )

    {asides, p1} =
      list(
        g,
        "set_aside",
        "goals.set_aside",
        @max_links,
        fn a, w ->
          case a do
            %{} ->
              case fields(a, w, [
                     {"value", true, &refers(&1, refs, [:value]), :bad_reference},
                     {"rate_bp", true,
                      &if(is_integer(&1) and &1 in 1..10_000, do: {:ok, &1}, else: :error),
                      :invalid_rate}
                   ]) do
                {x, []} -> {:ok, {x["value"], x["rate_bp"]}}
                {_, ps} -> {:error, ps}
              end

            _ ->
              {:error, [{w, :not_an_object}]}
          end
        end,
        false
      )

    {%{fund_months: v["fund_months"], set_aside: asides}, p0 ++ p1}
  end

  defp goals(_, _), do: {%{fund_months: nil, set_aside: []}, [{"goals", :not_an_object}]}

  defp retirement(r, _refs) when r in [nil, :null], do: {%{contributions: []}, []}

  defp retirement(%{} = r, refs) do
    spec =
      for {k, f} <- @retirement_fields do
        {k, false, fn v -> if Retirement.valid?(f, v), do: {:ok, v}, else: :error end,
         :invalid_retirement}
      end

    {v, p0} = fields(r, "retirement", spec, ["contributions"])

    {contributions, p1} =
      list(
        r,
        "contributions",
        "retirement.contributions",
        @max_links,
        fn c, w ->
          case c do
            %{} ->
              case fields(c, w, [
                     {"account", true, &retirement_ref(&1, refs), :bad_reference},
                     {"cents", true,
                      &if(is_integer(&1) and &1 > 0 and &1 <= 100_000_000,
                        do: {:ok, &1},
                        else: :error
                      ), :invalid_amount}
                   ]) do
                {x, []} -> {:ok, {x["account"], x["cents"]}}
                {_, ps} -> {:error, ps}
              end

            _ ->
              {:error, [{w, :not_an_object}]}
          end
        end,
        false
      )

    fields = Map.new(v, fn {k, x} -> {@retirement_fields[k], x} end)
    {Map.put(fields, :contributions, contributions), p0 ++ p1}
  end

  defp retirement(_, _), do: {%{contributions: []}, [{"retirement", :not_an_object}]}

  # ---------------------------------------------------------------------------
  # Bringing in (REQ-156, REQ-159)

  @doc "The date the member brought in the file with this fingerprint, or nil."
  def imported_on(h, m, fingerprint),
    do: h |> Plans.goals(m) |> Map.get(:imports, %{}) |> Map.get(fingerprint)

  @doc """
  Brings a checked `bundle` in for member `m`: `new_id` gives a fresh id for each new entry;
  `fingerprint` identifies the file; `today` is recorded with it. Returns `{:ok, h, summary}`, or
  `{:error, {:already_imported, date}}`, or `{:error, reason}` if a core rule refuses an entry.
  """
  def apply(%Household{} = h, m, bundle, new_id, fingerprint, %Date{} = today) do
    if on = imported_on(h, m, fingerprint) do
      {:error, {:already_imported, on}}
    else
      ids = Map.new(bundle.items, &{&1.ref, new_id.()})

      result =
        {:ok, h}
        |> each(bundle.items, fn h, i -> bring_item(h, m, ids[i.ref], i) end)
        |> each(bundle.links, fn h, {i, v} -> Alignment.link(h, m, ids[i], ids[v]) end)
        |> each(Map.get(bundle, :plans, []), fn h, p -> bring_plan(h, m, new_id.(), p, ids) end)
        |> each(Map.get(bundle, :marks, []), fn h, {i, j} -> Plans.mark(h, m, ids[i], ids[j]) end)
        |> then(fn r -> bring_goals(r, m, Map.get(bundle, :goals), ids) end)
        |> then(fn r -> bring_retirement(r, m, Map.get(bundle, :retirement), ids) end)

      case result do
        {:ok, h} ->
          g = Plans.goals(h, m)
          imports = Map.put(Map.get(g, :imports, %{}), fingerprint, Date.to_iso8601(today))

          h = %{
            h
            | goals: Map.put(h.goals, m, Map.put(Map.get(h.goals, m, %{}), :imports, imports))
          }

          {:ok, h, summary(bundle)}

        error ->
          error
      end
    end
  end

  defp each({:ok, h}, list, fun) do
    Enum.reduce_while(list, {:ok, h}, fn x, {:ok, h} ->
      case fun.(h, x) do
        {:ok, h} -> {:cont, {:ok, h}}
        {:ok, h, _} -> {:cont, {:ok, h}}
        error -> {:halt, error}
      end
    end)
  end

  defp each(error, _list, _fun), do: error

  defp bring_item(h, m, id, %{attrs: attrs, readings: readings}) do
    with {:ok, h} <- Household.add_item(h, m, id, attrs, %{imported: true}) do
      each({:ok, h}, readings, fn h, r -> Balances.add_reading(h, m, id, r) end)
    end
  end

  defp bring_plan(h, m, pid, p, ids) do
    with {:ok, h} <- Plans.new_plan(h, m, pid, p.name) do
      each({:ok, h}, p.steps, fn h, step -> Plans.add_step(h, m, pid, remap(step, ids)) end)
    end
  end

  defp remap({:switch_off, refs, from}, ids), do: {:switch_off, Enum.map(refs, &ids[&1]), from}
  defp remap(step, _ids), do: step

  # only what the member hasn't set already
  defp bring_goals({:ok, h}, m, g, ids) when is_map(g) do
    current = Plans.goals(h, m)

    {:ok, h}
    |> then(fn r ->
      if current.fund_months == nil and g.fund_months,
        do: with({:ok, h} <- r, do: Plans.set_fund_goal(h, m, g.fund_months)),
        else: r
    end)
    |> each(g.set_aside, fn h, {v, bp} -> Plans.set_aside(h, m, ids[v], bp) end)
  end

  defp bring_goals(r, _m, _g, _ids), do: r

  defp bring_retirement({:ok, h}, m, r, ids) when is_map(r) do
    current = Retirement.settings(h, m)

    {:ok, h}
    |> each(Map.drop(r, [:contributions]) |> Enum.to_list(), fn h, {f, v} ->
      if current[f] == nil, do: Retirement.set(h, m, f, v), else: {:ok, h}
    end)
    |> each(r.contributions, fn h, {a, c} -> Retirement.set_contribution(h, m, ids[a], c) end)
  end

  defp bring_retirement(r, _m, _r, _ids), do: r

  @doc "What the bundle would bring in (REQ-158)."
  def summary(bundle) do
    by_kind = Enum.group_by(bundle.items, & &1.kind)

    names = fn k ->
      by_kind |> Map.get(k, []) |> Enum.map(&(&1.attrs[:note] || &1.attrs[:label]))
    end

    g = Map.get(bundle, :goals, %{fund_months: nil, set_aside: []})
    r = Map.get(bundle, :retirement, %{contributions: []})

    %{
      items: names.(:money),
      values: names.(:value),
      accounts: names.(:account),
      debts: names.(:debt),
      readings: bundle.items |> Enum.map(&length(&1.readings)) |> Enum.sum(),
      links: length(bundle.links),
      plans: bundle |> Map.get(:plans, []) |> Enum.map(& &1.name),
      marks: length(Map.get(bundle, :marks, [])),
      goals: if(g.fund_months, do: 1, else: 0) + length(g.set_aside),
      retirement: map_size(Map.drop(r, [:contributions])) + length(r.contributions),
      shared_plans: bundle.shared_plans
    }
  end
end
