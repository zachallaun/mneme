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

  defmacro auto_assert({:=, _meta, [_left, _right]} = assertion) do
    quote do
      ExUnit.Assertions.assert(unquote(assertion))
    end
  end

  defmacro auto_assert(expr) do
    quote do
      value = unquote(expr)
      expr = unquote(Macro.escape(expr))
      location = unquote(Macro.Env.location(__CALLER__))
      Mneme.Server.new_assertion(value, expr, location)
    end
  end
end
