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
    Mneme.Assertion.build(expr, __CALLER__)
  end
end
