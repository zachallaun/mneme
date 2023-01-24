defmodule Mneme.Code do
  @moduledoc false

  alias Mneme.Serialize

  @doc """
  Transforms a Mneme assertion into an ExUnit assertion.
  """
  def mneme_to_exunit({:auto_assert, _, [{:<-, _, [{:when, _, [expected, guard]}, _]}]}) do
    quote do
      assert unquote(expected) = var!(actual)
      assert unquote(guard)
    end
  end

  def mneme_to_exunit({:auto_assert, _, [{:<-, _, [expected, _]}]}) do
    quote do
      assert unquote(expected) = var!(actual)
    end
  end

  @doc """
  Returns `true` if the node is the Mneme assertion for the context.
  """
  def mneme_assertion?(node, context) do
    case node do
      {:auto_assert, meta, [_]} -> meta[:line] == context[:line]
      _ -> false
    end
  end

  @doc """
  Formats a Mneme assertion as a string.
  """
  def format_assertion({:auto_assert, _, [expr]}, opts) do
    {:auto_assert, [], [expr]} |> Sourceror.to_string(opts)
  end

  @doc """
  Updates a Mneme assertion.
  """
  def update_assertion({:auto_assert, _, [expr]}, update_type, value, context)
      when update_type in [:new, :replace] do
    pattern = update_pattern(update_type, expr, Serialize.to_pattern(value, context))
    {:auto_assert, [], [pattern]}
  end

  defp update_pattern(:new, value_expr, pattern) do
    {:<-, [], [pattern, value_expr]}
  end

  defp update_pattern(:replace, {:<-, meta, [_pattern, value_expr]}, pattern) do
    {:<-, meta, [pattern, value_expr]}
  end
end
