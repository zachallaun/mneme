defmodule Mneme.Format do
  @moduledoc false

  @doc """
  Prefix every line of `message` with the given `prefix`.
  """
  def prefix_lines(message, prefix) do
    message
    |> String.split("\n")
    |> Enum.map(&[prefix, &1])
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end
end
