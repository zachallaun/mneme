defmodule Mneme.Patch do
  @moduledoc false

  alias Mneme.Format
  alias Mneme.Serialize
  alias Rewrite.DotFormatter
  alias Sourceror.Zipper

  defmodule FileResult do
    @moduledoc false
    defstruct [:file, :source, :ast, accepted: [], rejected: []]
  end

  defmodule SuiteResult do
    @moduledoc false
    defstruct [:format_opts, files: %{}, finalized: false]
  end

  @doc """
  Initialize patch state.
  """
  def init do
    %SuiteResult{format_opts: DotFormatter.opts()}
  end

  @doc """
  Finalize all patches, writing all results to disk.
  """
  def finalize!(%SuiteResult{finalized: false, files: files} = state) do
    for {_, %FileResult{file: file, source: source, accepted: patches}} <- files do
      patched = Sourceror.patch_string(source, patches)
      File.write!(file, patched)
    end

    %{state | finalized: true}
  end

  def finalize!(%SuiteResult{finalized: true} = state), do: state

  @doc """
  Accepts a patch.
  """
  def accept(%SuiteResult{} = state, patch) do
    update_in(state.files[patch.context[:file]].accepted, &[patch | &1])
  end

  @doc """
  Rejects a patch.
  """
  def reject(%SuiteResult{} = state, patch) do
    update_in(state.files[patch.context[:file]].rejected, &[patch | &1])
  end

  @doc """
  Prompts the user to accept the patch.
  """
  def accept_patch?(%SuiteResult{} = state, patch) do
    %{
      type: type,
      context: context,
      original: original,
      replacement: replacement
    } = patch

    operation =
      case type do
        :new -> "New"
        :replace -> "Update"
      end

    message = """
    \n[Mneme] #{operation} assertion - #{context[:file]}:#{context[:line]}

    #{Format.prefix_lines(original, "- ")}
    #{Format.prefix_lines(replacement, "+ ")}
    """

    IO.puts(message)
    accept? = prompt_accept?("Accept change? (y/n) ")

    {accept?, state}
  end

  @doc """
  """
  def load_file!(%SuiteResult{files: files} = state, context) do
    with {:ok, file} <- Keyword.fetch(context, :file),
         nil <- state.files[file] do
      source = File.read!(file)

      file_result = %FileResult{
        file: file,
        source: source,
        ast: Sourceror.parse_string!(source)
      }

      %{state | files: Map.put(files, file, file_result)}
    else
      _ -> state
    end
  end

  @doc """
  Construct the patch and updated state for the given assertion.

  Returns `{patch, state}`.
  """
  def patch_assertion(%SuiteResult{files: files} = state, {type, actual, context}) do
    file = context[:file]
    line = context[:line]
    ast = Map.fetch!(files, file).ast

    {_, patch} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse(nil, fn
        {{:auto_assert, assert_meta, [_]} = assert, _} = zipper, nil ->
          if assert_meta[:line] == line do
            {zipper, create_patch(state, type, actual, context, assert)}
          else
            {zipper, nil}
          end

        zipper, patch ->
          {zipper, patch}
      end)

    {patch, state}
  end

  defp create_patch(
         %SuiteResult{format_opts: format_opts},
         type,
         actual,
         context,
         {:auto_assert, _, [inner]} = assert
       ) do
    original = {:auto_assert, [], [inner]} |> Sourceror.to_string(format_opts)
    expr = update_match(type, inner, Serialize.to_match_expressions(actual, context))

    replacement =
      {:auto_assert, [], [expr]}
      |> Sourceror.to_string(format_opts)

    %{
      change: replacement,
      range: Sourceror.get_range(assert),
      type: type,
      expr: expr,
      context: context,
      original: original,
      replacement: replacement
    }
  end

  defp update_match(:new, value, expected) do
    match_expr(expected, value, [])
  end

  defp update_match(:replace, {:<-, meta, [_old, value]}, expected) do
    match_expr(expected, value, meta)
  end

  defp match_expr({match_expr, nil}, value, meta) do
    {:<-, meta, [match_expr, value]}
  end

  defp match_expr({match_expr, conditions}, value, meta) do
    {:<-, meta, [{:when, [], [match_expr, conditions]}, value]}
  end

  defp prompt_accept?(prompt) do
    case IO.gets(prompt) do
      response when is_binary(response) ->
        response
        |> String.trim()
        |> String.downcase()
        |> case do
          "y" ->
            true

          "n" ->
            false

          other ->
            IO.puts("unknown response: #{other}")
            prompt_accept?(prompt)
        end

      :eof ->
        prompt_accept?(prompt)
    end
  end
end
