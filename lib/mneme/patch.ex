defmodule Mneme.Patch do
  @moduledoc false

  alias Rewrite.DotFormatter
  alias Rewrite.TextDiff
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
  def finalize!(%SuiteResult{finalized: false} = state) do
    %{files: files, format_opts: format_opts} = state

    for {_, %FileResult{file: file, source: source, accepted: patches}} <- files do
      patched_iodata =
        source
        |> Sourceror.patch_string(patches)
        |> Code.format_string!(format_opts)

      File.write!(file, [patched_iodata, "\n"])
    end

    %{state | finalized: true}
  end

  def finalize!(%SuiteResult{finalized: true} = state), do: state

  @doc """
  Accepts a patch.
  """
  def accept(%SuiteResult{} = state, patch) do
    update_in(state.files[patch.context.file].accepted, &[patch | &1])
  end

  @doc """
  Rejects a patch.
  """
  def reject(%SuiteResult{} = state, patch) do
    update_in(state.files[patch.context.file].rejected, &[patch | &1])
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
    \n[Mneme] #{operation} assertion - #{context.file}:#{context.line}

    #{diff(original, replacement)}\
    """

    IO.puts(message)
    accept? = prompt_accept?("Accept change? (y/n) ")

    {accept?, state}
  end

  @doc """
  """
  def load_file!(%SuiteResult{files: files} = state, context) do
    with {:ok, file} <- Map.fetch(context, :file),
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
    file = context.file
    ast = Map.fetch!(files, file).ast

    {_, patch} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse(nil, fn
        {node, _} = zipper, nil ->
          if Mneme.Code.mneme_assertion?(node, context) do
            {zipper, create_patch(state, type, actual, context, node)}
          else
            {zipper, nil}
          end

        zipper, patch ->
          {zipper, patch}
      end)

    {patch, state}
  end

  defp create_patch(%SuiteResult{format_opts: format_opts}, type, value, context, node) do
    original = Mneme.Code.format_assertion(node, format_opts)
    assertion = Mneme.Code.update_assertion(node, type, value, context)
    replacement = Mneme.Code.format_assertion(assertion, format_opts)

    %{
      change: replacement,
      range: Sourceror.get_range(node),
      type: type,
      expr: assertion,
      context: context,
      original: original,
      replacement: replacement
    }
  end

  defp prompt_accept?(prompt, tries \\ 5)

  defp prompt_accept?(_prompt, 0), do: false

  defp prompt_accept?(prompt, tries) do
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
            prompt_accept?(prompt, tries - 1)
        end

      :eof ->
        prompt_accept?(prompt, tries - 1)
    end
  end

  defp diff(old, new) do
    TextDiff.format(old, new,
      line_numbers: false,
      before: 0,
      after: 0,
      format: [separator: "| "]
    )
    |> IO.iodata_to_binary()
  end
end
