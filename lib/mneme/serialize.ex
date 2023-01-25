defmodule Mneme.Serialize do
  @moduledoc """
  Helpers for converting runtime values to match patterns.
  """

  alias Mneme.Serializer

  @doc """
  Generates a Mneme pattern expression from a runtime value.
  """
  @spec to_pattern(Serializer.t(), keyword()) :: Macro.t()
  def to_pattern(value, context \\ []) do
    case Serializer.to_pattern(value, context) do
      {pattern, nil} -> pattern
      {pattern, guard} -> {:when, [], [pattern, guard]}
    end
  end

  @doc """
  Returns `{:ok, pin_expr}` if the value can be found in the given
  binding, or `:error` otherwise.
  """
  def fetch_pinned(value, binding) do
    case List.keyfind(binding, value, 1) do
      {name, ^value} -> {:ok, {:^, [], [{name, [], nil}]}}
      _ -> :error
    end
  end

  @doc """
  Maps a list of values to their match expressions, combining any guards
  into a single clause with `and`.
  """
  def list_to_pattern(values, meta) do
    Enum.map_reduce(values, nil, fn value, guard ->
      case {guard, Serializer.to_pattern(value, meta)} do
        {nil, {expr, guard}} -> {expr, guard}
        {guard, {expr, nil}} -> {expr, guard}
        {guard1, {expr, guard2}} -> {expr, {:and, [], [guard1, guard2]}}
      end
    end)
  end

  @doc """
  Generate a quoted remote call. Requires fully expanded aliases.

  ## Examples

      iex> remote_call(:Kernel, :is_reference, [{:ref, [], nil}])
      {
        {:., [], [{:__aliases__, [alias: false], [:Kernel]}, :is_reference]},
        [],
        [{:ref, [], nil}]
      }
  """
  def remote_call(module, fun, args) do
    {{:., [], [{:__aliases__, [alias: false], [module]}, fun]}, [], args}
  end
end

defprotocol Mneme.Serializer do
  @doc """
  Generates ASTs that can be used to assert a match of the given value.

  Must return `{match_expression, guard_expression}`, where the first
  will be used in a `=` match, and the second will be a secondary
  assertion with access to any bindings produced by the match.

  Note that `guard_expression` can be `nil`, in which case the guard
  check will not occur.
  """
  @spec to_pattern(t, keyword()) :: {Macro.t(), Macro.t() | nil}
  def to_pattern(value, meta)
end

defimpl Mneme.Serializer, for: Integer do
  def to_pattern(int, _meta), do: {int, nil}
end

defimpl Mneme.Serializer, for: Float do
  def to_pattern(float, _meta), do: {float, nil}
end

defimpl Mneme.Serializer, for: BitString do
  def to_pattern(str, _meta), do: {str, nil}
end

defimpl Mneme.Serializer, for: List do
  def to_pattern(list, meta) do
    Mneme.Serialize.list_to_pattern(list, meta)
  end
end

defimpl Mneme.Serializer, for: Tuple do
  def to_pattern(tuple, meta) do
    values = Tuple.to_list(tuple)
    {value_matches, guard} = Mneme.Serialize.list_to_pattern(values, meta)
    {{:{}, [], value_matches}, guard}
  end
end

defimpl Mneme.Serializer, for: Reference do
  def to_pattern(ref, meta) do
    case Mneme.Serialize.fetch_pinned(ref, meta[:binding] || []) do
      {:ok, pin} ->
        {pin, nil}

      _ ->
        var = {:ref, [], nil}
        {var, {:is_reference, [], [var]}}
    end
  end
end

defimpl Mneme.Serializer, for: Atom do
  def to_pattern(atom, _meta), do: {atom, nil}
end

# defimpl Mneme.Serializer, for: PID do
# defimpl Mneme.Serializer, for: Map do
# defimpl Mneme.Serializer, for: Port do
# defimpl Mneme.Serializer, for: Any do
