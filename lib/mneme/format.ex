defmodule Mneme.Format do
  @moduledoc false

  @doc """
  Prefix every line of `message` with the given `prefix`.
  """
  def prefix_lines(message, prefix) do
    message
    |> String.split("\n")
    |> Enum.map_join("\n", &(prefix <> &1))
  end
end
