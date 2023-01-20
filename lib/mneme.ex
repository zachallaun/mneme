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
        ExUnit.Assertions.assert(unquote(expected) = actual)
      rescue
        error in [ExUnit.AssertionError] ->
          accepted? =
            Mneme.Server.await_assertion(:replace, unquote(Macro.escape(expr)), actual, location)

          if accepted? do
            :ok
          else
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
      accepted? = Mneme.Server.await_assertion(:new, expr, actual, location)

      if accepted? do
        :ok
      else
        raise ExUnit.AssertionError,
          message: "auto_assert failed to construct a suitable assertion for #{inspect(actual)}"
      end
    end
  end
end
