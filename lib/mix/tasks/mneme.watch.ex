defmodule Mix.Tasks.Mneme.Watch do
  @shortdoc "Run tests when files change"
  @moduledoc """
  Runs the tests for a project when source files change.

  This task is similar to [`mix test.watch`](https://hex.pm/packages/mix_test_watch),
  but updated to work with Mneme:

    * interrupts Mneme prompts, saving out already-accepted changes
    * tests aren't re-triggered when Mneme saves a test file after an
      update

  This task accepts the same arguments as `mix test`. For instance:

  ```sh
  # only run tests tagged with `some_tag: true`
  $ mix mneme.watch --only some_tag

  # only run tests from one file
  $ mix mneme.watch test/my_app/my_test.exs
  ```
  """

  use Mix.Task

  @doc false
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
