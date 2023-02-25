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
    quote do
      Mneme.Assertion.run!(
        unquote(Macro.escape(code)),
        unquote(value_expr(code)),
        unquote(assertion_context(caller)),
        binding(),
        __ENV__
      )
    end
  end

  @doc false
  def run!(code, value, context, binding, env) do
    assertion =
      new(
        code,
        value,
        Keyword.put(context, :binding, binding)
      )

    eval_binding = [{{:value, :mneme}, value} | binding]

    try do
      case Mneme.Server.register_assertion(assertion) do
        {:ok, assertion} ->
          Code.eval_quoted(assertion.eval, eval_binding, env)

        :error ->
          raise Mneme.AssertionError, message: "No pattern present"
      end
    rescue
      error in [ExUnit.AssertionError] ->
        case Mneme.Server.patch_assertion(assertion) do
          {:ok, assertion} ->
            Code.eval_quoted(assertion.eval, eval_binding, env)

          :error ->
            reraise error, [stacktrace_entry(assertion)]
        end
    end

    value
  end

  defp stacktrace_entry(assertion) do
    {assertion.module, assertion.test, 1, [file: assertion.file, line: assertion.line]}
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
    %Assertion{
      type: get_type(code),
      value: value,
      code: code,
      eval: code_for_eval(code, value),
      file: context[:file],
      line: context[:line],
      module: context[:module],
      test: context[:test],
      aliases: context[:aliases] || [],
      binding: context[:binding] || []
    }
  end

  defp get_type({_, _, [{op, _, [_, _]}]}) when op in [:<-, :==], do: :update
  defp get_type(_code), do: :new

  @doc """
  Regenerate assertion code for the given target.
  """
  def regenerate_code(assertion, target, default_pattern \\ :infer)

  def regenerate_code(%Assertion{patterns: nil} = assertion, target, default_pattern) do
    {prev_patterns, patterns} = build_and_select_pattern(assertion, default_pattern)

    assertion
    |> Map.merge(%{
      patterns: patterns,
      prev_patterns: prev_patterns
    })
    |> regenerate_code(target)
  end

  def regenerate_code(%Assertion{} = assertion, target, _) do
    new_code = to_code(assertion, target)

    assertion
    |> Map.put(:code, new_code)
    |> Map.put(:eval, code_for_eval(new_code, assertion.value))
  end

  defp build_and_select_pattern(%{value: value} = assertion, :first) do
    {[], Builder.to_patterns(value, assertion)}
  end

  defp build_and_select_pattern(%{value: value} = assertion, :last) do
    [pattern | prev] = Builder.to_patterns(value, assertion) |> Enum.reverse()
    {prev, [pattern]}
  end

  defp build_and_select_pattern(%{type: :new} = assertion, :infer) do
    build_and_select_pattern(assertion, :first)
  end

  defp build_and_select_pattern(%{type: :update, value: value, code: code} = assertion, :infer) do
    [expr, guard] =
      case code do
        {_, _, [{:<-, _, [{:when, _, [expr, guard]}, _]}]} -> [expr, guard]
        {_, _, [{:<-, _, [expr, _]}]} -> [expr, nil]
        {_, _, [{:==, _, [_, expr]}]} -> [expr, nil]
      end
      |> Enum.map(&simplify_expr/1)

    Builder.to_patterns(value, assertion)
    |> Enum.split_while(fn
      {pattern_expr, pattern_guard, _} ->
        !(simplify_expr(pattern_expr) == expr && simplify_expr(pattern_guard) == guard)

      _ ->
        true
    end)
    |> case do
      {patterns, []} -> {[], patterns}
      {prev_reverse, patterns} -> {Enum.reverse(prev_reverse), patterns}
    end
  end

  defp simplify_expr(nil), do: nil

  defp simplify_expr(expr) do
    Sourceror.prewalk(expr, fn
      {:__block__, _meta, [arg]}, state ->
        {arg, state}

      {name, _meta, args}, state ->
        {{name, [], args}, state}

      quoted, state ->
        {quoted, state}
    end)
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
  def to_code(%Assertion{code: code, value: falsy, patterns: [{expr, nil, _} | _]}, target)
      when falsy in [nil, false] do
    build_call(target, :compare, code, block_with_line(expr, meta(code)), nil)
  end

  def to_code(%Assertion{code: code, patterns: [{expr, guard, _} | _]}, target) do
    build_call(target, :match, code, block_with_line(expr, meta(code)), guard)
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

  defp code_for_eval({:__block__, _, _} = code, _value), do: code

  defp code_for_eval({_, _, [{:<-, _, [expected, _]}]}, falsy) when falsy in [false, nil] do
    assert_compare(expected)
  end

  defp code_for_eval({_, _, [pattern]}, _value) do
    case pattern do
      {match, _, [{:when, _, [expected, guard]}, _]} when match in [:<-, :=] ->
        quote do
          value = unquote(assert_match(expected))
          assert unquote(guard)
          value
        end

      {match, _, [expected, _]} when match in [:<-, :=] ->
        assert_match(expected)

      {:==, _, [_, expected]} ->
        assert_compare(expected)

      _ ->
        quote do
          raise Mneme.AssertionError, message: "no match present"
        end
    end
  end

  defp assert_compare(expr) do
    {:assert, [], [{:==, [], [normalized_expect_expr(expr), Macro.var(:value, :mneme)]}]}
  end

  defp assert_match(expr) do
    {:assert, [], [{:=, [], [normalized_expect_expr(expr), Macro.var(:value, :mneme)]}]}
  end

  defp value_expr({:__block__, _, [first, _second]}), do: value_expr(first)
  defp value_expr({_, _, [{:<-, _, [_, value_expr]}]}), do: value_expr
  defp value_expr({_, _, [{:=, _, [_, value_expr]}]}), do: value_expr
  defp value_expr({_, _, [{:==, _, [value_expr, _]}]}), do: value_expr
  defp value_expr({_, _, [value_expr]}), do: value_expr

  defp normalized_expect_expr(expect_expr) do
    expect_expr |> normalize_heredoc()
  end

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
