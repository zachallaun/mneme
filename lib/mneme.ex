defmodule Mneme do
  @moduledoc """
  Auto assert away.
  """

  @doc """
  Starts Mneme.
  """
  def start do
    children = [Mneme.Server]
    opts = [strategy: :one_for_one, name: Mneme.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Generates a match assertion.
  """
  defmacro auto_assert({:<-, _, [{:when, _, [expected, guard]}, actual]} = expr) do
    code = __gen_assert_match__({expected, guard})
    __gen_auto_assert__(:replace, __CALLER__, expr, actual, code)
  end

  defmacro auto_assert({:<-, _, [expected, actual]} = expr) do
    code = __gen_assert_match__({expected, nil})
    __gen_auto_assert__(:replace, __CALLER__, expr, actual, code)
  end

  defmacro auto_assert(expr) do
    code =
      quote do
        raise ExUnit.AssertionError, message: "No match present"
      end

    __gen_auto_assert__(:new, __CALLER__, expr, expr, code)
  end

  @doc false
  def __gen_auto_assert__(type, env, expr, actual, code) do
    quote do
      var!(actual) = unquote(actual)
      locals = Keyword.delete(binding(), :actual)
      meta = [module: __MODULE__, binding: locals] ++ unquote(Macro.Env.location(env))

      try do
        unquote(code)
      rescue
        error in [ExUnit.AssertionError] ->
          assertion = {unquote(type), unquote(Macro.escape(expr)), var!(actual), meta}

          case Mneme.Server.await_assertion(assertion) do
            {:ok, expected} ->
              Mneme.__gen_assert_match__(expected)
              |> Code.eval_quoted(binding(), __ENV__)

            :error ->
              reraise error, __STACKTRACE__
          end
      end
    end
  end

  @doc false
  def __gen_assert_match__({expr, nil}) do
    quote do
      ExUnit.Assertions.assert(unquote(expr) = var!(actual))
    end
  end

  def __gen_assert_match__({expr, guard}) do
    quote do
      ExUnit.Assertions.assert(unquote(expr) = var!(actual))
      ExUnit.Assertions.assert(unquote(guard))
    end
  end
end
