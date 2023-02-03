defmodule Mneme.Code do
  @moduledoc false

  alias Mneme.Serializer

  @doc """
  Transforms a Mneme assertion into an ExUnit assertion.
  """
  def auto_assertion_to_ex_unit({:auto_assert, _, [{:<-, _, [{:when, _, [expected, guard]}, _]}]}) do
    quote do
      assert unquote(expected) = var!(actual)
      assert unquote(guard)
    end
  end

  def auto_assertion_to_ex_unit({:auto_assert, _, [{:<-, _, [expected, _]}]}) do
    quote do
      assert unquote(expected) = var!(actual)
    end
  end

  @doc """
  Returns `true` if the node is the Mneme assertion for the context.
  """
  def auto_assertion?(node, context) do
    case node do
      {:auto_assert, meta, [_]} -> meta[:line] == context[:line]
      _ -> false
    end
  end

  @doc """
  Formats a Mneme assertion as a string.
  """
  def format_auto_assertion({:auto_assert, _, [expr]}, opts) do
    {:auto_assert, [], [expr]} |> Sourceror.to_string(opts)
  end

  @doc """
  Updates a Mneme assertion.
  """
  def update_auto_assertion({:auto_assert, _, [expr]}, update_type, value, context)
      when update_type in [:new, :replace] do
    pattern = update_pattern(update_type, expr, to_pattern(value, context))
    {:auto_assert, [], [pattern]}
  end

  defp update_pattern(:new, value_expr, pattern) do
    {:<-, [], [pattern, value_expr]}
  end

  defp update_pattern(:replace, {:<-, meta, [_pattern, value_expr]}, pattern) do
    {:<-, meta, [pattern, value_expr]}
  end

  @doc """
  Generates a pattern AST that matches the value.
  """
  def to_pattern(value, context \\ []) do
    case Serializer.to_pattern(value, context) do
      {pattern, nil} -> pattern
      {pattern, guard} -> {:when, [], [pattern, guard]}
    end
  end

  # Serializer helpers

  @doc false
  def fetch_pinned(value, binding) do
    case List.keyfind(binding || [], value, 1) do
      {name, ^value} -> {:ok, {:^, [], [{name, [], nil}]}}
      _ -> :error
    end
  end

  @doc false
  def enum_to_pattern(values, context) do
    Enum.map_reduce(values, nil, fn value, guard ->
      case {guard, Serializer.to_pattern(value, context)} do
        {nil, {expr, guard}} -> {expr, guard}
        {guard, {expr, nil}} -> {expr, guard}
        {guard1, {expr, guard2}} -> {expr, {:and, [], [guard1, guard2]}}
      end
    end)
  end

  @doc false
  def guard(name, guard) do
    var = {name, [], nil}
    {var, {guard, [], [var]}}
  end
end
