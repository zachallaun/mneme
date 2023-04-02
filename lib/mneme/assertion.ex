defmodule Mneme.Assertion do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Assertion.PatternBuilder

  @type context :: %{
          file: String.t(),
          line: non_neg_integer(),
          module: module(),
          test: atom(),
          aliases: list(),
          binding: list()
        }

  @type pattern :: {match :: Macro.t(), guard :: Macro.t() | nil, notes :: [String.t()]}

  @type t :: %Assertion{
          stage: :new | :update,
          value: term(),
          code: Macro.t(),
          patterns: [pattern],
          pattern_idx: non_neg_integer(),
          context: context
        }

  defstruct [
    :stage,
    :value,
    :code,
    :patterns,
    :pattern_idx,
    :context
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

    case assertion.stage do
      :new ->
        run_patch!(assertion, eval_binding, env)

      :update ->
        {:ok, assertion} = Mneme.Server.register_assertion(assertion)

        try do
          eval(assertion, eval_binding, env)
        rescue
          error in [ExUnit.AssertionError] ->
            run_patch!(assertion, eval_binding, env, error)
        end
    end

    value
  end

  defp run_patch!(assertion, eval_binding, env, error \\ nil) do
    case Mneme.Server.patch_assertion(assertion) do
      {:ok, assertion} ->
        eval(assertion, eval_binding, env)

      {:error, :skip} ->
        :ok

      {:error, :no_pattern} ->
        if error do
          reraise error, [stacktrace_entry(assertion)]
        else
          raise Mneme.AssertionError, message: "No pattern present"
        end

      {:error, {:internal, error, stacktrace}} ->
        raise Mneme.InternalError, original_error: error, original_stacktrace: stacktrace
    end
  end

  defp stacktrace_entry(%{context: context}) do
    {context.module, context.test, 1, [file: context.file, line: context.line]}
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
      stage: get_stage(code),
      value: value,
      code: code,
      context: Map.new(context)
    }
  end

  defp get_stage({_, _, [{op, _, [_, _]}]}) when op in [:<-, :==], do: :update
  defp get_stage(_code), do: :new

  @doc """
  Regenerate assertion code for the given target.
  """
  def regenerate_code(assertion, target, default_pattern \\ :infer)

  def regenerate_code(%Assertion{patterns: nil} = assertion, target, default_pattern) do
    {patterns, pattern_idx} = build_and_select_pattern(assertion, default_pattern)

    assertion
    |> Map.merge(%{
      patterns: patterns,
      pattern_idx: pattern_idx
    })
    |> regenerate_code(target)
  end

  def regenerate_code(%Assertion{} = assertion, target, _) do
    %{assertion | code: to_code(assertion, target)}
  end

  defp build_and_select_pattern(%{value: value} = assertion, :first) do
    {PatternBuilder.to_patterns(value, assertion.context), 0}
  end

  defp build_and_select_pattern(%{value: value} = assertion, :last) do
    patterns = PatternBuilder.to_patterns(value, assertion.context)
    {patterns, length(patterns) - 1}
  end

  defp build_and_select_pattern(%{stage: :new} = assertion, :infer) do
    build_and_select_pattern(assertion, :first)
  end

  defp build_and_select_pattern(%{stage: :update, value: value, code: code} = assertion, :infer) do
    [expr, guard] =
      case code do
        {_, _, [{:<-, _, [{:when, _, [expr, guard]}, _]}]} -> [expr, guard]
        {_, _, [{:<-, _, [expr, _]}]} -> [expr, nil]
        {_, _, [{:==, _, [_, expr]}]} -> [expr, nil]
      end
      |> Enum.map(&simplify_expr/1)

    PatternBuilder.to_patterns(value, assertion.context)
    |> Enum.split_while(fn
      {pattern_expr, pattern_guard, _} ->
        !(simplify_expr(pattern_expr) == expr && simplify_expr(pattern_guard) == guard)

      _ ->
        true
    end)
    |> case do
      {patterns, []} -> {patterns, 0}
      {patterns, selected} -> {patterns ++ selected, length(patterns)}
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
  def prev(%Assertion{pattern_idx: 0, patterns: ps} = assertion, target) do
    %{assertion | pattern_idx: length(ps) - 1}
    |> regenerate_code(target)
  end

  def prev(%Assertion{pattern_idx: idx} = assertion, target) do
    %{assertion | pattern_idx: idx - 1}
    |> regenerate_code(target)
  end

  @doc """
  Select the next pattern.
  """
  def next(%Assertion{pattern_idx: idx, patterns: ps} = assertion, target) do
    %{assertion | pattern_idx: rem(idx + 1, length(ps))}
    |> regenerate_code(target)
  end

  @doc """
  Returns a tuple of `{current_index, count}` of all patterns for this assertion.
  """
  def pattern_index(%Assertion{pattern_idx: idx, patterns: patterns}) do
    {idx, length(patterns)}
  end

  @doc """
  Returns the currently selected pattern.
  """
  def pattern(%Assertion{pattern_idx: idx, patterns: patterns}), do: Enum.at(patterns, idx)

  @doc """
  Returns any notes associated with the current pattern.
  """
  def notes(%Assertion{} = assertion), do: assertion |> pattern() |> elem(2)

  @doc """
  Check whether the assertion struct represents the given AST node.
  """
  def same?(%Assertion{context: %{line: line}}, node) do
    case node do
      {:auto_assert, meta, [_]} -> meta[:line] == line
      _ -> false
    end
  end

  @doc """
  Generates assertion code for the given target.
  """
  def to_code(%Assertion{code: code, value: falsy} = assertion, target)
      when falsy in [nil, false] do
    {expr, nil, _} = pattern(assertion)
    build_call(target, :compare, code, block_with_line(expr, meta(code)), nil)
  end

  def to_code(%Assertion{code: code} = assertion, target) do
    {expr, guard, _} = pattern(assertion)
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
    {:assert, meta(code), [{:=, meta(value_expr(code)), [unescape(expr), value_expr(code)]}]}
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

  defp eval(assertion, binding, env) do
    assertion
    |> code_for_eval()
    |> Code.eval_quoted(binding, env)
  end

  @doc false
  def code_for_eval(%Assertion{code: {:__block__, _, _} = code}), do: code

  def code_for_eval(%Assertion{code: {_, _, [{:<-, _, [expected, _]}]}, value: falsy})
      when falsy in [false, nil] do
    assert_compare(expected)
  end

  def code_for_eval(%Assertion{code: {_, _, [pattern]}}) do
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
        :ok
    end
  end

  defp assert_compare(expr) do
    {:assert, [], [{:==, [], [unescape(expr), Macro.var(:value, :mneme)]}]}
  end

  defp assert_match(expr) do
    {:assert, [], [{:=, [], [unescape(expr), Macro.var(:value, :mneme)]}]}
  end

  defp value_expr({:__block__, _, [first, _second]}), do: value_expr(first)
  defp value_expr({_, _, [{:<-, _, [_, value_expr]}]}), do: value_expr
  defp value_expr({_, _, [{:=, _, [_, value_expr]}]}), do: value_expr
  defp value_expr({_, _, [{:==, _, [value_expr, _]}]}), do: value_expr
  defp value_expr({_, _, [value_expr]}), do: value_expr

  defp unescape(expect_expr), do: unescape_strings(expect_expr)

  defp unescape_strings(expr) do
    Sourceror.prewalk(expr, fn
      {:__block__, meta, [string]}, state when is_binary(string) ->
        {{:__block__, meta, [Macro.unescape_string(string)]}, state}

      quoted, state ->
        {quoted, state}
    end)
  end
end
