defmodule Mneme.Integration do
  @moduledoc """
  Builds modules for integration testing.

  To debug a specific integration test set the `DBG` environment var to
  a substring matching the test's file name. This will print additional
  information about the generated test module and result.

  ```bash
  $ DBG=some_test mix test
  ```
  """

  alias Rewrite.Project
  alias Rewrite.Source

  defmodule TestError do
    defexception [:message]
  end

  @doc """
  Build integration test modules for each file matching the wildcard.
  """
  defmacro build_tests!(wildcard) when is_binary(wildcard) do
    project = Project.read!(wildcard)
    project = Enum.reduce(Project.sources(project), project, &set_up_source/2)

    for source <- Project.sources(project) do
      module = source |> Source.modules() |> List.last()
      "Elixir." <> module_name = to_string(module)

      quote do
        defmodule unquote(module) do
          use ExUnit.Case, async: true

          @tag :tmp_dir
          @tag :integration
          test unquote(module_name), %{tmp_dir: tmp_dir} do
            data = %{
              path: unquote(Source.path(source)),
              tmp_dir: tmp_dir,
              test_input: unquote(test_input(source)),
              test_code: unquote(test_code(source)),
              expected_code: unquote(expected_code(source)),
              expected_exit_code: unquote(expected_exit_code(source))
            }

            Mneme.Integration.run_test(data)
          end
        end
      end
    end
  end

  @doc false
  def run_test(test) do
    debug_setup(System.get_env("DBG"), test)

    file_path = Path.join([test.tmp_dir, "integration_test.exs"])
    File.write!(file_path, test.test_code)

    test_command = """
    echo "#{test.test_input}" | \
      CI=false \
      mix test #{file_path} --seed 0 \
    """

    task = Task.async(System, :shell, [test_command])

    {output, exit_code} =
      case Task.yield(task, 15_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} ->
          result

        nil ->
          raise Mneme.Integration.TestError,
            message: "integration test failed to complete within 15 seconds: #{test.path}"
      end

    code_after_test =
      file_path
      |> File.read!()
      # This allows us to modify the test file in-place without the
      # `code_after_test == test.expected_code` check failing
      |> String.trim_trailing("#")

    errors =
      [
        {exit_code == test.expected_exit_code,
         "Exit code was #{exit_code} (expected #{test.expected_exit_code})"},
        {code_after_test == test.expected_code,
         diff("Source", test.expected_code, code_after_test)}
      ]
      |> Enum.reject(fn {check, _} -> check end)
      |> Enum.map(fn {_, message} -> message end)

    debug_output(System.get_env("DBG"), test, code_after_test, output)

    unless errors == [] do
      message = "\n" <> Enum.join(errors, "\n")
      raise Mneme.Integration.TestError, message: message
    end
  end

  defp debug_setup(nil, _), do: :ok

  defp debug_setup("", test) do
    Owl.IO.puts([Owl.Data.tag("Running: ", :cyan), test.path, "\n"])
  end

  defp debug_setup(debug, test) do
    if String.contains?(test.path, debug) do
      Owl.IO.puts([
        [Owl.Data.tag("Path: ", :cyan), test.path, "\n"],
        [Owl.Data.tag("Exit code: ", :cyan), to_string(test.expected_exit_code), "\n"],
        [Owl.Data.tag("Input:\n", :cyan), test.test_input, "\n"],
        [Owl.Data.tag("Test:\n\n", :cyan), test.test_code, "\n\n"],
        [Owl.Data.tag("Expected:\n\n", :cyan), test.expected_code, "\n"]
      ])
    end
  end

  defp debug_output(nil, _, _, _), do: :ok

  defp debug_output("", test, _, _) do
    Owl.IO.puts([Owl.Data.tag("Complete: ", :green), test.path, "\n"])
  end

  defp debug_output(debug, test, code_after, output) do
    if String.contains?(test.path, debug) do
      [
        [Owl.Data.tag("Actual:\n\n", :cyan), code_after, "\n"],
        [Owl.Data.tag("\n\nOutput:\n", :cyan), output, "\n"]
      ]
      |> Owl.IO.puts()
    end
  end

  defp set_up_source(source, project) do
    ast = Source.ast(source)

    {test_ast, test_input} = build_test_ast_and_input(ast)
    test_code = source |> Source.update(:mneme, ast: test_ast) |> Source.code()

    expected_ast = build_expected_ast(ast)
    expected_code = source |> Source.update(:mneme, ast: expected_ast) |> Source.code()

    expected_exit_code = get_exit_code(ast)

    source =
      Source.put_private(source, :mneme,
        test_input: test_input,
        test_code: test_code,
        expected_code: expected_code,
        expected_exit_code: expected_exit_code
      )

    Project.update(project, source)
  end

  defp test_code(source), do: source.private[:mneme][:test_code] |> eof_newline()
  defp test_input(source), do: source.private[:mneme][:test_input]
  defp expected_code(source), do: source.private[:mneme][:expected_code] |> eof_newline()
  defp expected_exit_code(source), do: source.private[:mneme][:expected_exit_code]

  defp build_test_ast_and_input(ast) do
    {test_ast, comments} =
      Sourceror.prewalk(ast, [], fn
        {:auto_assert, meta, _} = quoted, %{acc: comments} = state ->
          {test_auto_assert(quoted), %{state | acc: meta[:leading_comments] ++ comments}}

        {:auto_assert_raise, meta, _} = quoted, %{acc: comments} = state ->
          {test_auto_assert_raise(quoted), %{state | acc: meta[:leading_comments] ++ comments}}

        {:auto_assert_receive, meta, _} = quoted, %{acc: comments} = state ->
          {test_auto_assert_receive(quoted), %{state | acc: meta[:leading_comments] ++ comments}}

        {:assert, meta, args} = quoted, %{acc: comments} = state ->
          case meta[:leading_comments] do
            [%{text: "# auto_assert"}] ->
              {test_auto_assert({:auto_assert, meta, args}),
               %{state | acc: meta[:leading_comments] ++ comments}}

            _ ->
              {quoted, state}
          end

        quoted, state ->
          {quoted, state}
      end)

    {test_ast, input_string_from_comments(comments)}
  end

  defp test_auto_assert({call, meta, [current, _expected]}) do
    {call, meta, [current]}
  end

  defp test_auto_assert({call, meta, [{:<-, _, [_expected_pattern, expr]}]}) do
    {call, meta, [expr]}
  end

  defp test_auto_assert({call, meta, [{:=, _, [_expected_pattern, expr]}]}) do
    {call, meta, [expr]}
  end

  defp test_auto_assert({_call, _meta, [_expr]} = quoted), do: quoted

  defp test_auto_assert_raise({call, meta, args}), do: {call, meta, [List.last(args)]}

  defp test_auto_assert_receive({call, meta, _}), do: {call, meta, []}

  defp build_expected_ast(ast) do
    Sourceror.prewalk(ast, fn
      {:auto_assert, _, _} = quoted, state -> {expected_auto_assert(quoted), state}
      {:assert, _, _} = quoted, state -> {expected_auto_assert(quoted), state}
      quoted, state -> {quoted, state}
    end)
  end

  defp expected_auto_assert({call, meta, [_current, expected]}) do
    {call, meta, [expected]}
  end

  defp expected_auto_assert({_call, _meta, [_expr]} = quoted), do: quoted

  @input_re ~r/#\s?(.+)/
  defp input_string_from_comments(comments) do
    comments
    |> Enum.sort_by(& &1.line)
    |> Enum.flat_map(fn %{text: text} ->
      case(Regex.run(@input_re, text)) do
        [_, input] -> input |> String.split() |> Enum.map(&[&1, "\n"])
        _ -> []
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp get_exit_code({:defmodule, meta, _args}) do
    with [%{text: comment} | _] <- meta[:leading_comments],
         [_, exit_code_str] <- Regex.run(~r/.*exit:(\d).*/, comment),
         {exit_code, ""} <- Integer.parse(exit_code_str) do
      exit_code
    else
      _ -> 0
    end
  end

  defp diff(header, expected, actual) do
    [
      """
      #{header} does not match:

      """,
      Rewrite.TextDiff.format(expected, actual, format: [separator: "| "])
    ]
    |> IO.iodata_to_binary()
  end

  defp eof_newline(string), do: String.trim_trailing(string) <> "\n"
end
