defmodule Mneme.Patch do
  @moduledoc false

  alias Mneme.Format
  alias Mneme.Serialize
  alias Rewrite.DotFormatter
  alias Sourceror.Zipper

  defmodule SuiteResult do
    @moduledoc false
    defstruct asts: %{},
              accepted_patches: %{},
              rejected_patches: %{},
              format_opts: [],
              finalized: false
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
  def finalize(%SuiteResult{finalized: false, accepted_patches: patches} = state) do
    Enum.each(patches, &patch_file!/1)
    %{state | finalized: true}
  end

  def finalize(%SuiteResult{finalized: true} = state), do: state

  @doc """
  Accepts a patch.
  """
  def accept(%SuiteResult{} = state, patch) do
    update_in(state.accepted_patches[patch.context[:file]], &[patch | &1])
  end

  @doc """
  Rejects a patch.
  """
  def reject(%SuiteResult{} = state, patch) do
    update_in(state.rejected_patches[patch.context[:file]], &[patch | &1])
  end

  @doc """
  Prompts the user to accept the patch.
  """
  def accept_patch?(%{type: type, context: context, original: original, replacement: replacement}) do
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
    prompt_action("Accept change? (y/n) ")
  end

  @doc """
  Construct the patch and updated state for the given assertion.
  """
  def patch_for_assertion(state, {type, actual, context}) do
    file = context[:file]
    line = context[:line]

    {ast, state} = file_data(state, file)

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

  defp file_data(%{asts: asts} = state, file) do
    case {asts, file} do
      {%{^file => ast}, _} ->
        {ast, state}

      {_asts, file} ->
        ast = file |> File.read!() |> Sourceror.parse_string!()

        state =
          state
          |> Map.update!(:asts, &Map.put(&1, file, ast))
          |> Map.update!(:accepted_patches, &Map.put(&1, file, []))
          |> Map.update!(:rejected_patches, &Map.put(&1, file, []))

        {ast, state}
    end
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

  defp prompt_action(prompt) do
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
            prompt_action(prompt)
        end

      :eof ->
        prompt_action(prompt)
    end
  end

  defp patch_file!({_file, []}), do: :ok

  defp patch_file!({file, patches}) do
    source = File.read!(file)
    patched = Sourceror.patch_string(source, patches)
    File.write!(file, patched)
  end
end
