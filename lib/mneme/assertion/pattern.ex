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

  @doc """
  Combines a list of patterns into a single list pattern.
  """
  def combine(patterns) when is_list(patterns) do
    {exprs, {guard, notes}} =
      Enum.map_reduce(
        patterns,
        {nil, []},
        fn %Pattern{expr: expr, guard: g1, notes: n1}, {g2, n2} ->
          {expr, {combine_guards(g1, g2), n1 ++ n2}}
        end
      )

    Pattern.new(exprs, guard: guard, notes: notes)
  end

  @doc """
  Adds an improper tail onto a list pattern.
  """
  def with_improper_tail(%Pattern{expr: list} = list_pattern, %Pattern{} = tail)
      when is_list(list) do
    %Pattern{
      expr: improper_tail_expr(list, tail.expr),
      guard: combine_guards(list_pattern.guard, tail.guard),
      notes: list_pattern.notes ++ tail.notes
    }
  end

  defp improper_tail_expr([last], tail_expr), do: [{:|, [], [last, tail_expr]}]
  defp improper_tail_expr([x | xs], tail_expr), do: [x | improper_tail_expr(xs, tail_expr)]

  defp combine_guards(nil, guard), do: guard
  defp combine_guards(guard, nil), do: guard
  defp combine_guards(g1, {_, meta, _} = g2), do: {:and, meta, [g2, g1]}
end
