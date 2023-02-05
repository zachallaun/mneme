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
  defmacro auto_assert(expr) do
    context = assertion_context(__CALLER__)
    assertion = Mneme.Assertion.build(expr, context)

    quote do
      {assertion, eval_binding} = unquote(assertion)

      try do
        case assertion.type do
          :new ->
            raise ExUnit.AssertionError, message: "No match present"

          :replace ->
            {result, _} =
              assertion
              |> Mneme.Assertion.convert(target: :ex_unit_eval)
              |> Code.eval_quoted(eval_binding, __ENV__)

            result
        end
      rescue
        error in [ExUnit.AssertionError] ->
          case Mneme.Server.await_assertion(assertion) do
            {:ok, assertion} ->
              assertion
              |> Mneme.Assertion.convert(target: :ex_unit_eval)
              |> Code.eval_quoted(eval_binding, __ENV__)

            :error ->
              reraise error, [hd(__STACKTRACE__)]
          end
      end
    end
  end

  defp assertion_context(caller) do
    {test, _arity} = caller.function

    %{
      file: caller.file,
      line: caller.line,
      module: caller.module,
      test: test,
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
      aliases: caller.aliases
    }
  end
end
