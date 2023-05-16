defmodule Mneme.Assertion do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Assertion.Pattern
  alias Mneme.Assertion.PatternBuilder

  defstruct [
    :kind,
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
          kind: kind,
          stage: :new | :update,
          value: term(),
          macro_ast: Macro.t(),
          rich_ast: Macro.t(),
          code: Macro.t(),
          patterns: [Pattern.t()],
          pattern_idx: non_neg_integer(),
          context: context
        }

  @type kind ::
          :auto_assert
          | :auto_assert_raise
          | :auto_assert_receive
          | :auto_assert_received

  @type context :: %{
          file: String.t(),
          line: non_neg_integer(),
          module: module(),
          test: atom(),
          aliases: list(),
          binding: list(),
          original_pattern: Macro.t() | nil
        }

  @type target :: :mneme | :ex_unit

  @doc false
  def new({kind, _, args} = macro_ast, value, ctx) do
    {stage, original_pattern} = get_stage(kind, args)
    context = Enum.into(ctx, %{original_pattern: original_pattern})

    %Assertion{
      kind: kind,
      stage: stage,
      macro_ast: macro_ast,
      value: value,
      context: context
    }
  end

  @doc """
  Builds a quoted expression that will run the assertion.
  """
  @spec build(atom(), [term()], Macro.Env.t()) :: Macro.t()
  def build(kind, args, caller) do
    macro_ast = {kind, Macro.Env.location(caller), args}

    quote do
      Mneme.Assertion.new(
        unquote(Macro.escape(macro_ast)),
        unquote(value_eval_expr(macro_ast)),
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
  def run(assertion, env, interactive? \\ true) do
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

    assertion.value
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
    case assertion do
      %{kind: :auto_assert_raise, value: nil} -> {:ok, assertion}
      %{kind: :auto_assert_receive, value: []} -> {:ok, assertion}
      %{kind: :auto_assert_received, value: []} -> {:ok, assertion}
      _ -> Mneme.Server.patch_assertion(assertion)
    end
    |> handle_assertion(assertion, env, existing_error)
  end

  defp handle_assertion(result, assertion, env, existing_error \\ nil)
  defp handle_assertion({:ok, assertion}, _, env, _), do: eval(assertion, env)
  defp handle_assertion({:error, :skipped}, _, _, _), do: :ok
  defp handle_assertion({:error, :rejected}, _, _, nil), do: assertion_error!()

  defp handle_assertion({:error, :rejected}, assertion, _, error) do
    reraise error, [stacktrace_entry(assertion)]
  end

  defp handle_assertion({:error, {:internal, error, stacktrace}}, _, _, _) do
    raise Mneme.InternalError, original_error: error, original_stacktrace: stacktrace
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

  defp warn_non_interactive do
    [
      [:yellow, "warning: ", :default_color],
      "Mneme is running in non-interactive mode. Ensure that `Mneme.start()` is called before auto-assertions run."
    ]
    |> IO.ANSI.format()
    |> IO.puts()
  end

  defp get_stage(:auto_assert, [{:<-, _, [{:when, _, [pattern, _]}, _]}]), do: {:update, pattern}
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
    {patterns, pattern_idx} = build_and_select(assertion, default_pattern)

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

  defp build_and_select(%{kind: kind} = assertion, default_pattern) do
    case kind do
      :auto_assert -> build_and_select_pattern(assertion, default_pattern)
      :auto_assert_raise -> build_and_select_raise(assertion, default_pattern)
      :auto_assert_receive -> build_and_select_receive(assertion, default_pattern)
      :auto_assert_received -> build_and_select_receive(assertion, default_pattern)
    end
  end

  defp build_and_select_receive(%{value: [_ | _] = messages, context: ctx}, default_pattern) do
    patterns =
      messages
      |> Enum.map(&PatternBuilder.to_patterns(&1, ctx))
      |> Enum.map(fn patterns ->
        case default_pattern do
          :first -> List.first(patterns)
          _ -> List.last(patterns)
        end
      end)

    {patterns, 0}
  end

  defp build_and_select_raise(%{value: error, macro_ast: macro_ast, context: ctx}, default) do
    %exception{} = error

    patterns =
      error
      |> Exception.message()
      |> PatternBuilder.to_patterns(ctx)
      |> Enum.map(fn %Pattern{expr: message} ->
        Pattern.new({exception, message})
      end)
      |> then(&[Pattern.new({exception, nil}) | &1])

    case {default, macro_ast} do
      {:infer, {_, _, [_, _, _]}} -> {patterns, 1}
      {:last, _} -> {patterns, 1}
      _ -> {patterns, 0}
    end
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
  defp similarity_score({name, _, args1}, {name, _, args2}) do
    1 + similarity_score(args1, args2)
  end

  defp similarity_score(l1, l2) when is_list(l1) and is_list(l2) do
    # add the lesser length so that non-empty lists will be considered
    # more similar than empty ones, but lists sharing content will be
    # considered even more similar
    min(length(l1), length(l2)) +
      (Enum.zip(l1, l2)
       |> Enum.map(fn {el1, el2} -> similarity_score(el1, el2) end)
       |> Enum.sum())
  end

  defp similarity_score({_, _, args1}, {_, _, args2}), do: similarity_score(args1, args2)
  defp similarity_score({key, val1}, {key, val2}), do: 1 + similarity_score(val1, val2)
  defp similarity_score({_, val1}, {_, val2}), do: similarity_score(val1, val2)
  defp similarity_score(expr, expr), do: 1
  defp similarity_score(_, _), do: 0

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
  Check whether the assertion struct represents the given AST node.
  """
  def same?(%Assertion{kind: kind, context: %{line: line}}, node) do
    case node do
      {^kind, meta, _} -> meta[:line] == line
      _ -> false
    end
  end

  @doc """
  Generates assertion code for the given target.
  """
  def to_code(%Assertion{kind: :auto_assert_raise} = assertion, target) do
    %Pattern{expr: expr} = pattern(assertion)
    build_call(target, assertion, expr)
  end

  def to_code(%Assertion{rich_ast: ast} = assertion, target) do
    %Pattern{expr: expr, guard: guard} = pattern(assertion)
    build_call(target, assertion, {block_with_line(expr, meta(ast)), guard})
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
  def code_for_eval(%Assertion{kind: kind, code: nil, macro_ast: ast, value: value}) do
    code_for_eval(kind, ast, value)
  end

  def code_for_eval(%Assertion{kind: kind, code: code, value: value}) do
    code_for_eval(kind, code, value)
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
end
