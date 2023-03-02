defmodule Mneme.Diff.Formatter do
  @moduledoc false

  @doc """
  Highlights the given code based on the instructions.
  """
  def highlight(code, instructions) do
    lines = code |> Owl.Data.lines() |> Enum.reverse()
    [last_line | rest] = lines

    instructions
    |> denormalize()
    |> do_highlight(length(lines), last_line, rest)
  end

  defp do_highlight(instructions, line_no, current_line, earlier_lines, acc \\ [])

  defp do_highlight([], _, current_line, earlier_lines, acc) do
    earlier_lines ++ [current_line | acc]
  end

  defp do_highlight([{op, {l, c}, len} | rest], l, line, earlier, acc) do
    {start_line, rest_line} = String.split_at(line, c + len - 1)
    {start_line, token} = String.split_at(start_line, c - 1)
    do_highlight(rest, l, start_line, earlier, [tag(token, op), rest_line | acc])
  end

  defp do_highlight(instructions, l, line, [next | rest_earlier], acc) do
    do_highlight(instructions, l - 1, next, rest_earlier, [line | acc])
  end

  defp denormalize(instructions) do
    Enum.flat_map(instructions, fn
      {op, {:int, _}, %{token: token, line: l, column: c}} ->
        [{op, {l, c}, String.length(token)}]

      {op, :"[]", %{line: l, column: c, closing: %{line: l_end, column: c_end}}} ->
        [{op, {l, c}, 1}, {op, {l_end, c_end}, 1}]
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp tag(data, :ins), do: Owl.Data.tag(data, :green)
  defp tag(data, :del), do: Owl.Data.tag(data, :red)
end
