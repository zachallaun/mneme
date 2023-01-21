defmodule Mneme.Code do
  @moduledoc false

  @doc """
  Transform Mneme match AST into ExUnit assertion AST.
  """
  def mneme_to_exunit({:<-, _, [{:when, _, [expected, guard]}, _]}) do
    quote do
      assert unquote(expected) = var!(actual)
      assert unquote(guard)
    end
  end

  def mneme_to_exunit({:<-, _, [expected, _]}) do
    quote do
      assert unquote(expected) = var!(actual)
    end
  end
end
