defmodule Mneme.Assertion.PatternBuilder do
  @moduledoc false

  alias Mneme.Assertion.Pattern

  @doc """
  Builds pattern expressions from a runtime value.
  """
  @spec to_patterns(term(), Mneme.Assertion.context()) :: [Pattern.t(), ...]
  def to_patterns(value, context) do
    context =
      context
      |> Map.take([:line, :aliases, :binding, :original_pattern])
      |> Map.put_new(:aliases, [])
      |> Map.put_new(:binding, [])
      |> Map.put(:keysets, get_keysets(context.original_pattern))

    {patterns, _vars} = to_patterns(value, context, [])
    patterns
  end

  defp to_patterns(value, context, vars) do
    {patterns, vars} = do_to_patterns(value, context, vars)

    case fetch_pinned(value, context) do
      {:ok, pin} -> {[Pattern.new(pin) | patterns], vars}
      :error -> {patterns, vars}
    end
  end

  # Keysets are the lists of keys being matched in any map patterns. We
  # extract them upfront so that map pattern generation can create
  # patterns for those subsets as well when applicable.
  defp get_keysets(pattern) do
    {_, keysets} =
      Macro.prewalk(pattern, [], fn
        {:%{}, _, [_ | _] = kvs} = quoted, keysets ->
          {quoted, [Enum.map(kvs, &elem(&1, 0)) | keysets]}

        quoted, keysets ->
          {quoted, keysets}
      end)

    keysets
  end

  defp with_meta(meta \\ [], context) do
    Keyword.merge([line: context[:line]], meta)
  end

  defp fetch_pinned(value, context) when value not in [true, false, nil] do
    case List.keyfind(context[:binding] || [], value, 1) do
      {name, ^value} -> {:ok, {:^, with_meta(context), [make_var(name, context)]}}
      _ -> :error
    end
  end

  defp fetch_pinned(_, _), do: :error

  @spec do_to_patterns(term(), map(), [atom()]) :: {[Pattern.t(), ...], [atom()]}
  defp do_to_patterns(value, context, vars)

  defp do_to_patterns(int, context, vars) when is_integer(int) do
    pattern = Pattern.new({:__block__, with_meta([token: inspect(int)], context), [int]})
    {[pattern], vars}
  end

  defp do_to_patterns(value, _context, vars) when is_atom(value) or is_float(value) do
    {[Pattern.new(value)], vars}
  end

  defp do_to_patterns(string, context, vars) when is_binary(string) do
    patterns =
      cond do
        !String.printable?(string) ->
          [Pattern.new({:<<>>, [], :erlang.binary_to_list(string)})]

        String.contains?(string, "\n") ->
          [string_pattern(string, context), heredoc_pattern(string, context)]

        true ->
          [string_pattern(string, context)]
      end

    {patterns, vars}
  end

  defp do_to_patterns([], _, vars), do: {[Pattern.new([])], vars}

  defp do_to_patterns(list, context, vars) when is_list(list) do
    {patterns, vars} = enum_to_patterns(list, context, vars)

    if List.ascii_printable?(list) do
      {patterns ++ [charlist_pattern(list, context)], vars}
    else
      {patterns, vars}
    end
  end

  defp do_to_patterns(tuple, context, vars) when is_tuple(tuple) do
    {patterns, vars} =
      tuple
      |> Tuple.to_list()
      |> enum_to_patterns(context, vars)

    {Enum.map(patterns, &to_tuple_pattern(&1, context)), vars}
  end

  for {var_name, guard} <- [ref: :is_reference, pid: :is_pid, port: :is_port, fun: :is_function] do
    defp do_to_patterns(value, context, vars) when unquote(guard)(value) do
      {pattern, vars} = guard_pattern(unquote(var_name), unquote(guard), value, context, vars)
      {[pattern], vars}
    end
  end

  for module <- [Range, Regex, DateTime, NaiveDateTime, Date, Time] do
    defp do_to_patterns(%unquote(module){} = value, context, vars) do
      {call, meta, args} = value |> inspect() |> Code.string_to_quoted!()
      pattern = Pattern.new({call, with_meta(meta, context), args})
      {[pattern], vars}
    end
  end

  defp do_to_patterns(%URI{} = uri, context, vars) do
    struct_to_patterns(URI, Map.delete(uri, :authority), context, vars, [])
  end

  defp do_to_patterns(%MapSet{} = set, context, vars) do
    struct_to_patterns(MapSet, set, context, vars, [
      "MapSets do not serialize well, consider transforming to a list using `MapSet.to_list/1`"
    ])
  end

  defp do_to_patterns(%struct{} = value, context, vars) do
    if ecto_schema?(struct) do
      {value, notes} = prepare_ecto_struct(value)
      struct_to_patterns(struct, value, context, vars, notes)
    else
      struct_to_patterns(struct, value, context, vars, [])
    end
  end

  defp do_to_patterns(%{} = map, context, vars) when map_size(map) == 0 do
    {[map_pattern([], context)], vars}
  end

  defp do_to_patterns(%{} = map, context, vars) do
    sub_maps =
      for keyset <- context.keysets,
          sub_map = Map.take(map, keyset),
          map_size(sub_map) > 0 && map != sub_map do
        sub_map
      end

    {patterns, vars} =
      (sub_maps ++ [map])
      |> Enum.flat_map_reduce(vars, fn map, vars ->
        {patterns, vars} =
          map
          |> Enum.sort_by(&elem(&1, 0))
          |> enum_to_patterns(context, vars)

        {Enum.map(patterns, &to_map_pattern(&1, context)), vars}
      end)

    {[map_pattern([], context) | patterns], vars}
  end

  defp struct_to_patterns(struct, map, context, vars, extra_notes) do
    defaults = struct.__struct__()

    map
    |> Map.filter(fn {k, v} -> v != Map.get(defaults, k) end)
    |> to_patterns(context, vars)
    |> then(fn {patterns, vars} ->
      struct_patterns = Enum.map(patterns, &to_struct_pattern(struct, &1, context, extra_notes))
      {struct_patterns, vars}
    end)
  end

  defp enum_to_patterns(values, context, vars) do
    {patterns, vars} = Enum.map_reduce(values, vars, &to_patterns(&1, context, &2))
    {unzip_combine(patterns), vars}
  end

  defp unzip_combine(nested_patterns, acc \\ []) do
    if last_pattern?(nested_patterns) do
      {patterns, _} = combine_and_pop(nested_patterns)
      Enum.reverse([patterns | acc])
    else
      {patterns, rest} = combine_and_pop(nested_patterns)
      unzip_combine(rest, [patterns | acc])
    end
  end

  defp last_pattern?(nested_patterns) do
    Enum.all?(nested_patterns, fn
      [_] -> true
      _ -> false
    end)
  end

  defp combine_and_pop(nested_patterns) do
    {patterns, rest_patterns} =
      nested_patterns
      |> Enum.map(&pop_pattern/1)
      |> Enum.unzip()

    {Pattern.combine(patterns), rest_patterns}
  end

  defp pop_pattern([current, next | rest]), do: {current, [next | rest]}
  defp pop_pattern([current]), do: {current, [current]}

  defp guard_pattern(name, guard, value, context, vars) do
    if existing = List.keyfind(vars, value, 1) do
      {var, _} = existing
      {Pattern.new(make_var(var, context)), vars}
    else
      {var_name, _, _} = var = make_unique_var(name, context, vars)

      guard =
        if is_function(value) do
          {:arity, arity} = Function.info(value, :arity)
          {guard, with_meta(context), [var, arity]}
        else
          {guard, with_meta(context), [var]}
        end

      pattern =
        Pattern.new(var,
          guard: guard,
          notes: ["Using guard for non-serializable value `#{inspect(value)}`"]
        )

      {pattern, [{var_name, value} | vars]}
    end
  end

  defp to_tuple_pattern(%Pattern{expr: [e1, e2]} = pattern, _context) do
    %{pattern | expr: {e1, e2}}
  end

  defp to_tuple_pattern(%Pattern{expr: exprs} = pattern, context) do
    %{pattern | expr: {:{}, with_meta(context), exprs}}
  end

  defp to_map_pattern(%Pattern{expr: tuples} = pattern, context) do
    %{pattern | expr: map_pattern(tuples, context).expr}
  end

  defp to_struct_pattern(struct, map_pattern, context, extra_notes) do
    {aliased, _} =
      context
      |> Map.get(:aliases, [])
      |> List.keyfind(struct, 1, {struct, struct})

    aliases = aliased |> Module.split() |> Enum.map(&String.to_atom/1)

    {:%, with_meta(context), [{:__aliases__, with_meta(context), aliases}, map_pattern.expr]}
    |> Pattern.new(guard: map_pattern.guard, notes: extra_notes ++ map_pattern.notes)
  end

  defp ecto_schema?(module) do
    function_exported?(module, :__schema__, 1)
  end

  defp prepare_ecto_struct(%schema{} = struct) do
    notes = ["Patterns for Ecto structs exclude primary keys, association keys, and meta fields"]

    primary_keys = schema.__schema__(:primary_key)
    autogenerated_fields = get_autogenerated_fields(schema)

    association_keys =
      for assoc <- schema.__schema__(:associations),
          %{owner_key: key} = schema.__schema__(:association, assoc) do
        key
      end

    drop_fields =
      Enum.concat([
        primary_keys,
        autogenerated_fields,
        association_keys,
        [:__meta__]
      ])

    {Map.drop(struct, drop_fields), notes}
  end

  # The Schema.__schema__(:autogenerate_fields) call was introduced in
  # Ecto v3.10.0, so we rely on an undocumented call using :autogenerate
  # for versions prior.
  ecto_supports_autogenerate_fields? =
    with {:ok, charlist} <- :application.get_key(:ecto, :vsn),
         {:ok, version} <- Version.parse(List.to_string(charlist)) do
      Version.match?(version, ">= 3.10.0")
    else
      _ -> false
    end

  if ecto_supports_autogenerate_fields? do
    def get_autogenerated_fields(schema) do
      schema.__schema__(:autogenerate_fields)
    end
  else
    def get_autogenerated_fields(schema) do
      :autogenerate
      |> schema.__schema__()
      |> Enum.flat_map(&elem(&1, 0))
    end
  end

  defp map_pattern(tuples, context) do
    Pattern.new({:%{}, with_meta(context), tuples})
  end

  defp string_pattern(string, context) do
    Pattern.new({:__block__, with_meta([delimiter: ~S(")], context), [escape(string)]})
  end

  defp charlist_pattern(charlist, context) do
    Pattern.new(
      {:sigil_c, with_meta([delimiter: ~S(")], context),
       [{:<<>>, [], [List.to_string(charlist)]}, []]}
    )
  end

  defp heredoc_pattern(string, context) do
    Pattern.new(
      {:__block__, with_meta([delimiter: ~S(""")], context),
       [string |> escape() |> format_for_heredoc()]}
    )
  end

  defp format_for_heredoc(string) when is_binary(string) do
    if String.ends_with?(string, "\n") do
      string
    else
      string <> "\\\n"
    end
  end

  defp escape(string) when is_binary(string) do
    String.replace(string, "\\", "\\\\")
  end

  defp make_var(name, context) do
    {name, with_meta(context), nil}
  end

  defp make_unique_var(name, context, vars) do
    vars = Keyword.keys(context[:binding] ++ vars)
    name = get_unique_name(name, vars)
    make_var(name, context)
  end

  defp get_unique_name(name, var_names) do
    if(name in var_names, do: get_unique_name(name, var_names, 1), else: name)
  end

  defp get_unique_name(name, var_names, i) do
    name_i = :"#{name}#{i}"
    if(name_i in var_names, do: get_unique_name(name, var_names, i + 1), else: name_i)
  end
end
