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

  defmacro auto_assert({:=, _meta, [expected, actual]} = expr) do
    quote do
      actual = unquote(actual)
      location = unquote(Macro.Env.location(__CALLER__))

      try do
        unquote(__gen_assert_match__(expected, quote(do: actual)))
      rescue
        error in [ExUnit.AssertionError] ->
          case Mneme.Server.await_assertion(
                 :replace,
                 unquote(Macro.escape(expr)),
                 actual,
                 location
               ) do
            {:ok, expected} ->
              Mneme.__gen_assert_match__(expected, actual)
              |> Code.eval_quoted(binding(), __ENV__)

            :error ->
              reraise error, __STACKTRACE__
          end
      end
    end
  end

  defmacro auto_assert(expr) do
    quote do
      actual = unquote(expr)
      expr = unquote(Macro.escape(expr))
      location = unquote(Macro.Env.location(__CALLER__))

      case Mneme.Server.await_assertion(:new, expr, actual, location) do
        {:ok, expected} ->
          Mneme.__gen_assert_match__(expected, actual)
          |> Code.eval_quoted(binding(), __ENV__)

        :error ->
          raise ExUnit.AssertionError,
            message: "auto_assert failed to construct a suitable assertion for #{inspect(actual)}"
      end
    end
  end

  @doc false
  def __gen_assert_match__(expected_expr, actual_value) do
    quote do
      ExUnit.Assertions.assert(unquote(expected_expr) = unquote(actual_value))
    end
  end
end
