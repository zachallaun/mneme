defmodule Mneme.Assertion.Pattern do
  @moduledoc false

  alias __MODULE__

  @enforce_keys [:expr]
  defstruct [:expr, guard: nil, notes: []]

  @type t :: %Pattern{
          expr: term(),
          guard: Macro.t() | nil,
          notes: [String.t()]
        }

  @doc """
  Creates a new pattern.
  """
  def new(expr, other_attrs \\ []) do
    struct(Pattern, Keyword.put(other_attrs, :expr, expr))
  end
end
