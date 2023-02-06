defmodule Mneme.Assertion do
  @moduledoc false

  alias __MODULE__

  defstruct [
    :type,
    :code,
    :value,
    :context
  ]

  @doc """
  Build an assertion.
  """
  def build(code, caller) do
    context = context(caller)

    eval_expr =
      quote do
        case assertion.type do
          :new ->
            raise ExUnit.AssertionError, message: "No match present"

          :update ->
            {result, _} =
              assertion
              |> Mneme.Assertion.to_code(:eval)
              |> Code.eval_quoted(binding, __ENV__)

            result
        end
      end

    quote do
      var!(value, :mneme) = unquote(value_expr(code))

      assertion =
        Mneme.Assertion.new(
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
  def new(code, value, context) do
    type =
      case code do
        {_, _, [{op, _, [_, _]}]} when op in [:<-, :==] -> :update
        _ -> :new
      end

    %Assertion{
      type: type,
      code: code,
      value: value,
      context: context
    }
  end

  @doc """
  Regenerate assertion `:code` based on its `:value`.
  """
  def regenerate_code(%Assertion{} = assertion, target) when target in [:auto_assert, :assert] do
    new_code = to_code(assertion, target)

    assertion
    |> Map.put(:code, new_code)
    |> Map.put(:type, :update)
  end

  @doc """
  Format the assertion as a string.
  """
  def format(%Assertion{code: code}, opts) do
    code
    |> escape_newlines()
    |> Sourceror.to_string(opts)
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
  Generates assertion code for the given target.

  Target is one of:

    * `:auto_assert` - Generate an `auto_assert` call that is appropriate
      for updating the source code.

    * `:assert` - Generate an `assert` call that is appropriate for
      updating the source code.

    * `:eval` - Generate an assertion that can be dynamically evaluated.
  """
  def to_code(assertion, target) when target in [:auto_assert, :assert, :eval] do
    case Mneme.Serializer.to_pattern(assertion.value, assertion.context) do
      {falsy, nil} when falsy in [nil, false] ->
        build_call(target, :compare, assertion, falsy, nil)

      {expr, guard} ->
        build_call(target, :match, assertion, expr, guard)
    end
  end

  defp build_call(:auto_assert, :compare, assertion, falsy_expr, nil) do
    {:auto_assert, [], [{:==, [], [value_expr(assertion.code), falsy_expr]}]}
  end

  defp build_call(:auto_assert, :match, assertion, expr, nil) do
    {:auto_assert, [], [{:<-, [], [expr, value_expr(assertion.code)]}]}
  end

  defp build_call(:auto_assert, :match, assertion, expr, guard) do
    {:auto_assert, [], [{:<-, [], [{:when, [], [expr, guard]}, value_expr(assertion.code)]}]}
  end

  defp build_call(:assert, :compare, assertion, falsy, nil) do
    {:assert, [], [{:==, [], [value_expr(assertion.code), falsy]}]}
  end

  defp build_call(:assert, :match, assertion, expr, nil) do
    {:assert, [], [{:=, [], [normalize_heredoc(expr), value_expr(assertion.code)]}]}
  end

  defp build_call(:assert, :match, assertion, expr, guard) do
    check = build_call(:assert, :match, assertion, expr, nil)

    quote do
      unquote(check)
      assert unquote(guard)
    end
  end

  defp build_call(:eval, _, %{code: {:__block__, _, _} = code}, _, _) do
    code
  end

  defp build_call(:eval, :compare, assertion, _falsy, nil) do
    {:assert, [], [{:==, [], [normalized_expect_expr(assertion.code), {:value, [], nil}]}]}
  end

  defp build_call(:eval, :match, assertion, _expr, nil) do
    {:assert, [], [{:=, [], [normalized_expect_expr(assertion.code), {:value, [], nil}]}]}
  end

  defp build_call(:eval, :match, assertion, expr, guard) do
    check = build_call(:eval, :match, assertion, expr, nil)

    quote do
      value = unquote(check)
      assert unquote(guard)
      value
    end
  end

  defp value_expr({_, _, [{:<-, _, [_, value_expr]}]}), do: value_expr
  defp value_expr({_, _, [{:==, _, [value_expr, _]}]}), do: value_expr
  defp value_expr({_, _, [value_expr]}), do: value_expr

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

  defp escape_newlines(code) when is_list(code) do
    Enum.map(code, &escape_newlines/1)
  end

  defp escape_newlines(code) do
    Sourceror.prewalk(code, fn
      {:__block__, meta, [string]} = quoted, state when is_binary(string) ->
        case meta[:delimiter] do
          "\"" -> {{:__block__, meta, [String.replace(string, "\n", "\\n")]}, state}
          _ -> {quoted, state}
        end

      quoted, state ->
        {quoted, state}
    end)
  end
end
