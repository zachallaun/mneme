defmodule Mneme.Assertion do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Assertion.PatternBuilder

  defstruct [
    :stage,
    :value,
    :macro_ast,
    :rich_ast,
    :code,
    :patterns,
    :pattern_idx,
    :context
  ]

  @type t :: %Assertion{
          stage: :new | :update,
          value: term(),
          macro_ast: Macro.t(),
          rich_ast: Macro.t(),
          code: Macro.t(),
          patterns: [pattern],
          pattern_idx: non_neg_integer(),
          context: context
        }

  @type context :: %{
          file: String.t(),
          line: non_neg_integer(),
          module: module(),
          test: atom(),
          aliases: list(),
          binding: list(),
          foo: integer()
        }

  @type pattern :: {match :: Macro.t(), guard :: Macro.t() | nil, notes :: [String.t()]}

  @doc """
  Builds a quoted expression that will run the assertion.
  """
  def build(call, arg, caller) do
    macro_ast = {call, Macro.Env.location(caller), [arg]}

    quote do
      Mneme.Assertion.new(
        unquote(Macro.escape(macro_ast)),
        unquote(value_expr(macro_ast)),
        Keyword.put(unquote(assertion_context(caller)), :binding, binding())
      )
      |> Mneme.Assertion.run(__ENV__, Mneme.Server.started?())
    end
  end

  @doc false
  def assertion_context(caller) do
    {test, _arity} = caller.function

    [
      test: test,
      file: caller.file,
      line: caller.line,
      module: caller.module,
      aliases: caller.aliases
    ]
  end

  @doc """
  Run an auto-assertion, potentially patching the code.
  """
  def run(assertion, env, interactive? \\ true)

  def run(assertion, env, true) do
    case assertion.stage do
      :new ->
        patch(assertion, env)

      :update ->
        {:ok, assertion} = Mneme.Server.register_assertion(assertion)

        try do
          eval(assertion, env)
        rescue
          error in [ExUnit.AssertionError] ->
            patch(assertion, env, error)
        end
    end

    assertion.value
  end

  def run(assertion, env, false) do
    case assertion.stage do
      :new -> assertion_error!()
      :update -> eval(assertion, env)
    end
  rescue
    error ->
      warn_non_interactive()
      reraise error, __STACKTRACE__
  end

  defp warn_non_interactive do
    [
      [:yellow, "warning: ", :default_color],
      "Mneme is running in non-interactive mode. Ensure that `Mneme.start()` is called before auto-assertions run."
    ]
    |> IO.ANSI.format()
    |> IO.puts()
  end

  @doc """
  Create an assertion struct.
  """
  def new(macro_ast, value, context) do
    %Assertion{
      stage: get_stage(macro_ast),
      macro_ast: macro_ast,
      value: value,
      context: Map.new(context)
    }
  end

  defp get_stage({_, _, [{:<-, _, [_, _]}]}), do: :update
  defp get_stage(_ast), do: :new

  defp patch(assertion, env, error \\ nil) do
    case Mneme.Server.patch_assertion(assertion) do
      {:ok, assertion} ->
        eval(assertion, env)

      {:error, :skip} ->
        :ok

      {:error, :no_pattern} ->
        if error do
          reraise error, [stacktrace_entry(assertion)]
        else
          assertion_error!()
        end

      {:error, {:internal, error, stacktrace}} ->
        raise Mneme.InternalError, original_error: error, original_stacktrace: stacktrace
    end
  end

  defp stacktrace_entry(%{context: context}) do
    {context.module, context.test, 1, [file: context.file, line: context.line]}
  end

  defp assertion_error!(message \\ "No pattern present") do
    raise Mneme.AssertionError, message: message
  end

  @doc """
  Set the rich AST from Sourceror for the given assertion.
  """
  def put_rich_ast(%Assertion{rich_ast: nil} = assertion, ast) do
    %{assertion | rich_ast: ast}
  end

  @doc """
  Generate output code for the given target.
  """
  def generate_code(assertion, target, default_pattern \\ :infer)

  def generate_code(%Assertion{rich_ast: nil}, _, _) do
    raise ArgumentError, "cannot generate code until `:rich_ast` has been set"
  end

  def generate_code(%Assertion{patterns: nil} = assertion, target, default_pattern) do
    {patterns, pattern_idx} = build_and_select_pattern(assertion, default_pattern)

    assertion
    |> Map.merge(%{
      patterns: patterns,
      pattern_idx: pattern_idx
    })
    |> generate_code(target)
  end

  def generate_code(%Assertion{} = assertion, target, _) do
    %{assertion | code: assertion |> to_code(target) |> escape_strings()}
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

  defp build_and_select_pattern(
         %{stage: :update, value: value, rich_ast: ast} = assertion,
         :infer
       ) do
    [expr, guard] =
      case ast do
        {_, _, [{:<-, _, [{:when, _, [expr, guard]}, _]}]} -> [expr, guard]
        {_, _, [{:<-, _, [expr, _]}]} -> [expr, nil]
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
  def prev(%Assertion{pattern_idx: 0, patterns: ps} = assertion) do
    %{assertion | pattern_idx: length(ps) - 1}
  end

  def prev(%Assertion{pattern_idx: idx} = assertion) do
    %{assertion | pattern_idx: idx - 1}
  end

  @doc """
  Select the next pattern.
  """
  def next(%Assertion{pattern_idx: idx, patterns: ps} = assertion) do
    %{assertion | pattern_idx: rem(idx + 1, length(ps))}
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
  def to_code(%Assertion{rich_ast: ast, value: value} = assertion, target) do
    {expr, guard, _} = pattern(assertion)
    build_call(target, :match, ast, block_with_line(expr, meta(ast)), guard, value)
  end

  # This gets around a bug in Elixir's `Code.Normalizer` prior to this
  # PR being merged: https://github.com/elixir-lang/elixir/pull/12389
  defp block_with_line({call, meta, args}, parent_meta) do
    {call, Keyword.put(meta, :line, parent_meta[:line]), args}
  end

  defp block_with_line(value, parent_meta) do
    {:__block__, [line: parent_meta[:line]], [value]}
  end

  defp build_call(:mneme, :match, ast, expr, nil, _value) do
    {:auto_assert, meta(ast), [{:<-, meta(value_expr(ast)), [expr, value_expr(ast)]}]}
  end

  defp build_call(:mneme, :match, ast, expr, guard, _value) do
    {:auto_assert, meta(ast),
     [{:<-, meta(value_expr(ast)), [{:when, [], [expr, guard]}, value_expr(ast)]}]}
  end

  defp build_call(:ex_unit, :match, ast, expr, nil, falsy) when falsy in [false, nil] do
    {:assert, meta(ast), [{:==, meta(value_expr(ast)), [value_expr(ast), expr]}]}
  end

  defp build_call(:ex_unit, :match, ast, expr, nil, _value) do
    {:assert, meta(ast), [{:=, meta(value_expr(ast)), [unescape(expr), value_expr(ast)]}]}
  end

  defp build_call(:ex_unit, :match, ast, expr, guard, value) do
    check = build_call(:ex_unit, :match, ast, expr, nil, value)

    quote do
      unquote(check)
      assert unquote(guard)
    end
  end

  defp meta({_, meta, _}), do: meta
  defp meta(_), do: []

  defp eval(%{value: value, context: context} = assertion, env) do
    binding = [{{:value, :mneme}, value} | context.binding]

    assertion
    |> code_for_eval()
    |> Code.eval_quoted(binding, env)
  end

  @doc false
  def code_for_eval(%Assertion{code: nil, macro_ast: ast, value: value}) do
    code_for_eval(ast, value)
  end

  def code_for_eval(%Assertion{code: code, value: value}) do
    code_for_eval(code, value)
  end

  # Only case it's a block is if the output target is :ex_unit, so we eval directly
  def code_for_eval({:__block__, _, _} = code, _value), do: code

  def code_for_eval({_, _, [{_, _, [expr, _]}]}, falsy) when falsy in [nil, false] do
    {:assert, [], [{:==, [], [unescape(expr), Macro.var(:value, :mneme)]}]}
  end

  def code_for_eval({_, _, [{_, _, [{:when, _, [expected, guard]}, _]}]}, _value) do
    quote do
      value = unquote(assert_match(expected))
      assert unquote(guard)
      value
    end
  end

  def code_for_eval({_, _, [{_, _, [expected, _]}]}, _value) do
    assert_match(expected)
  end

  defp assert_match(expr) do
    {:assert, [], [{:=, [], [unescape(expr), Macro.var(:value, :mneme)]}]}
  end

  defp value_expr({:__block__, _, [first, _second]}), do: value_expr(first)
  defp value_expr({_, _, [{:<-, _, [_, value_expr]}]}), do: value_expr
  defp value_expr({_, _, [{:=, _, [_, value_expr]}]}), do: value_expr
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

  defp escape_strings(code) when is_list(code) do
    Enum.map(code, &escape_strings/1)
  end

  defp escape_strings(code) do
    Sourceror.prewalk(code, fn
      {:__block__, meta, [string]} = quoted, state when is_binary(string) ->
        case meta[:delimiter] do
          "\"" -> {{:__block__, meta, [escape_string(string)]}, state}
          _ -> {quoted, state}
        end

      quoted, state ->
        {quoted, state}
    end)
  end

  defp escape_string(string) when is_binary(string) do
    string
    |> String.replace("\n", "\\n")
    |> String.replace("\#{", "\\\#{")

    # |> String.replace("\"", "\\\"")
  end
end
