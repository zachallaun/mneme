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
      test_data = source.private[:mneme_integration]

      quote do
        defmodule unquote(module) do
          use ExUnit.Case, async: true

          @tag :tmp_dir
          @tag :integration
          @tag unquote(test_data[:name])
          test unquote(module_name), %{tmp_dir: tmp_dir} do
            unquote(test_data)
            |> Map.new()
            |> Map.put(:tmp_dir, tmp_dir)
            |> Mneme.Integration.run_test()
          end
        end
      end
    end
  end

  @doc """
  A string that can be prepended or appended to an Elixir integration
  test file to update the file contents during testing.
  """
  def safe_source_modification, do: "\n#mneme_integration_modification\n"

  @doc false
  def run_test(test) do
    debug_setup(System.get_env("DBG"), test)

    file_path = Path.join([test.tmp_dir, "integration_test.exs"])
    File.write!(file_path, test.test_code)

    test_command = """
    echo "#{test.test_input}" | \
      CI=false mix test #{file_path} --seed 0 \
    """

    test_command =
      if Application.get_env(:mneme, :export_integration_coverage) do
        test_command <> "--cover --export-coverage #{test.name}"
      else
        test_command
      end

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
      |> String.trim_leading(safe_source_modification())
      |> String.trim_trailing(safe_source_modification())

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
    ast =
      source
      |> Source.ast()
      |> prune_to_version()

    {test_ast, test_input} = build_test_ast_and_input(ast)
    test_code = source |> Source.update(:mneme, ast: test_ast) |> Source.code()

    expected_ast = build_expected_ast(ast)
    expected_code = source |> Source.update(:mneme, ast: expected_ast) |> Source.code()

    %{exit_code: exit_code} = module_metadata(ast)

    source =
      Source.put_private(source, :mneme_integration,
        name: source |> Source.path() |> Path.rootname() |> Path.basename() |> String.to_atom(),
        path: Source.path(source),
        test_input: test_input,
        test_code: eof_newline(test_code),
        expected_code: eof_newline(expected_code),
        expected_exit_code: exit_code
      )

    Project.update(project, source)
  end

  defp prune_to_version(ast) do
    alias Sourceror.Zipper, as: Z

    current = %{
      version: System.version(),
      otp: semantic_otp_version()
    }

    ast
    |> Z.zip()
    |> Z.traverse(fn zipper ->
      if meets_version_requirements?(Z.node(zipper), current) do
        zipper
      else
        Z.replace(zipper, :ok)
      end
    end)
    |> Z.node()
  end

  defp meets_version_requirements?(node, current) do
    case required_versions(node) do
      %{version: version, otp: otp} ->
        Version.match?(current.version, version) && Version.match?(current.otp, otp)

      %{version: version} ->
        Version.match?(current.version, version)

      %{otp: otp} ->
        Version.match?(current.otp, otp)

      _ ->
        true
    end
  end

  defp required_versions({_, meta, _}) do
    Enum.flat_map(meta[:leading_comments] || [], fn
      %{text: "# version: " <> version_spec} -> [{:version, version_spec}]
      %{text: "# otp: " <> otp_spec} -> [{:otp, otp_spec}]
      _ -> []
    end)
    |> Map.new()
  end

  defp required_versions(_), do: %{}

  defp build_test_ast_and_input(ast) do
    {test_ast, nested_comments} = Sourceror.prewalk(ast, [], &transform_test_assertion/2)
    {test_ast, nested_comments |> List.flatten() |> input_string_from_comments()}
  end

  defp transform_test_assertion({_, meta, _} = quoted, state) do
    state = Map.update!(state, :acc, &[meta[:leading_comments] || [] | &1])

    if ignore_transform?(meta) do
      {quoted, state}
    else
      {transform(quoted), state}
    end
  end

  defp transform_test_assertion(quoted, state), do: {quoted, state}

  defp ignore_transform?(meta) do
    Enum.any?(meta[:leading_comments] || [], fn
      %{text: "# ignore"} -> true
      _ -> false
    end)
  end

  defp transform({:auto_assert, _, _} = quoted) do
    transform_auto_assert(quoted)
  end

  # last argument is the function expected to raise
  defp transform({:auto_assert_raise, meta, args}) do
    {:auto_assert_raise, meta, [List.last(args)]}
  end

  defp transform({assert_receive, meta, _})
       when assert_receive in [:auto_assert_receive, :auto_assert_received] do
    {assert_receive, meta, []}
  end

  defp transform({:assert, meta, args} = quoted) do
    if Enum.any?(meta[:leading_comments] || [], &(&1.text == "# auto_assert")) do
      transform_auto_assert({:auto_assert, meta, args})
    else
      quoted
    end
  end

  defp transform(quoted), do: quoted

  defp transform_auto_assert({call, meta, [current, _expected]}) do
    {call, meta, [current]}
  end

  defp transform_auto_assert({call, meta, [{:<-, _, [_expected_pattern, expr]}]}) do
    {call, meta, [expr]}
  end

  defp transform_auto_assert({call, meta, [{:=, _, [_expected_pattern, expr]}]}) do
    {call, meta, [expr]}
  end

  defp transform_auto_assert({_call, _meta, [_expr]} = quoted), do: quoted

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

  # Extracts only single character input. For example, a comment of
  # "# j y" will end up as "j\ny\n". A comment of "# something y" will
  # end up as "y\n".
  defp input_string_from_comments(comments) do
    comments
    |> Enum.sort_by(& &1.line)
    |> Stream.flat_map(fn
      %{text: "# " <> input} -> String.split(input)
      _ -> []
    end)
    |> Stream.filter(fn
      <<_::utf8>> -> true
      _ -> false
    end)
    |> Stream.map(&[&1, "\n"])
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  defp module_metadata({:defmodule, meta, _}) do
    meta[:leading_comments]
    |> Enum.flat_map(fn
      %{text: "# exit: " <> exit_code} ->
        {exit_code, ""} = Integer.parse(exit_code)
        [{:exit_code, exit_code}]

      _ ->
        []
    end)
    |> Map.new()
    |> Map.put_new(:exit_code, 0)
  end

  defp module_metadata(_), do: %{exit_code: 0}

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

  defp semantic_otp_version do
    otp_version()
    |> String.trim()
    |> String.split(".")
    |> case do
      [major] -> "#{major}.0.0"
      [major, minor] -> "#{major}.#{minor}.0"
      [major, minor, patch | _] -> "#{major}.#{minor}.#{patch}"
    end
  end

  defp otp_version do
    major = System.otp_release()
    version_file = Path.join([:code.root_dir(), "releases", major, "OTP_VERSION"])

    try do
      {:ok, contents} = File.read(version_file)
      String.split(contents, "\n", trim: true)
    else
      [full] -> full
      _ -> major
    catch
      :error, _ -> major
    end
  end
end
