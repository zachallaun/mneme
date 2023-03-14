defmodule Mneme.Diff.Formatter do
  @moduledoc false

  alias Mneme.Diff.Zipper

  @re_newline ~r/\n|\r\n/

  @doc """
  Highlights the given code based on the instructions.
  """
  def highlight_lines(code, instructions) do
    lines = code |> Owl.Data.lines() |> Enum.reverse()
    [last_line | rest] = lines

    instructions
    |> denormalize_all()
    |> do_highlight(length(lines), last_line, rest)
    |> Enum.map(fn
      list when is_list(list) ->
        Enum.filter(list, &(Owl.Data.length(&1) > 0))

      line ->
        line
    end)
  end

  defp do_highlight(instructions, line_no, current_line, earlier_lines, line_acc \\ [], acc \\ [])

  defp do_highlight([], _, current_line, earlier_lines, line_acc, acc) do
    Enum.reverse(earlier_lines) ++ [[current_line | line_acc] | acc]
  end

  # no-content highlight
  defp do_highlight([{_, {{l, c}, {l, c}}} | rest], l, line, earlier, line_acc, acc) do
    do_highlight(rest, l, line, earlier, line_acc, acc)
  end

  # single-line highlight
  defp do_highlight([{op, {{l, c}, {l, c2}}} | rest], l, line, earlier, line_acc, acc) do
    {start_line, rest_line} = String.split_at(line, c2 - 1)
    {start_line, token} = String.split_at(start_line, c - 1)
    do_highlight(rest, l, start_line, earlier, [tag(token, op), rest_line | line_acc], acc)
  end

  # bottom of a multi-line highlight
  defp do_highlight(
         [{op, {{l, _}, {l2, c2}}} | _] = hl,
         l2,
         line,
         earlier,
         line_acc,
         acc
       )
       when l2 > l do
    {token, rest_line} = String.split_at(line, c2 - 1)
    lines = earlier |> Enum.take(l2 - l - 1) |> Enum.reverse() |> Enum.map(&tag(&1, op))
    [next | rest_earlier] = earlier |> Enum.drop(l2 - l - 1)
    acc = lines ++ [[tag(token, op), rest_line | line_acc] | acc]

    do_highlight(hl, l, next, rest_earlier, [], acc)
  end

  # top of a multi-line highlight
  defp do_highlight([{op, {{l, c}, _}} | rest], l, line, earlier, [], acc) do
    {start_line, token} = String.split_at(line, c - 1)
    do_highlight(rest, l, start_line, earlier, [tag(token, op)], acc)
  end

  defp do_highlight(instructions, l, line, [next | rest_earlier], line_acc, acc) do
    do_highlight(instructions, l - 1, next, rest_earlier, [], [[line | line_acc] | acc])
  end

  defp denormalize_all(instructions) do
    instructions
    |> Enum.flat_map(fn {op, type, zipper} ->
      denormalize(type, op, zipper |> Zipper.node(), zipper)
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp denormalize(:node, op, {:{}, tuple_meta, [left, right]} = node, _) do
    case tuple_meta do
      %{closing: _} ->
        [{op, bounds(node)}]

      _ ->
        {lc1, _} = bounds(left)
        {_, lc2} = bounds(right)
        [{op, {lc1, lc2}}]
    end
  end

  defp denormalize(:node, op, {:var, meta, var}, zipper) do
    var_bounds = bounds({:var, meta, var})
    {{l, c}, {l2, c2}} = var_bounds

    case zipper |> Zipper.up() |> Zipper.node() do
      {:__aliases__, _, _} ->
        case Zipper.right(zipper) do
          nil ->
            [{op, {{l, c - 1}, {l2, c2}}}]

          _ ->
            [{op, {{l, c}, {l2, c2 + 1}}}]
        end

      _ ->
        [{op, var_bounds}]
    end
  end

  defp denormalize(:node, _op, {{:., _, _}, _, []}, _zipper) do
    []
  end

  defp denormalize(:node, op, node, _zipper) do
    [{op, bounds(node)}]
  end

  defp denormalize(:delimiter, _op, {:%, _, _}, _), do: []

  defp denormalize(:delimiter, op, {:"[]", meta, _}, _) do
    denormalize_delimiter(op, meta, 1, 1)
  end

  defp denormalize(:delimiter, op, {:{}, meta, _}, _) do
    denormalize_delimiter(op, meta, 1, 1)
  end

  defp denormalize(:delimiter, op, {:%{}, meta, _}, zipper) do
    case zipper |> Zipper.up() |> Zipper.node() do
      {:%, %{line: l, column: c}, _} ->
        [{op, {{l, c}, {l, c + 1}}} | denormalize_delimiter(op, meta, 1, 1)]

      _ ->
        denormalize_delimiter(op, Map.update!(meta, :column, &(&1 - 1)), 2, 1)
    end
  end

  defp denormalize(
         :delimiter,
         op,
         {call, %{line: l, column: c, closing: %{line: l2, column: c2}}, _},
         _
       )
       when is_atom(call) do
    len = Macro.inspect_atom(:remote_call, call) |> String.length()
    [{op, {{l, c}, {l, c + len + 1}}}, {op, {{l2, c2}, {l2, c2 + 1}}}]
  end

  defp denormalize(
         :delimiter,
         op,
         {call, %{line: l, column: c}, _},
         _
       )
       when is_atom(call) do
    len = Macro.inspect_atom(:remote_call, call) |> String.length()
    [{op, {{l, c}, {l, c + len}}}]
  end

  defp denormalize(
         :delimiter,
         op,
         {{:., _, [left, right]}, %{closing: %{line: l2, column: c2}}, _},
         _
       ) do
    [{op, bounds({left, right})}, {op, {{l2, c2}, {l2, c2 + 1}}}]
  end

  defp denormalize(:delimiter, _op, {{:., _, _}, _, _}, _), do: []

  defp denormalize(:delimiter, op, {atom, %{line: l, column: c}, _}, _) when is_atom(atom) do
    len = Macro.inspect_atom(:remote_call, atom) |> String.length()
    [{op, {{l, c}, {l, c + len}}}]
  end

  defp denormalize(:delimiter, _op, {_, _}, _), do: []

  defp denormalize_delimiter(op, meta, start_len, end_len) do
    case meta do
      %{line: l, column: c, closing: %{line: l2, column: c2}} ->
        [{op, {{l, c}, {l, c + start_len}}}, {op, {{l2, c2}, {l2, c2 + end_len}}}]

      _ ->
        []
    end
  end

  # HACK: meta in args haven't been converted to maps, so we do it here
  defp bounds({_, list, _} = node) when is_list(list), do: node |> bounds()

  defp bounds({:%, %{line: l, column: c}, [_, map_node]}) do
    {_, closing_bound} = map_node |> bounds()
    {{l, c}, closing_bound}
  end

  defp bounds({:%{}, %{closing: %{line: l2, column: c2}, line: l, column: c}, _}) do
    {{l, c - 1}, {l2, c2 + 1}}
  end

  defp bounds({_, %{closing: %{line: l2, column: c2}, line: l, column: c}, _}) do
    {{l, c}, {l2, c2 + 1}}
  end

  defp bounds({_, %{token: token, line: l, column: c}, _}) do
    {{l, c}, {l, c + String.length(token)}}
  end

  defp bounds({:string, %{line: l, column: c, delimiter: ~s(")}, string}) do
    offset = 2 + String.length(string) + occurrences(string, ?")
    {{l, c}, {l, c + offset}}
  end

  defp bounds({:string, %{line: l, column: c, delimiter: ~s("""), indentation: indent}, string}) do
    n_lines = string |> String.replace_suffix("\n", "") |> String.split(@re_newline) |> length()
    {{l, c}, {l + n_lines + 1, indent + 4}}
  end

  defp bounds({:string, %{line: l, column: c}, string}) do
    {{l, c}, {l, c + String.length(string) - 1}}
  end

  defp bounds({:charlist, %{line: l, column: c, delimiter: "'"}, string}) do
    offset = 2 + String.length(string) + occurrences(string, ?')
    {{l, c}, {l, c + offset}}
  end

  defp bounds({:atom, %{format: :keyword, line: l, column: c}, atom}) do
    atom_bounds(:key, atom, l, c)
  end

  defp bounds({:atom, %{line: l, column: c}, atom}) do
    atom_bounds(:literal, atom, l, c)
  end

  defp bounds({:var, %{line: l, column: c}, atom}) do
    {{l, c}, {l, c + String.length(to_string(atom))}}
  end

  defp bounds({:__aliases__, %{line: l, column: c, last: %{line: l2, column: c2}}, vars}) do
    {:var, _, last_var} = List.last(vars)
    len = last_var |> to_string() |> String.length()
    {{l, c}, {l2, c2 + len}}
  end

  defp bounds({:^, %{line: l, column: c}, [var]}) do
    {_, end_bound} = var |> bounds()
    {{l, c}, end_bound}
  end

  defp bounds({:., %{line: l, column: c}, args}) do
    {_, end_bound} =
      case args do
        [inner] -> bounds(inner)
        [_, inner] -> bounds(inner)
      end

    {{l, c}, end_bound}
  end

  defp bounds({{:., _, _} = call, %{no_parens: true}, []}) do
    call |> bounds()
  end

  # TODO: handle multi-line using """/''' delimiters
  defp bounds({:"~", %{line: l, column: c, delimiter: del}, [_sigil, [string], modifiers]}) do
    {_, {l2, c2}} = bounds(string)
    del_length = String.length(del) * 2
    {{l, c}, {l2, c2 + del_length + length(modifiers)}}
  end

  defp bounds({:"~", _, _} = sigil) do
    raise ArgumentError, "bounds unimplemented for: #{inspect(sigil)}"
  end

  defp bounds({call, _, args}) when is_atom(call) and is_list(args) do
    [first | _] = args
    last = List.last(args)
    bounds({first, last})
  end

  defp bounds({left, right}) do
    {start_bound, _} = bounds(left)
    {_, end_bound} = bounds(right)

    {start_bound, end_bound}
  end

  defp bounds(unimplemented) do
    raise ArgumentError, "bounds unimplemented for: #{inspect(unimplemented)}"
  end

  defp atom_bounds(type, atom, l, c) when type in [:literal, :key, :remote_call] do
    len = Macro.inspect_atom(type, atom) |> String.length()
    {{l, c}, {l, c + len}}
  end

  defp tag(data, :ins), do: Owl.Data.tag(data, :green)
  defp tag(data, :del), do: Owl.Data.tag(data, :red)

  defp occurrences(string, char, acc \\ 0)
  defp occurrences(<<char, rest::binary>>, char, acc), do: occurrences(rest, char, acc + 1)
  defp occurrences(<<_, rest::binary>>, char, acc), do: occurrences(rest, char, acc)
  defp occurrences(<<>>, _char, acc), do: acc
end
