defmodule Mneme.Utils do
  @moduledoc false

  @doc """
  Returns the occurrences of a given character in a string.

  ## Examples

      iex> occurrences("foo", ?o)
      2

      iex> occurrences("foo", ?z)
      0

  """
  def occurrences(string, char) when is_binary(string) and is_integer(char) do
    occurrences(string, char, 0)
  end

  defp occurrences(<<char, rest::binary>>, char, acc), do: occurrences(rest, char, acc + 1)
  defp occurrences(<<_, rest::binary>>, char, acc), do: occurrences(rest, char, acc)
  defp occurrences(<<>>, _char, acc), do: acc

  @doc """
  Macro expands an expression in a pattern match context.
  """
  @spec expand_pattern(Macro.t(), Macro.Env.t()) :: Macro.t()
  def expand_pattern({:when, meta, [left, right]}, caller) do
    left = do_expand_pattern(left, Macro.Env.to_match(caller))
    right = do_expand_pattern(right, %{caller | context: :guard})
    {:when, meta, [left, right]}
  end

  def expand_pattern(expr, caller) do
    do_expand_pattern(expr, Macro.Env.to_match(caller))
  end

  defp do_expand_pattern({:quote, _, [_]} = expr, _caller), do: expr
  defp do_expand_pattern({:quote, _, [_, _]} = expr, _caller), do: expr
  defp do_expand_pattern({:__aliases__, _, _} = expr, caller), do: Macro.expand(expr, caller)

  defp do_expand_pattern({:@, _, [{attribute, _, _}]}, caller) do
    caller.module |> Module.get_attribute(attribute) |> Macro.escape()
  end

  defp do_expand_pattern({left, meta, right} = expr, caller) do
    case Macro.expand(expr, caller) do
      ^expr ->
        {do_expand_pattern(left, caller), meta, do_expand_pattern(right, caller)}

      {left, meta, right} ->
        {do_expand_pattern(left, caller), [original: expr] ++ meta,
         do_expand_pattern(right, caller)}

      other ->
        other
    end
  end

  defp do_expand_pattern({left, right}, caller) do
    {do_expand_pattern(left, caller), do_expand_pattern(right, caller)}
  end

  defp do_expand_pattern([_ | _] = list, caller) do
    Enum.map(list, &do_expand_pattern(&1, caller))
  end

  defp do_expand_pattern(other, _caller), do: other

  @doc """
  Collects variables bound in the given pattern.
  """
  @spec collect_vars_from_pattern(Macro.t()) :: [var] when var: {atom(), Macro.metadata(), atom()}
  def collect_vars_from_pattern({:when, _, [left, right]}) do
    pattern = collect_vars_from_pattern(left)

    vars =
      for {name, _, context} = var <- collect_vars_from_pattern(right),
          has_var?(pattern, name, context),
          do: var

    pattern ++ vars
  end

  def collect_vars_from_pattern(expr) do
    expr
    |> Macro.prewalk([], fn
      {:"::", _, [left, right]}, acc ->
        {[left], collect_vars_from_binary(right, acc)}

      {skip, _, [_]}, acc when skip in [:^, :@, :quote] ->
        {:ok, acc}

      {skip, _, [_, _]}, acc when skip in [:quote] ->
        {:ok, acc}

      {:_, _, context}, acc when is_atom(context) ->
        {:ok, acc}

      {name, meta, context}, acc when is_atom(name) and is_atom(context) ->
        {:ok, [{name, meta, context} | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp collect_vars_from_binary(right, original_acc) do
    right
    |> Macro.prewalk(original_acc, fn
      {mode, _, [{name, meta, context}]}, acc
      when is_atom(mode) and is_atom(name) and is_atom(context) ->
        if has_var?(original_acc, name, context) do
          {:ok, [{name, meta, context} | acc]}
        else
          {:ok, acc}
        end

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp has_var?(pattern, name, context), do: Enum.any?(pattern, &match?({^name, _, ^context}, &1))
end
