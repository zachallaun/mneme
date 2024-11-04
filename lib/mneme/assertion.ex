defmodule Mneme.Assertion do
  @moduledoc false

  import Sourceror.Identifier, only: [is_identifier: 1]

  alias Mneme.Assertion
  alias Mneme.Assertion.Context
  alias Mneme.Assertion.Pattern
  alias Mneme.Assertion.PatternBuilder
  alias Mneme.Utils

  defstruct [
    :kind,
    :stage,
    :value,
    :macro_ast,
    :rich_ast,
    :patterns,
    :pattern_idx,
    :context,
    :options,
    vars_bound_in_pattern: []
  ]

  @type t :: %Assertion{
          kind: kind,
          stage: :new | :update,
          value: term(),
          macro_ast: Macro.t(),
          rich_ast: Macro.t(),
          patterns: [Pattern.t()],
          pattern_idx: non_neg_integer(),
          context: Context.t(),
          options: map(),
          vars_bound_in_pattern: [macro_var]
        }

  @type kind ::
          :auto_assert
          | :auto_assert_raise
          | :auto_assert_receive
          | :auto_assert_received

  @type target :: :mneme | :ex_unit

  @type macro_var :: {atom(), Macro.metadata(), atom()}

  @doc false
  def new({kind, _, args} = macro_ast, value, ctx, vars \\ [], opts \\ Mneme.Options.options()) do
    {stage, original_pattern} = get_stage(kind, args)
    context = Enum.into(ctx, %{original_pattern: original_pattern})

    %Assertion{
      kind: kind,
      stage: stage,
      macro_ast: macro_ast,
      value: value,
      context: struct!(Context, context),
      options: Map.new(opts),
      vars_bound_in_pattern: vars
    }
  end

  @doc """
  Builds a quoted expression that will run the assertion.
  """
  @spec build(atom(), [term()], Macro.Env.t(), keyword()) :: Macro.t()
  def build(kind, args, caller, opts) do
    maybe_warn(kind, args, caller)

    macro_ast = {kind, Macro.Env.location(caller), args}
    context = extract_assertion_context(caller)
    vars = maybe_collect_vars(kind, args, caller)

    quote do
      unquote_splicing(silence_used_aliases(macro_ast, context[:aliases]))

      ast = unquote(Macro.escape(macro_ast))

      assertion =
        Mneme.Assertion.new(
          ast,
          unquote(value_eval_expr(macro_ast)),
          Keyword.put(unquote(context), :binding, binding()),
          unquote(Macro.escape(vars)),
          unquote(opts)
        )

      {assertion, binding} = Mneme.Assertion.run!(assertion, __ENV__, Mneme.Server.started?())

      unquote(vars) = Mneme.Assertion.ensure_vars!(assertion, binding)

      assertion.value
    end
  end

  defp maybe_collect_vars(:auto_assert, [{matcher, _, [left, _right]}], caller)
       when matcher in [:<-, :=] do
    left
    |> Utils.expand_pattern(caller)
    |> Utils.collect_vars_from_pattern()
    |> Enum.uniq()
  end

  defp maybe_collect_vars(_, _, _), do: []

  @doc false
  def ensure_vars!(%Assertion{} = assertion, binding) do
    binding_map = Map.new(binding)

    result =
      assertion.vars_bound_in_pattern
      |> Enum.map(fn
        {var, _, nil} -> var
        {var, _, context} -> {var, context}
      end)
      |> Enum.reduce(%{values: [], missing: []}, fn var, acc ->
        if value = binding_map[var] do
          update_in(acc.values, &[value | &1])
        else
          update_in(acc.missing, &[var | &1])
        end
      end)

    case result do
      %{values: rev_values, missing: []} ->
        Enum.reverse(rev_values)

      %{missing: missing_vars} ->
        raise Mneme.UnboundVariableError, vars: missing_vars
    end
  end

  # Prevents warnings about unused aliases when their only usage is in an auto-assertion
  defp silence_used_aliases(macro_ast, context_aliases) do
    macro_ast
    |> extract_used_aliases(context_aliases)
    |> Enum.map(&quoted_dummy_assign/1)
  end

  defp extract_used_aliases(quoted, aliases) do
    quoted
    |> Macro.prewalker()
    |> Enum.filter(fn
      {:__aliases__, _, [maybe_alias | _]} when is_atom(maybe_alias) ->
        module = Module.concat([maybe_alias])
        Keyword.has_key?(aliases, module)

      _ ->
        false
    end)
  end

  defp quoted_dummy_assign(expr) do
    {:=, [], [Macro.var(:_, nil), expr]}
  end

  @doc false
  def extract_assertion_context(caller) do
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
  Run an assertion, potentially patching the code.

  Returns the assertion and binding resulting from running it. Raises if
  the assertion fails.
  """
  @spec run!(t, Macro.Env.t(), boolean()) :: {t, Code.binding()}
  def run!(assertion, env, interactive? \\ true) do
    do_run(assertion, env, interactive?)
  rescue
    error in [ExUnit.AssertionError] ->
      updated_error = %{error | expr: assertion.macro_ast}
      reraise updated_error, __STACKTRACE__
  end

  defp do_run(assertion, env, true) do
    case assertion.stage do
      :new ->
        patch(assertion, env)

      :update ->
        try do
          assertion
          |> Mneme.Server.register_assertion()
          |> handle_assertion(assertion, env)
        rescue
          error in [ExUnit.AssertionError] ->
            patch(assertion, env, error)
        end
    end
  end

  defp do_run(assertion, env, false) do
    case assertion.stage do
      :new -> assertion_error!()
      :update -> eval(assertion, env)
    end
  rescue
    error ->
      warn_non_interactive()
      reraise error, __STACKTRACE__
  end

  defp patch(assertion, env, existing_error \\ nil) do
    result =
      case assertion do
        %{kind: :auto_assert_raise, value: nil} -> {:ok, assertion}
        %{kind: :auto_assert_receive, value: []} -> {:ok, assertion}
        %{kind: :auto_assert_received, value: []} -> {:ok, assertion}
        _ -> Mneme.Server.patch_assertion(assertion)
      end

    handle_assertion(result, assertion, env, existing_error)
  end

  defp handle_assertion(result, assertion, env, existing_error \\ nil)

  defp handle_assertion({:ok, assertion}, _, env, _) do
    {_, binding} = eval(assertion, env)
    {assertion, binding}
  end

  defp handle_assertion({:error, :skipped}, assertion, _, _), do: {assertion, []}
  defp handle_assertion({:error, :file_changed}, assertion, _, _), do: {assertion, []}
  defp handle_assertion({:error, :rejected}, _, _, nil), do: assertion_error!()

  defp handle_assertion({:error, :rejected}, assertion, _, error) do
    reraise error, [stacktrace_entry(assertion)]
  end

  defp handle_assertion({:error, {:internal, error, stacktrace}}, _, _, _) do
    raise Mneme.InternalError, original_error: error, original_stacktrace: stacktrace
  end

  defp handle_assertion({:error, {:internal, error}}, _, _, _) do
    raise Mneme.InternalError, original_error: error, original_stacktrace: []
  end

  defp eval(%{value: value, context: ctx} = assertion, env) do
    binding = [{{:value, :mneme}, value} | ctx.binding]

    assertion
    |> code_for_eval()
    |> Code.eval_quoted(binding, env)
  end

  defp stacktrace_entry(%{context: ctx}) do
    {ctx.module, ctx.test, 1, [file: ctx.file, line: ctx.line]}
  end

  defp assertion_error!(message \\ "No pattern present") do
    raise Mneme.AssertionError, message: message
  rescue
    error ->
      reraise error, prune_stacktrace(__STACKTRACE__)
  end

  # This runner module will be at the head of the stacktrace. Once it
  # isn't, return the remainder.
  defp prune_stacktrace([{__MODULE__, _, _, _} | t]), do: prune_stacktrace(t)
  defp prune_stacktrace(stacktrace), do: stacktrace

  defp get_stage(:auto_assert, [{:<-, _, [pattern, _]}]), do: {:update, pattern}
  defp get_stage(:auto_assert, _args), do: {:new, nil}

  defp get_stage(:auto_assert_raise, [exception, message, _]), do: {:update, {exception, message}}
  defp get_stage(:auto_assert_raise, [exception, _]), do: {:update, {exception, nil}}
  defp get_stage(:auto_assert_raise, _args), do: {:new, nil}

  defp get_stage(:auto_assert_receive, [pattern, _timeout]), do: {:update, pattern}
  defp get_stage(:auto_assert_receive, [pattern]), do: {:update, pattern}
  defp get_stage(:auto_assert_receive, _args), do: {:new, nil}

  defp get_stage(:auto_assert_received, [pattern]), do: {:update, pattern}
  defp get_stage(:auto_assert_received, _args), do: {:new, nil}

  @doc """
  Set the rich AST from Sourceror for the given assertion and generate
  patterns.
  """
  def prepare_for_patch(%Assertion{rich_ast: nil} = assertion, ast) do
    assertion
    |> Map.put(:rich_ast, ast)
    |> generate_patterns()
  end

  @doc false
  def prepare_for_patch(assertion), do: generate_patterns(assertion)

  defp generate_patterns(%Assertion{patterns: nil} = assertion) do
    {patterns, pattern_idx} = build_and_select(assertion)

    assertion
    |> Map.merge(%{
      patterns: patterns,
      pattern_idx: pattern_idx
    })
    |> generate_patterns()
  end

  defp generate_patterns(%Assertion{} = assertion), do: assertion

  defp build_and_select(%{kind: kind} = assertion) do
    case kind do
      :auto_assert -> build_and_select_pattern(assertion)
      :auto_assert_raise -> build_and_select_raise(assertion)
      :auto_assert_receive -> build_and_select_receive(assertion)
      :auto_assert_received -> build_and_select_receive(assertion)
    end
  end

  defp build_and_select_receive(%{value: [_ | _] = messages, context: ctx, options: opts}) do
    patterns =
      messages
      |> Enum.map(&PatternBuilder.to_patterns(&1, ctx))
      |> Enum.map(fn patterns ->
        case opts.default_pattern do
          :first -> List.first(patterns)
          _ -> List.last(patterns)
        end
      end)

    {patterns, 0}
  end

  defp build_and_select_raise(%{value: error, macro_ast: macro_ast, context: ctx, options: opts}) do
    %exception{} = error

    patterns =
      error
      |> Exception.message()
      |> PatternBuilder.to_patterns(ctx)
      |> Enum.map(fn %Pattern{expr: message} ->
        Pattern.new({exception, message})
      end)
      |> then(&[Pattern.new({exception, nil}) | &1])

    case {opts.default_pattern, macro_ast} do
      {:infer, {_, _, [_, _, _]}} -> {patterns, 1}
      {:last, _} -> {patterns, 1}
      _ -> {patterns, 0}
    end
  end

  defp build_and_select_pattern(assertion) do
    build_and_select_pattern(assertion, assertion.options.default_pattern)
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
    subexpressions =
      case ast do
        {_, _, [{:<-, _, [{:when, _, [expr, guard]}, _]}]} -> [expr, guard]
        {_, _, [{:<-, _, [expr, _]}]} -> [expr, nil]
      end

    [expr, guard] =
      Enum.map(subexpressions, &simplify_expr/1)

    patterns = PatternBuilder.to_patterns(value, assertion.context)

    {_, index} =
      patterns
      |> Enum.with_index()
      |> Enum.max_by(fn {%Pattern{expr: pattern_expr, guard: pattern_guard}, _index} ->
        similarity_score(expr, simplify_expr(pattern_expr)) +
          similarity_score(guard, simplify_expr(pattern_guard))
      end)

    {patterns, index}
  end

  defp simplify_expr(nil), do: nil

  defp simplify_expr(expr) do
    Sourceror.prewalk(expr, fn
      {:__block__, _, [s]} = string_block, state when is_binary(s) ->
        {string_block, state}

      {:__block__, _meta, [arg]}, state ->
        {arg, state}

      {name, _meta, args}, state ->
        {{name, [], args}, state}

      quoted, state ->
        {quoted, state}
    end)
  end

  # Opaque expression similarity score. More similar expressions should
  # have a higher value, but the exact value should be not be relied on.
  defp similarity_score(left, right)

  defp similarity_score({:__block__, s1_meta, [s1]}, {:__block__, s2_meta, [s2]})
       when is_binary(s1) and is_binary(s2) do
    if s1_meta[:delimiter] == s2_meta[:delimiter] do
      1
    else
      0
    end
  end

  defp similarity_score({name, _, args1}, {name, _, args2}) do
    1 + similarity_score(args1, args2)
  end

  defp similarity_score(l1, l2) when is_list(l1) and is_list(l2) do
    # add the lesser length so that non-empty lists will be considered
    # more similar than empty ones, but lists sharing content will be
    # considered even more similar
    min(length(l1), length(l2)) +
      (l1
       |> Enum.zip(l2)
       |> Enum.map(fn {el1, el2} -> similarity_score(el1, el2) end)
       |> Enum.sum())
  end

  defp similarity_score({_, _, args1}, {_, _, args2}), do: similarity_score(args1, args2)
  defp similarity_score({key, val1}, {key, val2}), do: 1 + similarity_score(val1, val2)
  defp similarity_score({_, val1}, {_, val2}), do: similarity_score(val1, val2)
  defp similarity_score(expr, expr), do: 1
  defp similarity_score(_, _), do: 0

  @doc """
  Select a new pattern.
  """
  @spec select(t, movement) :: t when movement: :next | :prev | :first | :last
  def select(assertion, movement)

  def select(%Assertion{} = assertion, :prev) do
    if assertion.pattern_idx == 0 do
      select(assertion, :last)
    else
      select_pattern_index(assertion, assertion.pattern_idx - 1)
    end
  end

  def select(%Assertion{} = assertion, :next) do
    idx = rem(assertion.pattern_idx + 1, length(assertion.patterns))
    generate_patterns(%{assertion | pattern_idx: idx})
  end

  def select(%Assertion{} = assertion, :first) do
    select_pattern_index(assertion, 0)
  end

  def select(%Assertion{} = assertion, :last) do
    select_pattern_index(assertion, length(assertion.patterns) - 1)
  end

  defp select_pattern_index(%Assertion{} = assertion, idx) when is_integer(idx) and idx >= 0 do
    generate_patterns(%{assertion | pattern_idx: idx})
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
  Check whether the assertion struct represents the given AST node.
  """
  def same?(%Assertion{kind: kind, context: %{line: line}}, node) do
    case node do
      {^kind, meta, _} -> meta[:line] == line
      _ -> false
    end
  end

  @doc """
  Returns the currently selected AST for the assertion.
  """
  def code(%Assertion{patterns: nil} = assertion) do
    assertion.macro_ast
  end

  def code(%Assertion{} = assertion) do
    assertion
    |> build_code()
    |> escape_strings()
  end

  defp build_code(%Assertion{kind: :auto_assert_raise, options: opts} = assertion) do
    %Pattern{expr: expr} = pattern(assertion)
    build_call(opts.target, assertion, expr)
  end

  defp build_code(%Assertion{rich_ast: ast, options: opts} = assertion) do
    %Pattern{expr: expr, guard: guard} = pattern(assertion)
    build_call(opts.target, assertion, {block_with_line(expr, meta(ast)), guard})
  end

  # This gets around a bug in Elixir's `Code.Normalizer` prior to this
  # PR being merged: https://github.com/elixir-lang/elixir/pull/12389
  defp block_with_line({kind, meta, args}, parent_meta) do
    {kind, Keyword.put(meta, :line, parent_meta[:line]), args}
  end

  defp block_with_line(value, parent_meta) do
    {:__block__, [line: parent_meta[:line]], [value]}
  end

  defp build_call(:mneme, %{kind: :auto_assert, rich_ast: ast}, pattern) do
    {:auto_assert, meta(ast),
     [{:<-, meta(value_expr(ast)), [maybe_when(pattern), value_expr(ast)]}]}
  end

  defp build_call(:mneme, %{kind: :auto_assert_raise, rich_ast: ast}, {exception, nil}) do
    {:auto_assert_raise, meta(ast), [exception, value_expr(ast)]}
  end

  defp build_call(:mneme, %{kind: :auto_assert_raise, rich_ast: ast}, {exception, msg}) do
    {:auto_assert_raise, meta(ast), [exception, msg, value_expr(ast)]}
  end

  defp build_call(:mneme, %{kind: :auto_assert_receive, rich_ast: ast}, pattern) do
    {meta, args} =
      case ast do
        {_, _, [_old_pattern, timeout]} -> {meta(ast), [maybe_when(pattern), timeout]}
        {_, _, []} -> {Keyword.delete(meta(ast), :closing), [maybe_when(pattern)]}
        _ -> {meta(ast), [maybe_when(pattern)]}
      end

    {:auto_assert_receive, meta, args}
  end

  defp build_call(:mneme, %{kind: :auto_assert_received, rich_ast: ast}, pattern) do
    {:auto_assert_received, Keyword.delete(meta(ast), :closing), [maybe_when(pattern)]}
  end

  defp build_call(:ex_unit, %{kind: :auto_assert, rich_ast: ast, value: falsy}, {expr, nil})
       when falsy in [false, nil] do
    {:assert, meta(ast), [{:==, meta(value_expr(ast)), [value_expr(ast), expr]}]}
  end

  defp build_call(:ex_unit, %{kind: :auto_assert, rich_ast: ast}, {expr, nil}) do
    {:assert, meta(ast), [{:=, meta(value_expr(ast)), [unescape_strings(expr), value_expr(ast)]}]}
  end

  defp build_call(:ex_unit, %{kind: :auto_assert} = assertion, {expr, guard}) do
    check = build_call(:ex_unit, assertion, {expr, nil})

    quote do
      unquote(check)
      assert unquote(guard)
    end
  end

  defp build_call(:ex_unit, %{kind: :auto_assert_raise, rich_ast: ast}, {exception, nil}) do
    {:assert_raise, meta(ast), [exception, value_expr(ast)]}
  end

  defp build_call(:ex_unit, %{kind: :auto_assert_raise, rich_ast: ast}, {exception, msg}) do
    {:assert_raise, meta(ast), [exception, unescape_strings(msg), value_expr(ast)]}
  end

  defp build_call(:ex_unit, %{kind: :auto_assert_receive, rich_ast: ast}, pattern) do
    args =
      case ast do
        {_, _, [_old_pattern, timeout]} -> [maybe_when(pattern), timeout]
        _ -> [maybe_when(pattern)]
      end

    {:assert_receive, meta(ast), args}
  end

  defp build_call(:ex_unit, %{kind: :auto_assert_received, rich_ast: ast}, pattern) do
    {:assert_received, Keyword.delete(meta(ast), :closing), [maybe_when(pattern)]}
  end

  defp maybe_when({expr, nil}), do: expr
  defp maybe_when({expr, guard}), do: {:when, [], [expr, guard]}

  @doc false
  def code_for_eval(%Assertion{} = assertion) do
    code = code(assertion)
    code_for_eval(assertion.kind, code, assertion.value)
  end

  # Output target was :ex_unit and included a guard, so the outer
  # expression is a block
  def code_for_eval(:auto_assert, {:__block__, _, [{:assert, _, _} | _]} = code, _value), do: code

  # Output target was :ex_unit, so eval directly
  def code_for_eval(:auto_assert, {:assert, _, _} = code, _value), do: code
  def code_for_eval(:auto_assert_raise, {:assert_raise, _, _} = code, _value), do: code
  def code_for_eval(:auto_assert_receive, {:assert_receive, _, _} = code, _value), do: code

  # ExUnit assert arguments must evaluate to a truthy value, so we eval
  # a comparison instead of pattern match
  def code_for_eval(:auto_assert, {:auto_assert, _, [{_, _, [expr, _]}]}, falsy)
      when falsy in [nil, false] do
    {:assert, [], [{:==, [], [unescape_strings(expr), Macro.var(:value, :mneme)]}]}
  end

  # ExUnit asserts don't support guards, so we split them out
  def code_for_eval(:auto_assert, {_, _, [{_, _, [{:when, _, [expected, guard]}, _]}]}, _value) do
    quote do
      value = unquote(assert_match(expected))
      assert unquote(guard)
      value
    end
  end

  def code_for_eval(:auto_assert, {_, _, [{_, _, [expected, _]}]}, _value) do
    assert_match(expected)
  end

  def code_for_eval(:auto_assert_raise, _ast, nil) do
    quote do
      raise Mneme.AssertionError,
        message: "expected function to raise an exception, but none was raised"
    end
  end

  def code_for_eval(:auto_assert_raise, {_, _, [exception, message, _]}, e) do
    quote do
      assert_raise unquote(exception), unquote(unescape_strings(message)), fn ->
        raise unquote(quote_exception(e))
      end
    end
  end

  def code_for_eval(:auto_assert_raise, {_, _, [exception, _]}, e) do
    quote do
      assert_raise unquote(exception), fn ->
        raise unquote(quote_exception(e))
      end
    end
  end

  def code_for_eval(:auto_assert_receive, _ast, []) do
    quote do
      raise Mneme.AssertionError,
        message: "did not receive any messages within the timeout period"
    end
  end

  def code_for_eval(:auto_assert_receive, {_, _, [pattern | _]}, _) do
    # We always set 0 timeout here since we've already waited in order
    # to generate patterns
    quote do
      assert_receive unquote(unescape_strings(pattern)), 0
    end
  end

  def code_for_eval(:auto_assert_received, _ast, []) do
    quote do
      raise Mneme.AssertionError, message: "no messages available in process inbox"
    end
  end

  def code_for_eval(:auto_assert_received, {_, _, [pattern]}, _) do
    quote do
      assert_received unquote(unescape_strings(pattern))
    end
  end

  defp assert_match(expr) do
    {:assert, [], [{:=, [], [unescape_strings(expr), Macro.var(:value, :mneme)]}]}
  end

  defp value_expr({:__block__, _, [first, _second]}), do: value_expr(first)

  defp value_expr({:auto_assert, _, [{:<-, _, [_, value_expr]}]}), do: value_expr
  defp value_expr({:auto_assert, _, [{:=, _, [_, value_expr]}]}), do: value_expr
  defp value_expr({:auto_assert, _, [value_expr]}), do: value_expr

  defp value_expr({:auto_assert_raise, _, [_, _, fun]}), do: fun
  defp value_expr({:auto_assert_raise, _, [_, fun]}), do: fun
  defp value_expr({:auto_assert_raise, _, [fun]}), do: fun

  defp value_eval_expr({:__block__, _, _} = expr), do: value_expr(expr)
  defp value_eval_expr({:auto_assert, _, _} = expr), do: value_expr(expr)

  defp value_eval_expr({:auto_assert_raise, _, _} = expr) do
    expr |> value_expr() |> raised_exception()
  end

  defp value_eval_expr({:auto_assert_receive, _, [_, timeout]}), do: messages_received(timeout)

  defp value_eval_expr({:auto_assert_receive, _, _}) do
    messages_received(Mneme.__receive_timeout__())
  end

  defp value_eval_expr({:auto_assert_received, _, _}), do: messages_received()

  defp messages_received do
    quote(do: self() |> Process.info(:messages) |> elem(1))
  end

  defp messages_received(timeout) do
    quote do
      ref = :erlang.start_timer(unquote(timeout), self(), :ok)

      receive do
        {_, ^ref, _} -> elem(Process.info(self(), :messages), 1)
      end
    end
  end

  defp raised_exception(fun) do
    quote do
      try do
        unquote(fun).()
        nil
      rescue
        e -> e
      end
    end
  end

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
  end

  defp meta({_, meta, _}), do: meta
  defp meta(_), do: []

  defp quote_exception(%exception{} = err) do
    kvs =
      err
      |> Map.from_struct()
      |> Map.delete(:__exception__)
      |> Enum.map(&Macro.escape/1)

    {:%, [], [exception, {:%{}, [], kvs}]}
  end

  defp maybe_warn(:auto_assert, [{:<-, _, [var, _]}] = args, caller) when is_identifier(var) do
    file = Path.relative_to_cwd(caller.file)
    warn_useless_pattern(args, file, caller.line)
  end

  defp maybe_warn(_, _, _), do: :ok

  defp warn_useless_pattern([{:<-, _, [left, right]}] = args, file, line) do
    current = {:auto_assert, [], args}
    suggested = {:=, [], [left, right]}

    warn("""
    (#{file}:#{line}) assertion will always succeed:

        #{Sourceror.to_string(current)}

    Consider rewriting to:

        #{Sourceror.to_string(suggested)}
    """)
  end

  defp warn_non_interactive do
    warn(
      "Mneme is running in non-interactive mode. Ensure that `Mneme.start()` is called before auto-assertions run."
    )
  end

  defp warn(message) do
    [:yellow, "warning: ", :default_color, message]
    |> IO.ANSI.format()
    |> IO.puts()
  end
end
