defmodule Mneme.Assertion.Pattern do
  @moduledoc false

  alias __MODULE__

  @enforce_keys [:expr]
  defstruct [:expr, match_kind: :match, guard: nil, notes: []]

  @type t :: %Pattern{
          expr: term(),
          match_kind: match_kind(),
          guard: Macro.t() | nil,
          notes: [String.t()]
        }

  @type match_kind :: :match | :text_match

  @doc """
  Creates a new pattern.
  """
  def new(expr, attrs \\ []) do
    struct(Pattern, Keyword.put(attrs, :expr, expr))
  end

  @doc """
  Combines a list of patterns into a single list pattern.
  """
  def combine(patterns) when is_list(patterns) do
    {exprs, {guard, notes}} =
      Enum.map_reduce(
        patterns,
        {nil, []},
        fn
          %Pattern{match_kind: :match, expr: expr, guard: g1, notes: n1}, {g2, n2} ->
            {expr, {combine_guards(g1, g2), n1 ++ n2}}

          %Pattern{} = pattern, _ ->
            raise """
            (invariant) cannot combine pattern unless `:match_kind` is `:match`:

              #{inspect(pattern)}

            patterns:

              #{inspect(patterns)}
            """
        end
      )

    Pattern.new(exprs, guard: guard, notes: notes)
  end

  defp combine_guards(nil, guard), do: guard
  defp combine_guards(guard, nil), do: guard
  defp combine_guards(g1, {_, meta, _} = g2), do: {:and, meta, [g2, g1]}
end
