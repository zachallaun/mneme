defmodule Mneme.Utils do
  @moduledoc false

  @doc """
  Returns the occurrences of a given character in a string.

  ## Examples

      iex> occurrences("foo", ?o)
      2

      iex> occurrences("foo", ?z)
      0

  """
  def occurrences(string, char) when is_binary(string) and is_integer(char) do
    occurrences(string, char, 0)
  end

  defp occurrences(<<char, rest::binary>>, char, acc), do: occurrences(rest, char, acc + 1)
  defp occurrences(<<_, rest::binary>>, char, acc), do: occurrences(rest, char, acc)
  defp occurrences(<<>>, _char, acc), do: acc
end
