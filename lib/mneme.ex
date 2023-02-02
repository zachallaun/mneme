defmodule Mneme do
  @moduledoc """
  Auto assert away.
  """

  alias Mneme.Utils

  @options [
    action: [
      type: {:in, [:prompt, :accept, :reject]},
      default: :prompt
    ]
  ]

  @options_schema NimbleOptions.new!(@options)

  @doc """
  Sets up Mneme to run auto-assertions in this module.
  """
  defmacro __using__(_opts) do
    quote do
      import Mneme, only: [auto_assert: 1]
      require Mneme.Utils

      Mneme.Utils.register_attributes()
    end
  end

  @doc """
  Configures the Mneme application server to run with ExUnit.
  """
  def start do
    ExUnit.configure(
      formatters: [Mneme.ExUnitFormatter],
      default_formatter: ExUnit.CLIFormatter,
      timeout: :infinity
    )

    children = [
      Mneme.Server
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc """
  Generates a match assertion.
  """
  defmacro auto_assert({:<-, _, [_, actual]} = expr) do
    assertion = Mneme.Code.mneme_to_exunit({:auto_assert, [], [expr]})
    gen_auto_assert(:replace, __CALLER__, actual, assertion)
  end

  defmacro auto_assert(expr) do
    assertion =
      quote do
        raise ExUnit.AssertionError, message: "No match present"
      end

    gen_auto_assert(:new, __CALLER__, expr, assertion)
  end

  defp gen_auto_assert(type, env, actual, assertion) do
    quote do
      var!(actual) = unquote(actual)
      locals = Keyword.delete(binding(), :actual)
      context = Map.new([module: __MODULE__, binding: locals] ++ unquote(Macro.Env.location(env)))

      try do
        unquote(assertion)
      rescue
        error in [ExUnit.AssertionError] ->
          assertion = {unquote(type), var!(actual), context}

          case Mneme.Server.await_assertion(assertion) do
            {:ok, expr} ->
              expr
              |> Mneme.Code.mneme_to_exunit()
              |> Code.eval_quoted(binding(), __ENV__)

            :error ->
              reraise error, __STACKTRACE__
          end
      end
    end
  end

  @doc false
  def __options__(test_tags) do
    opts =
      test_tags
      |> Utils.collect_attributes()
      |> Enum.map(fn {k, [v | _]} -> {k, v} end)
      |> Keyword.new()

    opts
    |> validate_opts(test_tags)
    |> Map.new()
  end

  defp validate_opts(opts, test_tags) do
    case NimbleOptions.validate(opts, @options_schema) do
      {:ok, opts} ->
        opts

      {:error, %{key: key_or_keys} = error} ->
        %{file: file, line: line, module: module} = test_tags
        stacktrace_info = [file: file, line: line, module: module]

        IO.warn("[Mneme] " <> Exception.message(error), stacktrace_info)

        opts
        |> without_opts(key_or_keys)
        |> validate_opts(test_tags)
    end
  end

  defp without_opts(opts, key_or_keys), do: Keyword.drop(opts, List.wrap(key_or_keys))
end
