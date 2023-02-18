defmodule Mneme.AssertionError do
  defexception [:message]
end

defmodule Mneme.Assertion do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Assertion.Builder

  defstruct [
    :type,
    :value,
    :code,
    :eval,
    :file,
    :line,
    :module,
    :test,
    :patterns,
    aliases: [],
    binding: [],
    prev_patterns: []
  ]

  @doc """
  Build an assertion.
  """
  def build(code, caller) do
    vars = code |> pattern_expr() |> collect_vars_from_pattern()

    quote do
      value = unquote(value_expr(code))

      var!(binding_acc, :mneme) = Keyword.get(binding(:mneme), :binding_acc, [])
      lookup_binding = Enum.uniq_by(binding() ++ var!(binding_acc, :mneme), &elem(&1, 0))

      eval_binding =
        Enum.uniq_by(
          binding() ++ [{{:value, :mneme}, value}] ++ binding() ++ var!(binding_acc, :mneme),
          &elem(&1, 0)
        )

      assertion =
        Mneme.Assertion.new(
          unquote(Macro.escape(code)),
          value,
          unquote(assertion_context(caller)) |> Keyword.put(:binding, lookup_binding)
        )

      {unquote(mark_as_generated(vars)), new_binding} =
        try do
          case Mneme.Server.register_assertion(assertion) do
            {:ok, assertion} ->
              Assertion.eval(assertion, eval_binding, __ENV__, unquote(Macro.escape(vars)))

            :error ->
              raise Mneme.AssertionError, message: "No pattern present"
          end
        rescue
          error in [ExUnit.AssertionError] ->
            case Mneme.Server.patch_assertion(assertion) do
              {:ok, assertion} ->
                Assertion.eval(assertion, eval_binding, __ENV__, unquote(Macro.escape(vars)))

              :error ->
                case __STACKTRACE__ do
                  [head | _] -> reraise error, [head]
                  [] -> reraise error, []
                end
            end
        end

      var!(binding_acc, :mneme) = new_binding ++ var!(binding_acc, :mneme)
      value
    end
  end

  defp assertion_context(caller) do
    {test, _arity} = caller.function

    [
      file: caller.file,
      line: caller.line,
      module: caller.module,
      test: test,
      # TODO: Macro.Env :aliases is technically private; so we should
      # access some other way
      aliases: caller.aliases
    ]
  end

  @doc false
  def new(code, value, context) do
    assertion = %Assertion{
      type: get_type(code),
      value: value,
      code: code,
      file: context[:file],
      line: context[:line],
      module: context[:module],
      test: context[:test],
      aliases: context[:aliases] || [],
      binding: context[:binding] || []
    }

    {prev_patterns, patterns} = build_and_select_pattern(assertion)

    Map.merge(assertion, %{
      patterns: patterns,
      prev_patterns: prev_patterns,
      eval: code_for_eval(code, hd(patterns))
    })
  end

  defp mark_as_generated(vars) do
    for {name, meta, context} <- vars do
      {name, [generated: true] ++ meta, context}
    end
  end

  defp collect_vars_from_pattern({:when, _, [expr, guard]}) do
    expr_vars = collect_vars_from_pattern(expr)

    guard_vars =
      for {name, _, context} = var <- collect_vars_from_pattern(guard),
          has_var?(expr_vars, name, context) do
        var
      end

    expr_vars ++ guard_vars
  end

  defp collect_vars_from_pattern(expr) do
    Macro.prewalk(expr, [], fn
      {:"::", _, [left, right]}, acc ->
        {[left], collect_vars_from_binary(right, acc)}

      {skip, _, [_]}, acc when skip in [:^, :@] ->
        {:ok, acc}

      {:_, _, context}, acc when is_atom(context) ->
        {:ok, acc}

      {_, [{:expanded, expanded} | _], _}, acc ->
        {[expanded], acc}

      {name, meta, context}, acc when is_atom(name) and is_atom(context) ->
        {:ok, [{name, meta, context} | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp collect_vars_from_binary(right, original_acc) do
    Macro.prewalk(right, original_acc, fn
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

  @doc false
  def eval(%Assertion{} = assertion, binding, env, vars) do
    {_result, binding} = Code.eval_quoted(assertion.eval, binding, env)
    {var_bindings(vars, binding), sanitize_binding(binding)}
  end

  defp var_bindings(vars, binding) do
    Enum.map(vars, fn {name, _, _} ->
      case List.keyfind(binding, name, 0) do
        {_, value} -> value
        nil -> :__mneme_var_no_longer_bound__
      end
    end)
  end

  defp sanitize_binding(binding) do
    Enum.filter(binding, fn
      {name, _} when is_atom(name) -> true
      _ -> false
    end)
  end

  defp build_and_select_pattern(%{type: :new, value: value} = assertion) do
    {[], Builder.to_patterns(value, assertion)}
  end

  defp build_and_select_pattern(%{type: :update, value: value, code: code} = assertion) do
    {expr, guard} =
      case code do
        {_, _, [{:<-, _, [{:when, _, [expr, guard]}, _]}]} -> {expr, guard}
        {_, _, [{:<-, _, [expr, _]}]} -> {expr, nil}
        {_, _, [{:==, _, [_, expr]}]} -> {expr, nil}
      end

    Builder.to_patterns(value, assertion)
    |> Enum.split_while(fn
      {^expr, ^guard, _} -> false
      _ -> true
    end)
    |> case do
      {patterns, []} -> {[], patterns}
      {prev_reverse, patterns} -> {Enum.reverse(prev_reverse), patterns}
    end
  end

  defp get_type({_, _, [{op, _, [_, _]}]}) when op in [:<-, :==], do: :update
  defp get_type(_code), do: :new

  @doc """
  Regenerate assertion code for the given target.
  """
  def regenerate_code(%Assertion{} = assertion, target) do
    new_code = to_code(assertion, target)

    assertion
    |> Map.put(:code, new_code)
    |> Map.put(:eval, code_for_eval(new_code, hd(assertion.patterns)))
  end

  @doc """
  Select the previous pattern.
  """
  def prev(%Assertion{prev_patterns: [prev | rest], patterns: patterns} = assertion, target) do
    %{assertion | prev_patterns: rest, patterns: [prev | patterns]}
    |> regenerate_code(target)
  end

  def prev(%Assertion{prev_patterns: [], patterns: patterns} = assertion, target) do
    [pattern | new_prev] = Enum.reverse(patterns)

    %{assertion | prev_patterns: new_prev, patterns: [pattern]}
    |> regenerate_code(target)
  end

  @doc """
  Select the next pattern.
  """
  def next(%Assertion{prev_patterns: prev, patterns: [current]} = assertion, target) do
    %{assertion | prev_patterns: [], patterns: Enum.reverse(prev) ++ [current]}
    |> regenerate_code(target)
  end

  def next(%Assertion{prev_patterns: prev, patterns: [current | rest]} = assertion, target) do
    %{assertion | prev_patterns: [current | prev], patterns: rest}
    |> regenerate_code(target)
  end

  @doc """
  Returns a tuple of `{current_index, count}` of all patterns for this assertion.
  """
  def pattern_index(%Assertion{prev_patterns: prev, patterns: patterns}) do
    {length(prev), length(prev) + length(patterns)}
  end

  @doc """
  Returns any notes associated with the current pattern.
  """
  def notes(%Assertion{patterns: [{_, _, notes} | _]}), do: notes

  @doc """
  Check whether the assertion struct represents the given AST node.
  """
  def same?(%Assertion{line: line}, node) do
    case node do
      {:auto_assert, meta, [_]} -> meta[:line] == line
      _ -> false
    end
  end

  @doc """
  Generates assertion code for the given target.
  """
  def to_code(assertion, target) do
    case assertion.patterns do
      [{falsy, nil, _} | _] when falsy in [nil, false] ->
        build_call(
          target,
          :compare,
          assertion.code,
          block_with_line(falsy, meta(assertion.code)),
          nil
        )

      [{expr, guard, _} | _] ->
        build_call(
          target,
          :match,
          assertion.code,
          block_with_line(expr, meta(assertion.code)),
          guard
        )
    end
  end

  # This gets around a bug in Elixir's `Code.Normalizer` prior to this
  # PR being merged: https://github.com/elixir-lang/elixir/pull/12389
  defp block_with_line({call, meta, args}, parent_meta) do
    {call, Keyword.put(meta, :line, parent_meta[:line]), args}
  end

  defp block_with_line(value, parent_meta) do
    {:__block__, [line: parent_meta[:line]], [value]}
  end

  defp build_call(:mneme, :compare, code, falsy_expr, nil) do
    {:auto_assert, meta(code), [{:==, meta(value_expr(code)), [value_expr(code), falsy_expr]}]}
  end

  defp build_call(:mneme, :match, code, expr, nil) do
    {:auto_assert, meta(code), [{:<-, meta(value_expr(code)), [expr, value_expr(code)]}]}
  end

  defp build_call(:mneme, :match, code, expr, guard) do
    {:auto_assert, meta(code),
     [{:<-, meta(value_expr(code)), [{:when, [], [expr, guard]}, value_expr(code)]}]}
  end

  defp build_call(:ex_unit, :compare, code, falsy, nil) do
    {:assert, meta(code), [{:==, meta(value_expr(code)), [value_expr(code), falsy]}]}
  end

  defp build_call(:ex_unit, :match, code, expr, nil) do
    {:assert, meta(code),
     [{:=, meta(value_expr(code)), [normalize_heredoc(expr), value_expr(code)]}]}
  end

  defp build_call(:ex_unit, :match, code, expr, guard) do
    check = build_call(:ex_unit, :match, code, expr, nil)

    quote do
      unquote(check)
      assert unquote(guard)
    end
  end

  defp meta({_, meta, _}), do: meta
  defp meta(_), do: []

  defp code_for_eval(code, {falsy, nil, _}) when falsy in [nil, false] do
    build_eval(:compare, code, falsy, nil)
  end

  defp code_for_eval(code, {expr, guard, _}) do
    build_eval(:match, code, expr, guard)
  end

  defp build_eval(_, {:__block__, _, _} = code, _, _) do
    code
  end

  defp build_eval(:compare, code, _falsy, nil) do
    {:assert, [], [{:==, [], [normalized_expect_expr(code), Macro.var(:value, :mneme)]}]}
  end

  defp build_eval(:match, code, _expr, nil) do
    {:assert, [], [{:=, [], [normalized_expect_expr(code), Macro.var(:value, :mneme)]}]}
  end

  defp build_eval(:match, code, expr, guard) do
    check = build_eval(:match, code, expr, nil)

    quote do
      value = unquote(check)
      assert unquote(guard)
      value
    end
  end

  @doc false
  def pattern_expr({_, _, [{:<-, _, [{:when, _, [pattern, _]}, _]}]}), do: pattern
  def pattern_expr({_, _, [{:<-, _, [pattern, _]}]}), do: pattern
  def pattern_expr(_), do: Macro.var(:_, nil)

  @doc false
  def value_expr({:__block__, _, [first, _second]}), do: value_expr(first)
  def value_expr({_, _, [{:<-, _, [_, value_expr]}]}), do: value_expr
  def value_expr({_, _, [{:=, _, [_, value_expr]}]}), do: value_expr
  def value_expr({_, _, [{:==, _, [value_expr, _]}]}), do: value_expr
  def value_expr({_, _, [value_expr]}), do: value_expr

  defp normalized_expect_expr({_, _, [{:<-, _, [expect_expr, _]}]}) do
    expect_expr |> normalize_heredoc()
  end

  defp normalized_expect_expr({_, _, [{:=, _, [expect_expr, _]}]}) do
    expect_expr |> normalize_heredoc()
  end

  defp normalized_expect_expr({_, _, [{:==, _, [_, expect_expr]}]}) do
    expect_expr |> normalize_heredoc()
  end

  defp normalized_expect_expr(expect_expr), do: expect_expr

  # Allows us to format multiline strings as heredocs when they don't
  # end with a newline, e.g.
  #
  #     """
  #     some
  #     thing\
  #     """
  #
  # In order to format correctly, the heredoc must end with "\\\n", but
  # but when that content is re-parsed, the backslash and newline are
  # not present in the string. Unless we remove it prior to running an
  # ExUnit assertion, the assertion will fail, but then succeed the next
  # time the test is run.
  defp normalize_heredoc({:__block__, meta, [string]} = expr) when is_binary(string) do
    if meta[:delimiter] == ~S(""") do
      {:__block__, meta, [String.trim_trailing(string, "\\\n")]}
    else
      expr
    end
  end

  defp normalize_heredoc(expr), do: expr
end
