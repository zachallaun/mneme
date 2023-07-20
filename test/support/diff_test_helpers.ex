defmodule Mneme.DiffTestHelpers do
  @moduledoc false
  alias Mneme.Diff

  @doc """
  Generates a diff as Owl data for the given pair of strings.
  """
  def format(left, right) do
    case Diff.compute(left, right) do
      {[], []} ->
        {nil, nil}

      {[], insertions} ->
        {nil, Diff.format_lines(right, insertions)}

      {deletions, []} ->
        {Diff.format_lines(left, deletions), nil}

      {deletions, insertions} ->
        {Diff.format_lines(left, deletions), Diff.format_lines(right, insertions)}
    end
  end

  @doc """
  Like `format/2`, but prints the colorized diff.
  """
  def dbg_format(left, right) do
    {left, right} = format(left, right)

    Owl.IO.puts([
      "\n",
      Owl.Data.unlines(left || []),
      "\n\n",
      Owl.Data.unlines(right || []),
      "\n"
    ])

    {left, right}
  end

  @doc """
  Like `format/2`, but installs IEx breaks in certain places for debugging.
  """
  def dbg_format!(left, right) do
    IEx.break!(Diff, :compute, 2)
    IEx.break!(Diff.Formatter, :highlight_lines, 2)
    format(left, right)
  end
end
