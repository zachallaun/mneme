defmodule Mneme.Utils do
  @moduledoc false

  @doc """
  Returns the formatter options for the given file.
  """
  def formatter_opts(file \\ nil) do
    {_formatter, opts} = Mix.Tasks.Format.formatter_for_file(file || __ENV__.file)
    opts
  end
end
