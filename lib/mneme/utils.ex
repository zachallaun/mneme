defmodule Mneme.Utils do
  @moduledoc false

  @test_attr :mneme
  @describe_attr :describe_mneme
  @module_attr :module_mneme

  @doc """
  Register ExUnit attributes for controlling Mneme behavior.
  """
  defmacro register_attributes do
    quote do
      ExUnit.Case.register_attribute(
        __MODULE__,
        unquote(@test_attr),
        accumulate: true
      )

      ExUnit.Case.register_describe_attribute(
        __MODULE__,
        unquote(@describe_attr),
        accumulate: true
      )

      ExUnit.Case.register_module_attribute(
        __MODULE__,
        unquote(@module_attr),
        accumulate: true
      )
    end
  end

  @doc """
  Collect all registered Mneme attributes from the given tags, in order of precedence.

  ## Examples

      iex> collect_attributes(%{})
      %{}

      iex> collect_attributes(%{registered: %{}})
      %{}

      iex> collect_attributes(%{
      ...>   registered: %{
      ...>     mneme: [[bar: 2], [bar: 1]]
      ...>   }
      ...> })
      %{bar: [2, 1]}

      iex> collect_attributes(%{
      ...>   registered: %{
      ...>      module_mneme: [[foo: 1]],
      ...>      describe_mneme: [[bar: 2], [foo: 2, bar: 1]],
      ...>      mneme: [[bar: 3, baz: 1]]
      ...>   }
      ...> })
      %{foo: [2, 1], bar: [3, 2, 1], baz: [1]}
  """
  def collect_attributes(%{registered: %{} = attrs}) do
    %{}
    |> collect_attributes(Map.get(attrs, @test_attr, []))
    |> collect_attributes(Map.get(attrs, @describe_attr, []))
    |> collect_attributes(Map.get(attrs, @module_attr, []))
  end

  def collect_attributes(_), do: %{}

  defp collect_attributes(acc, lower_priority) do
    new =
      for kw <- lower_priority,
          {k, v} <- kw,
          reduce: %{} do
        acc -> Map.update(acc, k, [v], &[v | &1])
      end
      |> Enum.map(fn {k, vs} -> {k, Enum.reverse(vs)} end)
      |> Map.new()

    Map.merge(acc, new, fn _, vs1, vs2 -> vs1 ++ vs2 end)
  end
end
