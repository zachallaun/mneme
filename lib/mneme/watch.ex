defmodule Mneme.Watch do
  @moduledoc false

  @doc """
  Runs `mix.test` with the given CLI arguments, restarting when files change.
  """
  @spec run([String.t()]) :: no_return()
  def run(args \\ []) do
    case os_type() do
      :unix ->
        Mneme.Watch.Listener.listen(args)
        :timer.sleep(:infinity)

      unsupported ->
        error = "file watcher is unsupported on OS: #{inspect(unsupported)}"

        [:red, "error: ", :default_color, error]
        |> IO.ANSI.format()
        |> then(&IO.puts(:stderr, &1))
    end
  end

  defp os_type do
    {os_type, _} = :os.type()
    os_type
  end
end
