defmodule Mneme.Patch do
  @moduledoc false

  alias Mneme.Format
  alias Sourceror.Zipper

  defmodule SuiteResult do
    @moduledoc false
    defstruct asts: %{}, patches: %{}, format_opts: %{}
  end

  def apply_changes!(%SuiteResult{patches: patches} = state) do
    Enum.each(patches, &patch_file!/1)
    %{state | patches: %{}}
  end

  def handle_assertion(state, {type, _expr, actual, loc}) do
    file = loc[:file]
    line = loc[:line]

    {ast, format_opts, state} = cache_file_data(state, file)

    {_, patch} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse(nil, fn
        {{:auto_assert, meta, [_]} = assert, _} = zipper, nil ->
          if meta[:line] == line do
            {zipper, assertion_patch(type, loc, actual, assert, format_opts)}
          else
            {zipper, nil}
          end

        zipper, patch ->
          {zipper, patch}
      end)

    if patch do
      {{:ok, patch.expectation}, update_in(state.patches[file], &[patch | &1])}
    else
      {:error, state}
    end
  end

  defp cache_file_data(%{asts: asts} = state, file) do
    case {asts, file} do
      {%{^file => ast}, file} ->
        {ast, state.format_opts[file], state}

      {_asts, file} ->
        ast = file |> File.read!() |> Sourceror.parse_string!()
        {_, format_opts} = Mix.Tasks.Format.formatter_for_file(file)

        state =
          state
          |> Map.update!(:asts, &Map.put(&1, file, ast))
          |> Map.update!(:format_opts, &Map.put(&1, file, format_opts))
          |> Map.update!(:patches, &Map.put(&1, file, []))

        {ast, format_opts, state}
    end
  end

  defp assertion_patch(
         type,
         loc,
         actual,
         {:auto_assert, _, [inner]} = assert,
         format_opts
       ) do
    original = {:auto_assert, [], [inner]} |> Sourceror.to_string(format_opts)

    expectation = quoted_expectation(actual)

    replacement =
      {:auto_assert, [], [update_match(type, inner, expectation)]}
      |> Sourceror.to_string(format_opts)

    if accept_change?(type, loc, original, replacement) do
      %{expectation: expectation, change: replacement, range: Sourceror.get_range(assert)}
    end
  end

  defp update_match(:new, value, expected) do
    {:=, [], [expected, value]}
  end

  defp update_match(:replace, {:=, meta, [_old, value]}, expected) do
    {:=, meta, [expected, value]}
  end

  defp quoted_expectation(value) when is_integer(value), do: value
  defp quoted_expectation(value) when is_binary(value), do: value

  defp patch_file!({_file, []}), do: :ok

  defp patch_file!({file, patches}) do
    source = File.read!(file)
    patched = Sourceror.patch_string(source, patches)
    File.write!(file, patched)
  end

  defp accept_change?(type, meta, original, replacement) do
    operation =
      case type do
        :new -> "New"
        :replace -> "Update"
      end

    message = """
    \n[Mneme] #{operation} assertion - #{meta[:file]}:#{meta[:line]}

    #{Format.prefix_lines(original, "- ")}
    #{Format.prefix_lines(replacement, "+ ")}
    """

    IO.puts(message)
    prompt_action("Accept change? (y/n) ")
  end

  defp prompt_action(prompt) do
    IO.gets(prompt)
    |> String.trim()
    |> String.downcase()
    |> case do
      "y" ->
        true

      "n" ->
        false

      other ->
        IO.puts("unknown response: #{other}")
        prompt_action(prompt)
    end
  end
end
