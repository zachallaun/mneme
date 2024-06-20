defmodule Mneme.DiffTestHelpers do
  @moduledoc false
  alias Mneme.Diff

  @doc """
  Generates a diff as for the given pair of strings.
  """
  def format(left, right) do
    case Diff.format(left, right) do
      {:ok, result} -> result
      {:error, {:internal, e, stacktrace}} -> reraise e, stacktrace
    end
  end

  @doc """
  Like `format/2`, but prints the colorized diff.
  """
  def dbg_format(left, right) do
    {left, right} = format(left, right)
    left = Mneme.Terminal.tag_lines(left)
    right = Mneme.Terminal.tag_lines(right)

    Owl.IO.puts([
      "\n",
      Owl.Data.unlines(left),
      "\n\n",
      Owl.Data.unlines(right),
      "\n"
    ])

    {left, right}
  end
end
