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

# defimpl Mneme.Serializer, for: Atom do
# defimpl Mneme.Serializer, for: List do
# defimpl Mneme.Serializer, for: Float do
# defimpl Mneme.Serializer, for: Function do
# defimpl Mneme.Serializer, for: PID do
# defimpl Mneme.Serializer, for: Map do
# defimpl Mneme.Serializer, for: Port do
# defimpl Mneme.Serializer, for: Reference do
# defimpl Mneme.Serializer, for: Any do
