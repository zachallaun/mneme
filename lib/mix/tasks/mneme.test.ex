defmodule Mix.Tasks.Mneme.Test do
  @shortdoc "Run tests with support for Mneme's options at the command line"
  @moduledoc """
  #{@shortdoc}

  This task is like `mix test`, except that it accepts some command line
  options specific to Mneme. See ["Command line options"](#module-command-line-options)
  below.

  ## Setup

  To ensure `mix mneme.test` runs in the test environment, add a
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

  In addition to the options supported by `mix test`, which runs under
  the hood, the following CLI options are available:

    * `--action [prompt,accept,reject]`
    * `--default-pattern [infer,first,last]`
    * `--diff [text,semantic]`
    * `--diff-style [side_by_side,stacked]`
    * `--force-update`
    * `--target [mneme,ex_unit]`

  Option documentation is found here: [Mneme – Options](`Mneme#module-options`)
  """

  use Mix.Task

  @switches [
    action: :string,
    default_pattern: :string,
    diff: :string,
    diff_style: :string,
    force_update: :boolean,
    target: :string,
    dry_run: :boolean
  ]

  # Ensure that these switches are collected instead of all but last
  # discarded so that they can be passed to `mix test`.
  @mix_test_keep [
    include: :keep,
    exclude: :keep,
    only: :keep,
    formatter: :keep
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, argv} = OptionParser.parse!(argv, switches: @switches ++ @mix_test_keep)
    {opts, mix_test_opts} = Keyword.split(opts, Keyword.keys(@switches))
    mix_test_argv = OptionParser.to_argv(mix_test_opts) ++ argv

    Application.put_env(:mneme, :cli_opts, opts)

    Mix.Task.reenable("test")
    Mix.Task.run("test", mix_test_argv)
  end
end
