defmodule Mneme do
  @moduledoc """
  Auto assert away.
  """

  @exunit_configuration [
    timeout: :infinity,
    formatters: [Mneme.ExUnitFormatter],
    default_formatter: ExUnit.CLIFormatter
  ]

  @doc """
  Starts the Mneme application server.

  Because Mneme prompts the user before altering assertions, we also
  have to configure ExUnit to prevent timeouts and mangled text due to
  async tests.
  """
  def start do
    ExUnit.configure(@exunit_configuration)
    ExUnit.after_suite(&Mneme.Server.after_suite/1)

    children = [Mneme.Server]
    opts = [strategy: :one_for_one, name: Mneme.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Generates a match assertion.
  """
  defmacro auto_assert({:<-, _, [_, actual]} = expr) do
    assertion = Mneme.Code.mneme_to_exunit({:auto_assert, [], [expr]})
    __gen_auto_assert__(:replace, __CALLER__, actual, assertion)
  end

  defmacro auto_assert(expr) do
    assertion =
      quote do
        raise ExUnit.AssertionError, message: "No match present"
      end

    __gen_auto_assert__(:new, __CALLER__, expr, assertion)
  end

  @doc false
  def __gen_auto_assert__(type, env, actual, assertion) do
    quote do
      var!(actual) = unquote(actual)
      locals = Keyword.delete(binding(), :actual)
      meta = [module: __MODULE__, binding: locals] ++ unquote(Macro.Env.location(env))

      try do
        unquote(assertion)
      rescue
        error in [ExUnit.AssertionError] ->
          assertion = {unquote(type), var!(actual), meta}

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
end
