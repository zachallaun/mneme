defmodule Mneme.Serialize do
  @moduledoc false

  alias Mneme.Serializer

  @doc """
  Delegates to `Mneme.Serializer.to_match_expressions/2`.
  """
  @spec to_match_expressions(Serializer.t(), keyword()) :: {Macro.t(), Macro.t() | nil}
  defdelegate to_match_expressions(value, meta), to: Serializer

  @doc """
  Returns `{:ok, pin_expr}` if the value can be found in the given
  context, or `:error` otherwise.
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
  def map_to_match_expressions(values, meta) do
    Enum.map_reduce(values, nil, fn value, guard ->
      case {guard, to_match_expressions(value, meta)} do
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

  @doc """
  Generate a unique var expression for the current binding.

  ## Examples

      iex> unique_var(:ref, [])
      {:ref, [], nil}

      iex> unique_var(:ref, [ref: :foo])
      {:ref2, [], nil}
  """
  def unique_var(name, binding, i \\ 2) do
    if name in Keyword.keys(binding) do
      unique_var(:"#{name}#{i}", binding, i + 1)
    else
      {name, [], nil}
    end
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
  @spec to_match_expressions(t, keyword()) :: {Macro.t(), Macro.t() | nil}
  def to_match_expressions(value, meta)
end

defimpl Mneme.Serializer, for: Integer do
  def to_match_expressions(int, _meta), do: {int, nil}
end

defimpl Mneme.Serializer, for: BitString do
  def to_match_expressions(str, _meta), do: {str, nil}
end

defimpl Mneme.Serializer, for: List do
  def to_match_expressions(list, meta) do
    Mneme.Serialize.map_to_match_expressions(list, meta)
  end
end

defimpl Mneme.Serializer, for: Tuple do
  def to_match_expressions(tuple, meta) do
    values = Tuple.to_list(tuple)
    {value_matches, guard} = Mneme.Serialize.map_to_match_expressions(values, meta)
    {{:{}, [], value_matches}, guard}
  end
end

defimpl Mneme.Serializer, for: Reference do
  def to_match_expressions(ref, meta) do
    case Mneme.Serialize.fetch_pinned(ref, meta[:binding]) do
      {:ok, pin} ->
        {pin, nil}

      _ ->
        var = Mneme.Serialize.unique_var(:ref, meta[:binding])
        {var, {:is_reference, [], [var]}}
    end
  end
end

# defimpl Mneme.Serializer, for: Atom do
# defimpl Mneme.Serializer, for: Float do
# defimpl Mneme.Serializer, for: Function do
# defimpl Mneme.Serializer, for: PID do
# defimpl Mneme.Serializer, for: Map do
# defimpl Mneme.Serializer, for: Port do
# defimpl Mneme.Serializer, for: Any do
