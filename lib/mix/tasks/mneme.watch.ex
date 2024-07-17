defmodule Mix.Tasks.Mneme.Watch do
  @shortdoc "Re-runs tests on save, interrupting Mneme prompts"
  @moduledoc """
  TODO
  """

  use Mix.Task

  @doc """
  Runs `mix.test` with the given CLI arguments, restarting when files change.
  """
  @impl Mix.Task
  @spec run([String.t()]) :: no_return()
  def run(args) do
    Mix.env(:test)
    ensure_os!()

    children = [
      {Mneme.Watch.TestRunner, cli_args: args}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)

    :timer.sleep(:infinity)
  end

  defp ensure_os! do
    case os_type() do
      :unix ->
        :ok

      unsupported ->
        error = "file watcher is unsupported on OS: #{inspect(unsupported)}"

        [:red, "error: ", :default_color, error]
        |> IO.ANSI.format()
        |> then(&IO.puts(:stderr, &1))

        System.halt(1)
    end
  end

  defp os_type do
    {os_type, _} = :os.type()
    os_type
  end
end
