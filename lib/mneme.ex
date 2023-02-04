defmodule Mneme do
  @moduledoc """
  Auto assert away.

  ## Options

  #{Mneme.Options.docs()}
  """

  @doc """
  Sets up Mneme to run auto-assertions in this module.
  """
  defmacro __using__(_opts) do
    quote do
      import Mneme, only: [auto_assert: 1]
      require Mneme.Options

      Mneme.Options.register_attributes()
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
    ex_unit_assertion = Mneme.Code.auto_assertion_to_ex_unit({:auto_assert, [], [expr]})
    gen_auto_assert(:replace, __CALLER__, actual, ex_unit_assertion)
  end

  defmacro auto_assert(expr) do
    raise_no_match =
      quote do
        raise ExUnit.AssertionError, message: "No match present"
      end

    gen_auto_assert(:new, __CALLER__, expr, raise_no_match)
  end

  defp gen_auto_assert(type, env, actual, test_expr) do
    context = %{
      file: env.file,
      line: env.line,
      module: env.module,
      #
      # TODO: access aliases some other way.
      #
      # Env :aliases is considered private and should not be relied on,
      # but I'm not sure where else to access the alias information
      # needed. Macro.Env.fetch_alias/2 is a thing, but it goes from
      # alias to resolved module, and I need resolved module to alias.
      # E.g. Macro.Env.fetch_alias(env, Bar) might return {:ok, Foo.Bar},
      # but I have Foo.Bar and need to know that Bar is the alias in
      # the current environment.
      aliases: env.aliases
    }

    quote do
      var!(actual) = unquote(actual)
      locals = Keyword.delete(binding(), :actual)

      context =
        unquote(Macro.escape(context))
        |> Map.put(:binding, locals)

      try do
        unquote(test_expr)
      rescue
        error in [ExUnit.AssertionError] ->
          assertion = {unquote(type), var!(actual), context}

          case Mneme.Server.await_assertion(assertion) do
            {:ok, expr} ->
              expr
              |> Mneme.Code.auto_assertion_to_ex_unit()
              |> Code.eval_quoted(binding(), __ENV__)

            :error ->
              reraise error, __STACKTRACE__
          end
      end
    end
  end
end
