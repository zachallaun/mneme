defmodule Mneme.Diff.Formatter do
  @moduledoc false

  alias Mneme.Diff.Zipper

  @doc """
  Highlights the given code based on the instructions.
  """
  def highlight_lines(code, instructions) do
    lines = code |> Owl.Data.lines() |> Enum.reverse()
    [last_line | rest] = lines

    instructions
    |> denormalize_all()
    |> do_highlight(length(lines), last_line, rest)
  end

  defp do_highlight(instructions, line_no, current_line, earlier_lines, line_acc \\ [], acc \\ [])

  defp do_highlight([], _, current_line, earlier_lines, line_acc, acc) do
    Enum.reverse(earlier_lines) ++ [[current_line | line_acc] | acc]
  end

  defp do_highlight([{op, {{l, c}, {l, c2}}} | rest], l, line, earlier, line_acc, acc) do
    {start_line, rest_line} = String.split_at(line, c2 - 1)
    {start_line, token} = String.split_at(start_line, c - 1)
    do_highlight(rest, l, start_line, earlier, [tag(token, op), rest_line | line_acc], acc)
  end

  defp do_highlight(instructions, l, line, [next | rest_earlier], line_acc, acc) do
    do_highlight(instructions, l - 1, next, rest_earlier, [], [[line | line_acc] | acc])
  end

  defp denormalize_all(instructions) do
    instructions
    |> Enum.flat_map(fn {op, type, zipper} ->
      denormalize(type, op, zipper |> Zipper.node() |> with_map_meta(), zipper)
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
    case zipper |> Zipper.up() |> Zipper.node() |> with_map_meta() do
      {:%, %{line: l, column: c}, _} ->
        [{op, {{l, c}, {l, c + 1}}} | denormalize_delimiter(op, meta, 1, 1)]

      _ ->
        denormalize_delimiter(op, Map.update!(meta, :column, &(&1 - 1)), 2, 1)
    end
  end

  defp denormalize(:delimiter, op, {call, %{line: l, column: c}, _}, _) do
    len = Macro.inspect_atom(:remote_call, call) |> String.length()
    [{op, {{l, c}, {l, c + len}}}]
  end

  defp denormalize_delimiter(op, meta, start_len, end_len) do
    case meta do
      %{line: l, column: c, closing: %{line: l2, column: c2}} ->
        [{op, {{l, c}, {l, c + start_len}}}, {op, {{l2, c2}, {l2, c2 + end_len}}}]

      _ ->
        []
    end
  end

  # HACK: meta in args haven't been converted to maps, so we do it here
  defp bounds({_, list, _} = node) when is_list(list), do: node |> with_map_meta() |> bounds()

  defp bounds({:%, %{line: l, column: c}, [_, map_node]}) do
    {_, closing_bound} = map_node |> with_map_meta() |> bounds()
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

  defp bounds({:atom, %{format: :keyword, line: l, column: c}, atom}) do
    atom_bounds(:key, atom, l, c)
  end

  defp bounds({:atom, %{line: l, column: c}, atom}) do
    atom_bounds(:literal, atom, l, c)
  end

  defp bounds({:__aliases__, %{line: l, column: c}, atoms}) do
    unwrapped = for {:atom, _, atom} <- atoms, do: atom
    len = {:__aliases__, [], unwrapped} |> Macro.to_string() |> String.length()
    {{l, c}, {l, c + len}}
  end

  defp bounds(unimplemented) do
    raise ArgumentError, "bounds unimplemented for: #{inspect(unimplemented)}"
  end

  defp atom_bounds(type, atom, l, c) when type in [:literal, :key] do
    len = Macro.inspect_atom(type, atom) |> String.length()
    {{l, c}, {l, c + len}}
  end

  defp tag(data, :ins), do: Owl.Data.tag(data, :green)
  defp tag(data, :del), do: Owl.Data.tag(data, :red)

  defp with_map_meta({_, _, _} = node) do
    # TODO: refactor
    Macro.update_meta(node, fn meta ->
      meta
      |> Map.new()
      |> case do
        %{closing: _} = map -> Map.update!(map, :closing, &Map.new/1)
        map -> map
      end
      |> case do
        %{last: _} = map -> Map.update!(map, :last, &Map.new/1)
        map -> map
      end
    end)
  end

  defp with_map_meta(nil), do: nil
end
