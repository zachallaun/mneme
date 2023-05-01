defmodule Mneme.Assertion.PatternBuilder do
  @moduledoc false

  alias Mneme.Assertion.Pattern

  @doc """
  Builds pattern expressions from a runtime value.
  """
  @spec to_patterns(term(), context :: map()) :: [Pattern.t(), ...]
  def to_patterns(value, context) do
    context = Map.put(context, :keysets, get_keysets(context.original_pattern))
    patterns = do_to_patterns(value, context)

    case fetch_pinned(value, context) do
      {:ok, pin} -> [Pattern.new(pin) | patterns]
      :error -> patterns
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

  defp do_to_patterns(int, context) when is_integer(int) do
    {:__block__, with_meta([token: inspect(int)], context), [int]}
    |> Pattern.new()
    |> List.wrap()
  end

  defp do_to_patterns(value, _context) when is_atom(value) or is_float(value) do
    [Pattern.new(value)]
  end

  defp do_to_patterns(string, context) when is_binary(string) do
    cond do
      !String.printable?(string) ->
        [Pattern.new({:<<>>, [], String.to_charlist(string)})]

      String.contains?(string, "\n") ->
        [string_pattern(string, context), heredoc_pattern(string, context)]

      true ->
        [string_pattern(string, context)]
    end
  end

  defp do_to_patterns([], _), do: [Pattern.new([])]

  defp do_to_patterns(list, context) when is_list(list) do
    patterns = enum_to_patterns(list, context)

    if List.ascii_printable?(list) do
      patterns ++ [Pattern.new(list)]
    else
      patterns
    end
  end

  defp do_to_patterns(tuple, context) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> enum_to_patterns(context)
    |> Enum.map(&to_tuple_pattern(&1, context))
  end

  for {var_name, guard} <- [ref: :is_reference, pid: :is_pid, port: :is_port] do
    defp do_to_patterns(value, context) when unquote(guard)(value) do
      [guard_pattern(unquote(var_name), unquote(guard), value, context)]
    end
  end

  for module <- [Range, Regex, DateTime, NaiveDateTime, Date, Time] do
    defp do_to_patterns(%unquote(module){} = value, context) do
      {call, meta, args} = value |> inspect() |> Code.string_to_quoted!()
      [Pattern.new({call, with_meta(meta, context), args})]
    end
  end

  defp do_to_patterns(%URI{} = uri, context) do
    struct_to_patterns(URI, Map.delete(uri, :authority), context, [])
  end

  defp do_to_patterns(%struct{} = value, context) do
    if ecto_schema?(struct) do
      {value, notes} = prepare_ecto_struct(value)
      struct_to_patterns(struct, value, context, notes)
    else
      struct_to_patterns(struct, value, context, [])
    end
  end

  defp do_to_patterns(%{} = map, context) when map_size(map) == 0 do
    [map_pattern([], context)]
  end

  defp do_to_patterns(%{} = map, context) do
    sub_maps =
      for keyset <- context.keysets,
          sub_map = Map.take(map, keyset),
          map_size(sub_map) > 0 && map != sub_map do
        sub_map
      end

    patterns =
      for map <- sub_maps ++ [map],
          enum_pattern <- enum_to_patterns(map, context) do
        to_map_pattern(enum_pattern, context)
      end

    [map_pattern([], context) | patterns]
  end

  defp struct_to_patterns(struct, map, context, extra_notes) do
    defaults = struct.__struct__()

    map
    |> Map.filter(fn {k, v} -> v != Map.get(defaults, k) end)
    |> to_patterns(context)
    |> Enum.map(&to_struct_pattern(struct, &1, context, extra_notes))
  end

  defp enum_to_patterns(values, context) do
    values
    |> Enum.map(&to_patterns(&1, context))
    |> unzip_combine(context)
  end

  defp unzip_combine(nested_patterns, context, acc \\ []) do
    if last_pattern?(nested_patterns) do
      {patterns, _} = combine_and_pop(nested_patterns, context)
      Enum.reverse([patterns | acc])
    else
      {patterns, rest} = combine_and_pop(nested_patterns, context)
      unzip_combine(rest, context, [patterns | acc])
    end
  end

  defp last_pattern?(nested_patterns) do
    Enum.all?(nested_patterns, fn
      [_] -> true
      _ -> false
    end)
  end

  defp combine_and_pop(nested_patterns, context) do
    {patterns, rest_patterns} =
      nested_patterns
      |> Enum.map(&pop_pattern/1)
      |> Enum.unzip()

    {combine_patterns(patterns, context), rest_patterns}
  end

  defp pop_pattern([current, next | rest]), do: {current, [next | rest]}
  defp pop_pattern([current]), do: {current, [current]}

  defp combine_patterns(patterns, context) do
    {exprs, {guard, notes}} =
      Enum.map_reduce(
        patterns,
        {nil, []},
        fn %Pattern{expr: expr, guard: g1, notes: n1}, {g2, n2} ->
          {expr, {combine_guards(g1, g2, context), n1 ++ n2}}
        end
      )

    Pattern.new(exprs, guard: guard, notes: notes)
  end

  defp combine_guards(nil, guard, _context), do: guard
  defp combine_guards(guard, nil, _context), do: guard
  defp combine_guards(g1, g2, context), do: {:and, with_meta(context), [g2, g1]}

  defp guard_pattern(name, guard, value, context) do
    var = make_var(name, context)

    Pattern.new(var,
      guard: {guard, with_meta(context), [var]},
      notes: ["Using guard for non-serializable value `#{inspect(value)}`"]
    )
  end

  defp make_var(name, context) do
    {name, with_meta(context), nil}
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
end
