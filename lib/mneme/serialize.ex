defmodule Mneme.Serialize do
  @moduledoc false

  alias Mneme.Serializer

  @doc """
  Delegates to `Mneme.Serializer.to_match_expression/2`.
  """
  @spec to_match_expression(Serializer.t(), keyword()) :: Macro.t()
  defdelegate to_match_expression(value, meta), to: Serializer

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
end

defprotocol Mneme.Serializer do
  @doc """
  Generates an AST that can be embedded in a match (`=`) expression.
  """
  @spec to_match_expression(t, keyword()) :: Macro.t()
  def to_match_expression(value, meta)
end

defimpl Mneme.Serializer, for: Integer do
  def to_match_expression(int, _meta), do: int
end

defimpl Mneme.Serializer, for: BitString do
  def to_match_expression(str, _meta), do: str
end

defimpl Mneme.Serializer, for: Tuple do
  def to_match_expression(tuple, meta) do
    values =
      tuple
      |> Tuple.to_list()
      |> Enum.map(&Mneme.Serializer.to_match_expression(&1, meta))

    {:{}, [], values}
  end
end

defimpl Mneme.Serializer, for: Reference do
  def to_match_expression(ref, meta) do
    case Mneme.Serialize.fetch_pinned(ref, meta[:binding]) do
      {:ok, pin} -> pin
      _ -> raise "can't serialize non-pinned reference: #{inspect(ref)}"
    end
  end
end

# defimpl Mneme.Serializer, for: Atom do
# defimpl Mneme.Serializer, for: List do
# defimpl Mneme.Serializer, for: Float do
# defimpl Mneme.Serializer, for: Function do
# defimpl Mneme.Serializer, for: PID do
# defimpl Mneme.Serializer, for: Map do
# defimpl Mneme.Serializer, for: Port do
# defimpl Mneme.Serializer, for: Any do
