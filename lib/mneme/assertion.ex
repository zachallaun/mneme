defmodule Mneme.Assertion do
  @moduledoc false

  alias __MODULE__

  defstruct [
    :type,
    :code,
    :value,
    :context,
    call: :auto_assert
  ]

  @doc """
  Build an assertion.
  """
  def build(call \\ :auto_assert, code, caller) do
    context = context(caller)

    eval_expr =
      quote do
        case assertion.type do
          :new ->
            raise ExUnit.AssertionError, message: "No match present"

          :replace ->
            {result, _} =
              assertion
              |> Mneme.Assertion.convert(target: :ex_unit_eval)
              |> Code.eval_quoted(binding, __ENV__)

            result
        end
      end

    quote do
      var!(value, :mneme) = unquote(value_expr(code))

      assertion =
        Mneme.Assertion.new(
          unquote(call),
          unquote(Macro.escape(code)),
          var!(value, :mneme),
          unquote(Macro.escape(context)) |> Map.put(:binding, binding())
        )

      binding = binding() ++ binding(:mneme)

      try do
        unquote(eval_expr)
      rescue
        error in [ExUnit.AssertionError] ->
          case Mneme.Server.await_assertion(assertion) do
            {:ok, assertion} ->
              unquote(eval_expr)

            :error ->
              case __STACKTRACE__ do
                [head | _] -> reraise error, [head]
                [] -> reraise error, []
              end
          end
      end
    end
  end

  defp context(caller) do
    {test, _arity} = caller.function

    %{
      file: caller.file,
      line: caller.line,
      module: caller.module,
      test: test,
      #
      # TODO: access aliases some other way.
      #
      # Env :aliases is considered private and should not be relied on,
      # but I'm not sure where else to access the alias information
      # needed. Macro.Env.fetch_alias/2 is a thing, but it goes from
      # alias to resolved module, and I need resolved module to alias.
      # E.g. Macro.Env.fetch_alias(env, Bar) might return {:ok, Foo.Bar},
      # but I have Foo.Bar and need to know that Bar is the alias in
      # the current environment.
      aliases: caller.aliases
    }
  end

  @doc false
  def new(call \\ :auto_assert, code, value, context)

  def new(call, {op, _, [_, _]} = code, value, context) when op in [:<-, :==] do
    %Assertion{
      type: :replace,
      call: call,
      code: code,
      value: value,
      context: context
    }
  end

  def new(call, code, value, context) do
    %Assertion{
      type: :new,
      call: call,
      code: code,
      value: value,
      context: context
    }
  end

  @doc """
  Regenerate assertion `:code` based on its `:value`.
  """
  def regenerate_code(%Assertion{} = assertion, opts) do
    {_, _, [new_code]} = convert(assertion, opts)

    assertion
    |> Map.put(:code, new_code)
    |> Map.put(:type, :replace)
  end

  @doc """
  Format the assertion as a string.
  """
  def format(%Assertion{call: call, code: code}, opts) do
    Sourceror.to_string({call, [], [code]}, opts)
  end

  @doc """
  Check whether the assertion struct represents the given AST node.
  """
  def same?(%Assertion{context: context}, node) do
    case node do
      {:auto_assert, meta, [_]} -> meta[:line] == context[:line]
      _ -> false
    end
  end

  @doc """
  Converts the assertion to the given target, either `:mneme` or `:ex_unit`.
  """
  def convert(assertion, opts \\ []) do
    target = Keyword.fetch!(opts, :target)

    case Mneme.Serializer.to_pattern(assertion.value, assertion.context) do
      {falsy, nil} when falsy in [nil, false] ->
        build_call(target, :compare, assertion, falsy, nil)

      {expr, guard} ->
        build_call(target, :match, assertion, expr, guard)
    end
  end

  defp build_call(:mneme, :compare, assertion, falsy_expr, nil) do
    {assertion.call, [], [{:==, [], [value_expr(assertion.code), falsy_expr]}]}
  end

  defp build_call(:mneme, :match, assertion, expr, nil) do
    {assertion.call, [], [{:<-, [], [expr, value_expr(assertion.code)]}]}
  end

  defp build_call(:mneme, :match, assertion, expr, guard) do
    {assertion.call, [], [{:<-, [], [{:when, [], [expr, guard]}, value_expr(assertion.code)]}]}
  end

  defp build_call(:ex_unit, :compare, assertion, falsy, nil) do
    {:assert, [], [{:==, [], [value_expr(assertion.code), falsy]}]}
  end

  defp build_call(:ex_unit, :match, assertion, expr, nil) do
    {:assert, [], [{:=, [], [normalize_heredoc(expr), value_expr(assertion.code)]}]}
  end

  defp build_call(:ex_unit, :match, assertion, expr, guard) do
    assertion = build_call(:ex_unit, :match, assertion, expr, nil)

    quote do
      value = unquote(assertion)
      assert unquote(guard)
      value
    end
  end

  defp build_call(:ex_unit_eval, :compare, assertion, _falsy, nil) do
    {:assert, [], [{:==, [], [expect_expr(assertion.code), {:value, [], nil}]}]}
  end

  defp build_call(:ex_unit_eval, :match, assertion, _expr, nil) do
    {:assert, [], [{:=, [], [expect_expr(assertion.code), {:value, [], nil}]}]}
  end

  defp build_call(:ex_unit_eval, :match, assertion, expr, guard) do
    assertion = build_call(:ex_unit_eval, :match, assertion, expr, nil)

    quote do
      value = unquote(assertion)
      assert unquote(guard)
      value
    end
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

  defp expect_expr({:<-, _, [expect_expr, _]}), do: expect_expr
  defp expect_expr({:==, _, [_, expect_expr]}), do: expect_expr

  defp value_expr({:<-, _, [_, value_expr]}), do: value_expr
  defp value_expr({:==, _, [value_expr, _]}), do: value_expr
  defp value_expr(value_expr), do: value_expr
end
