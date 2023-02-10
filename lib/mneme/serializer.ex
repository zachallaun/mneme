defmodule Mneme.Serializer do
  @moduledoc false

  @typedoc """
  Represents a possible pattern that would match a runtime value.
  """
  @type pattern :: {match_expression, guard_expression, notes}

  @type match_expression :: Macro.t()
  @type guard_expression :: Macro.t() | nil
  @type notes :: [binary()]

  @doc """
  Converts `value` into an AST that could be used to match that value.

  The second `context` argument is a map containing information about
  the context in which the expressions will be evaluated. It contains:

    * `:binding` - a keyword list of variables/values present in the
      calling environment

  Must return a three element tuple of the form:

      {[shrunk_pattern, ...], default_pattern, [expanded_pattern, ...]}

  Where each pattern is of type `t:pattern/0`.
  """
  @callback to_patterns(value :: any(), context :: map()) :: {[pattern], pattern, [pattern]}

  @doc """
  Default implementation of `c:to_pattern`.
  """
  def to_patterns(value, context) do
    {shrunk, default, expanded} = do_to_patterns(value, context)

    case fetch_pinned(value, context) do
      {:ok, pin} -> {shrunk, {pin, nil, []}, [default | expanded]}
      :error -> {shrunk, default, expanded}
    end
  end

  defp with_meta(meta \\ [], context) do
    Keyword.merge([line: context[:line]], meta)
  end

  defp fetch_pinned(value, context) do
    case List.keyfind(context[:binding] || [], value, 1) do
      {name, ^value} -> {:ok, {:^, with_meta(context), [make_var(name, context)]}}
      _ -> :error
    end
  end

  defp do_to_patterns(value, _context)
       when is_atom(value) or is_integer(value) or is_float(value) do
    pattern = {value, nil, []}
    {[], pattern, []}
  end

  defp do_to_patterns(string, context) when is_binary(string) do
    pattern =
      if String.contains?(string, "\n") do
        {{:__block__, with_meta([delimiter: ~S(""")], context), [format_for_heredoc(string)]},
         nil, []}
      else
        {string, nil, []}
      end

    {[], pattern, []}
  end

  defp do_to_patterns(list, context) when is_list(list) do
    enum_to_patterns(list, context)
  end

  defp do_to_patterns(tuple, context) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> enum_to_patterns(context)
    |> transform_patterns(&tuple_pattern/2, context)
  end

  for {var_name, guard} <- [ref: :is_reference, pid: :is_pid, port: :is_port] do
    defp do_to_patterns(value, context) when unquote(guard)(value) do
      guard_non_serializable(unquote(var_name), unquote(guard), value, context)
    end
  end

  for module <- [DateTime, NaiveDateTime, Date, Time] do
    defp do_to_patterns(%unquote(module){} = value, _context) do
      pattern = {value |> inspect() |> Code.string_to_quoted!(), nil, []}
      {[], pattern, []}
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

  defp do_to_patterns(map, context) when is_map(map) do
    empty_map_pattern = map_pattern({[], nil, []}, context)

    {shrunk, default, expanded} =
      map
      |> enum_to_patterns(context)
      |> transform_patterns(&map_pattern/2, context)

    {[empty_map_pattern | shrunk], default, expanded}
  end

  defp struct_to_patterns(struct, map, context, extra_notes) do
    empty_map_pattern = map_pattern({[], nil, []}, context)
    empty_struct_pattern = struct_pattern(struct, empty_map_pattern, context)

    empty = struct.__struct__()

    {shrunk, default, expanded} =
      map
      |> Map.filter(fn {k, v} -> v != Map.get(empty, k) end)
      |> Mneme.Serializer.to_patterns(context)
      |> transform_patterns(&struct_pattern(struct, &1, &2, extra_notes), context)

    {[empty_struct_pattern | shrunk], default, expanded}
  end

  defp struct_pattern(struct, {map_expr, guard, notes}, context, extra_notes \\ []) do
    {aliased, _} =
      context
      |> Map.get(:aliases, [])
      |> List.keyfind(struct, 1, {struct, struct})

    aliases = aliased |> Module.split() |> Enum.map(&String.to_atom/1)

    {{:%, with_meta(context), [{:__aliases__, with_meta(context), aliases}, map_expr]}, guard,
     extra_notes ++ notes}
  end

  defp format_for_heredoc(string) when is_binary(string) do
    if String.ends_with?(string, "\n") do
      string
    else
      string <> "\\\n"
    end
  end

  defp enum_to_patterns(values, context) do
    nested_patterns = Enum.map(values, &Mneme.Serializer.to_patterns(&1, context))
    shrunk = combine_until(&all_shrunk?/1, &shrink_and_get/1, nested_patterns, context)
    expanded = combine_until(&all_expanded?/1, &expand_and_get/1, nested_patterns, context)
    patterns = nested_patterns |> Enum.map(&elem(&1, 1)) |> combine_patterns(context)

    {shrunk, patterns, expanded}
  end

  defp combine_patterns(patterns, context) do
    {exprs, {guard, notes}} =
      Enum.map_reduce(patterns, {nil, []}, fn {expr, g1, n1}, {g2, n2} ->
        {expr, {combine_guards(g1, g2, context), n1 ++ n2}}
      end)

    {exprs, guard, notes}
  end

  defp combine_until(check, next, patterns, context, acc \\ []) do
    if check.(patterns) do
      Enum.reverse(acc)
    else
      {batch, rest_patterns} =
        patterns
        |> Enum.map(next)
        |> Enum.unzip()

      combined = combine_patterns(batch, context)

      combine_until(check, next, rest_patterns, context, [combined | acc])
    end
  end

  defp shrink_and_get({[next | rest], current, expanded}) do
    {next, {rest, next, [current | expanded]}}
  end

  defp shrink_and_get({[], current, expanded}) do
    {current, {[], current, expanded}}
  end

  defp expand_and_get({shrunk, current, [next | rest]}) do
    {next, {[current | shrunk], next, rest}}
  end

  defp expand_and_get({shrunk, current, []}) do
    {current, {shrunk, current, []}}
  end

  defp all_shrunk?(patterns) do
    Enum.all?(patterns, fn
      {[], _, _} -> true
      _ -> false
    end)
  end

  defp all_expanded?(patterns) do
    Enum.all?(patterns, fn
      {_, _, []} -> true
      _ -> false
    end)
  end

  defp combine_guards(nil, guard, _context), do: guard
  defp combine_guards(guard, nil, _context), do: guard
  defp combine_guards(g1, g2, context), do: {:and, with_meta(context), [g2, g1]}

  defp guard_non_serializable(name, guard, value, context) do
    var = make_var(name, context)

    pattern =
      {var, {guard, with_meta(context), [var]},
       ["Using guard for non-serializable value `#{inspect(value)}`"]}

    {[], pattern, []}
  end

  defp make_var(name, context) do
    {name, with_meta(context), nil}
  end

  defp transform_patterns({shrunk, default, expanded}, transform, context) do
    transformed_shrunk = Enum.map(shrunk, &transform.(&1, context))
    transformed_expanded = Enum.map(expanded, &transform.(&1, context))

    {transformed_shrunk, transform.(default, context), transformed_expanded}
  end

  defp tuple_pattern({[e1, e2], guard, notes}, _context) do
    {{e1, e2}, guard, notes}
  end

  defp tuple_pattern({exprs, guard, notes}, context) do
    {{:{}, with_meta(context), exprs}, guard, notes}
  end

  defp map_pattern({tuples, guard, notes}, context) do
    {{:%{}, with_meta(context), tuples}, guard, notes}
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

  # The Schema.__schema__(:autogenerate_fields) call was introduced after
  # Ecto v3.9.4, so we rely on an undocumented call using :autogenerate
  # for versions prior to that.
  ecto_supports_autogenerate_fields? =
    with {:ok, charlist} <- :application.get_key(:ecto, :vsn),
         {:ok, version} <- Version.parse(List.to_string(charlist)) do
      Version.compare(version, "3.9.4") == :gt
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
end
