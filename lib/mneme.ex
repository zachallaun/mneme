defmodule Mneme do
  @moduledoc """
  Auto assert away.
  """

  @doc """
  Sets up Mneme to run auto-assertions in this module.
  """
  defmacro __using__(_opts) do
    quote do
      import Mneme
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
end
