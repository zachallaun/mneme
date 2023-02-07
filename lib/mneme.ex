defmodule Mneme do
  @moduledoc """
  Auto assert away.

  ## Options

  #{Mneme.Options.docs()}
  """

  @doc """
  Sets up Mneme to run auto-assertions in this module.
  """
  defmacro __using__(opts) do
    quote do
      import Mneme, only: [auto_assert: 1]
      require Mneme.Options

      Mneme.Options.register_attributes(unquote(opts))
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
  Asserts that the expression is truthy or generates a match/comparison.
  """
  defmacro auto_assert(body) do
    code = {:auto_assert, Macro.Env.location(__CALLER__), [body]}
    Mneme.Assertion.build(code, __CALLER__)
  end
end
