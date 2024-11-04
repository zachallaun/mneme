defmodule Mix.Tasks.Mneme.Watch do
  @shortdoc "Runs the tests for a project when source files change."
  @moduledoc """
  #{@shortdoc}

  This task is similar to [`mix test.watch`](https://hex.pm/packages/mix_test_watch),
  but updated to work with Mneme:

    * interrupts Mneme prompts, saving already-accepted changes
    * doesn't re-trigger when test files are updated by Mneme

  ## Setup

  To ensure `mix mneme.watch` runs in the test environment, add a
  `:preferred_cli_env` entry in `mix.exs`:

      def project do
        [
          ...
          preferred_cli_env: [
            "mneme.test": :test,
            "mneme.watch": :test
          ],
          ...
        ]
      end

  ## Command line options

  In addition to the options supported by `mix mneme.test` and `mix test`,
  which this task runs under the hood, the following CLI options are
  available:

    * `--exit-on-success` - stops the test watcher the first time the
      test suite passes.

  All other CLI arguments are passed to `mix test`, which runs under the
  hood.

  ## The --stale option

  The `--stale` command line option is especially useful. Run by itself,
  `mix mneme.watch` will run all of your tests when any source file or
  test is saved. When used with `--stale`, only tests that have gone
  stale due to changes in `lib` will be re-run, greatly speeding up most
  test runs.

  For more information, see the `mix test` documentation for
  [the `--stale` option](https://hexdocs.pm/mix/Mix.Tasks.Test.html#module-the-stale-option).

  ## Examples

  ```sh
  $ mix mneme.watch --only some_tag
  # runs tests tagged with `some_tag: true`

  $ mix mneme.watch test/my_app/my_test.exs
  # runs tests in the given file

  $ mix mneme.watch --stale
  # runs stale tests
  ```
  """

  use Mix.Task

  @doc false
  @impl Mix.Task
  @spec run([String.t()]) :: no_return()
  def run(args) do
    Mix.env(:test)

    children = [
      {Mneme.Watch.TestRunner, cli_args: args}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)

    :timer.sleep(:infinity)
  end
end
