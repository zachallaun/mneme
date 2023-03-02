defmodule Mneme.Diff.Formatter do
  @moduledoc false

  @doc """
  Highlights the given code based on the instructions.
  """
  def highlight_lines(code, instructions) do
    lines = code |> Owl.Data.lines() |> Enum.reverse()
    [last_line | rest] = lines

    instructions
    |> denormalize()
    |> do_highlight(length(lines), last_line, rest)
  end

  defp do_highlight(instructions, line_no, current_line, earlier_lines, line_acc \\ [], acc \\ [])

  defp do_highlight([], _, current_line, earlier_lines, line_acc, acc) do
    Enum.reverse(earlier_lines) ++ [[current_line | line_acc] | acc]
  end

  defp do_highlight([{op, {l, c}, len} | rest], l, line, earlier, line_acc, acc) do
    {start_line, rest_line} = String.split_at(line, c + len - 1)
    {start_line, token} = String.split_at(start_line, c - 1)
    do_highlight(rest, l, start_line, earlier, [tag(token, op), rest_line | line_acc], acc)
  end

  defp do_highlight(instructions, l, line, [next | rest_earlier], line_acc, acc) do
    do_highlight(instructions, l - 1, next, rest_earlier, [], [[line | line_acc] | acc])
  end

  defp denormalize(instructions) do
    Enum.flat_map(instructions, fn
      {op, {number, _}, %{token: token, line: l, column: c}} when number in [:int, :float] ->
        [{op, {l, c}, String.length(token)}]

      {op, {:atom, atom}, %{line: l, column: c}} ->
        [{op, {l, c}, atom |> inspect() |> String.length()}]

      {op, :"[]", meta} ->
        denormalize_delimiter(op, meta, 1, 1)

      {op, :{}, meta} ->
        denormalize_delimiter(op, meta, 1, 1)

      {op, :%{}, meta} ->
        denormalize_delimiter(op, Map.update!(meta, :column, &(&1 - 1)), 2, 1)
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp denormalize_delimiter(op, meta, start_len, end_len) do
    case meta do
      %{line: l, column: c, closing: %{line: l2, column: c2}} ->
        [{op, {l, c}, start_len}, {op, {l2, c2}, end_len}]

      _ ->
        []
    end
  end

  defp tag(data, :ins), do: Owl.Data.tag(data, :green)
  defp tag(data, :del), do: Owl.Data.tag(data, :red)
end
