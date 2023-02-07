defprotocol Mneme.Serializer do
  @moduledoc false

  @fallback_to_any true

  @doc """
  Generates ASTs that can be used to assert a match of the given value.

  Must return `{match_expression, guard_expression}`, where the first
  will be used in a `=` match, and the second will be a secondary
  assertion with access to any bindings produced by the match.

  Note that `guard_expression` can be `nil`, in which case the guard
  check will not occur.
  """
  @spec to_pattern(t, keyword()) :: {Macro.t(), Macro.t() | nil}
  def to_pattern(value, context)
end

defimpl Mneme.Serializer, for: Any do
  def to_pattern(value, _context)
      when is_atom(value) or is_integer(value) or is_float(value) do
    {value, nil}
  end

  def to_pattern(string, _context) when is_binary(string) do
    if String.contains?(string, "\n") do
      {{:__block__, [delimiter: ~S(""")], [format_for_heredoc(string)]}, nil}
    else
      {string, nil}
    end
  end

  def to_pattern(list, context) when is_list(list) do
    enum_to_pattern(list, context)
  end

  def to_pattern({a, b}, context) do
    case {Mneme.Serializer.to_pattern(a, context), Mneme.Serializer.to_pattern(b, context)} do
      {{expr1, nil}, {expr2, nil}} -> {{expr1, expr2}, nil}
      {{expr1, guard}, {expr2, nil}} -> {{expr1, expr2}, guard}
      {{expr1, nil}, {expr2, guard}} -> {{expr1, expr2}, guard}
      {{expr1, guard1}, {expr2, guard2}} -> {{expr1, expr2}, {:and, [], [guard1, guard2]}}
    end
  end

  def to_pattern(tuple, context) when is_tuple(tuple) do
    values = Tuple.to_list(tuple)
    {value_matches, guard} = enum_to_pattern(values, context)
    {{:{}, [], value_matches}, guard}
  end

  for {var_name, guard} <- [ref: :is_reference, pid: :is_pid, port: :is_port] do
    def to_pattern(value, context) when unquote(guard)(value) do
      case fetch_pinned(value, context[:binding]) do
        {:ok, pin} -> {pin, nil}
        :error -> guard(unquote(var_name), unquote(guard))
      end
    end
  end

  for module <- [DateTime, NaiveDateTime, Date, Time] do
    def to_pattern(%unquote(module){} = value, context) do
      case fetch_pinned(value, context[:binding]) do
        {:ok, pin} -> {pin, nil}
        :error -> {value |> inspect() |> Code.string_to_quoted!(), nil}
      end
    end
  end

  def to_pattern(%URI{} = uri, context) do
    struct_to_pattern(URI, Map.delete(uri, :authority), context)
  end

  def to_pattern(%struct{} = value, context) do
    struct_to_pattern(struct, value, context)
  end

  def to_pattern(%{} = map, context) do
    {tuples, guard} = enum_to_pattern(map, context)
    {{:%{}, [], tuples}, guard}
  end

  defp struct_to_pattern(struct, map, context) do
    {aliased, _} =
      context
      |> Map.get(:aliases, [])
      |> List.keyfind(struct, 1, {struct, struct})

    aliases = aliased |> Module.split() |> Enum.map(&String.to_atom/1)
    empty = struct.__struct__()

    {map_expr, guard} =
      map
      |> Map.filter(fn {k, v} -> v != Map.get(empty, k) end)
      |> Mneme.Serializer.to_pattern(context)

    {{:%, [], [{:__aliases__, [], aliases}, map_expr]}, guard}
  end

  defp format_for_heredoc(string) when is_binary(string) do
    if String.ends_with?(string, "\n") do
      string
    else
      string <> "\\\n"
    end
  end

  defp fetch_pinned(value, binding) do
    case List.keyfind(binding || [], value, 1) do
      {name, ^value} -> {:ok, {:^, [], [{name, [], nil}]}}
      _ -> :error
    end
  end

  defp enum_to_pattern(values, context) do
    Enum.map_reduce(values, nil, fn value, guard ->
      case {guard, Mneme.Serializer.to_pattern(value, context)} do
        {nil, {expr, guard}} -> {expr, guard}
        {guard, {expr, nil}} -> {expr, guard}
        {guard1, {expr, guard2}} -> {expr, {:and, [], [guard1, guard2]}}
      end
    end)
  end

  defp guard(name, guard) do
    var = {name, [], nil}
    {var, {guard, [], [var]}}
  end
end
