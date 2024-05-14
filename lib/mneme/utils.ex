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

  @doc """
  Strips leading or trailing ignorable content from the given string.

  Ignorable content is content at the beginning or end of the string that
  is unlikely to be relevant, like whitespace, formatting characters,
  timestamps, etc.
  """
  @spec strip_ignorable(String.t()) :: String.t()
  def strip_ignorable(string) when is_binary(string) do
    if String.valid?(string) do
      re_ignore_head = re_concat!(["^("] ++ re_ignorables() ++ [")*"])
      re_ignore_tail = re_concat!(["("] ++ re_ignorables() ++ [")*$"])

      {_head, rest} =
        case Regex.run(re_ignore_head, string, return: :index) do
          [{0, match_length} | _] ->
            split_bytes(string, match_length)
        end

      {content, _tail} =
        case Regex.run(re_ignore_tail, rest, return: :index) do
          nil -> {rest, ""}
          [{index, _match_length} | _] -> split_bytes(rest, index)
        end

      content
    else
      string
    end
  end

  defp split_bytes(string, byte_size) when is_binary(string) do
    case string do
      <<head::binary-size(^byte_size), tail::binary>> -> {head, tail}
    end
  end

  defp re_ignorables do
    Enum.intersperse(
      [
        # whitespace
        ~r/(\s+)/,
        # timestamp
        ~r/(\d{1,2}:\d{1,2}:\d{1,2}\.\d+)/,
        # date
        ~r/(\d{1,4}[\/-]\d{1,2}[\/-]\d{1,2})/,
        # terminal escape sequence
        ~r/(\e\[\d+m)/
      ],
      "|"
    )
  end

  defp re_concat!(reg_exprs) do
    regex_modifies = [:unicode]

    reg_exprs
    |> Enum.map_join("", fn
      %Regex{} = regex -> Regex.source(regex)
      s when is_binary(s) -> s
    end)
    |> Regex.compile!(regex_modifies)
  end
end
