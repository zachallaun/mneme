example = "MIX_ENV=test mix mneme.install"

defmodule Mix.Tasks.Mneme.Install do
  @shortdoc "Sets up Mneme in your project."
  @moduledoc """
  #{@shortdoc}

  Running this command will automatically patch the following:

    * `mix.exs` - Adds Mneme's tasks to `:preferred_cli_env`
    * `.formatter.exs` - Adds `:mneme` to `:import_deps`
    * `test/test_helper.exs` - Adds `Mneme.start()` after `ExUnit.start()`

  ## Example

  Since your `:mneme` dependency is usually specified with `only: :test`,
  this task should be run with `MIX_ENV=test`.

  ```shell
  $ #{example}

  Igniter:
  Update: .formatter.exs

  1 1   |# Used by "mix format"
  2 2   |[
  3   - |  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    3 + |  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
    4 + |  import_deps: [:mneme]
  4 5   |]
  5 6   |

  Update: mix.exs

       ...|
   8  8   |      elixir: "~> 1.17",
   9  9   |      start_permanent: Mix.env() == :prod,
  10    - |      deps: deps()
     10 + |      deps: deps(),
     11 + |      preferred_cli_env: ["mneme.test": :test, "mneme.watch": :test]
  11 12   |    ]
  12 13   |  end
       ...|

  Update: test/test_helper.exs

  1 1   |ExUnit.start()
    2 + |Mneme.start()

  Proceed with changes? [y/n]
  ```
  """

  use Igniter.Mix.Task

  alias Igniter.Code.Function

  @example example

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      # Groups allow for overlapping arguments for tasks by the same author
      # See the generators guide for more.
      group: :mneme,
      # dependencies to add
      adds_deps: [],
      # dependencies to add and call their associated installers, if they exist
      installs: [],
      # An example invocation
      example: @example,
      # A list of environments that this should be installed in.
      only: [:test],
      # a list of positional arguments, i.e `[:file]`
      positional: [],
      # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
      # This ensures your option schema includes options from nested tasks
      composes: [],
      # `OptionParser` schema
      schema: [],
      # Default values for the options in the `schema`.
      defaults: [],
      # CLI aliases
      aliases: [],
      # A list of options in the schema that are required
      required: []
    }
  end

  @doc false
  @impl Igniter.Mix.Task
  def igniter(igniter) do
    igniter
    |> update_preferred_cli_env()
    |> update_import_deps()
    |> update_test_helper()
  end

  defp update_preferred_cli_env(igniter) do
    Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
      # First, try to update a keyword literal in the project
      with {:ok, zipper} <- Function.move_to_def(zipper, :project, 0),
           {:ok, zipper} <-
             Igniter.Code.Keyword.put_in_keyword(
               zipper,
               [:preferred_cli_env, :"mneme.test"],
               :test
             ),
           {:ok, zipper} <-
             Igniter.Code.Keyword.put_in_keyword(
               zipper,
               [:preferred_cli_env, :"mneme.watch"],
               :test
             ) do
        {:ok, zipper}
      else
        _ ->
          # Second, try to update a local function containing a keyword literal.
          # This handles `[preferred_cli_env: preferred_cli_env()]`.
          with {:ok, zipper} <- Function.move_to_def(zipper, :project, 0),
               {:ok, zipper} <- Igniter.Code.Keyword.get_key(zipper, :preferred_cli_env),
               true <- Function.function_call?(zipper),
               {call_name, _, call_args} <- zipper.node,
               {:ok, zipper} <- move_to_def_or_defp(zipper, call_name, length(call_args)),
               {:ok, zipper} <-
                 Igniter.Code.Keyword.put_in_keyword(zipper, [:"mneme.watch"], :test) do
            {:ok, zipper}
          else
            _ ->
              {:error,
               "Unable to update `:preferred_cli_env` to include `[\"mneme.watch\": :test]"}
          end
      end
    end)
  end

  defp update_import_deps(igniter) do
    Igniter.Project.Formatter.import_dep(igniter, :mneme)
  end

  defp update_test_helper(igniter) do
    Igniter.update_elixir_file(igniter, "test/test_helper.exs", fn zipper ->
      with :error <- Function.move_to_function_call(zipper, {Mneme, :start}, :any),
           {:ok, zipper} <- Function.move_to_function_call(zipper, {ExUnit, :start}, :any) do
        {:ok, Igniter.Code.Common.add_code(zipper, "Mneme.start()")}
      else
        _ -> {:ok, zipper}
      end
    end)
  end

  defp move_to_def_or_defp(zipper, call_name, arity) do
    with :error <- Igniter.Code.Function.move_to_def(zipper, call_name, arity) do
      Igniter.Code.Function.move_to_defp(zipper, call_name, arity)
    end
  end
end
