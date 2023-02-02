defmodule Mneme.Patcher do
  @moduledoc false

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
  Run an assertion patch.

  Returns `{result, patch_state}`.
  """
  def patch!(%SuiteResult{} = state, assertion, opts) do
    patch = patch_assertion(state, assertion, opts)

    if accept_patch?(patch, opts) do
      {{:ok, patch.expr}, accept_patch(state, patch)}
    else
      {:error, reject_patch(state, patch)}
    end
  end

  @doc """
  Load and cache and source and AST required by the context.
  """
  def load_file!(%SuiteResult{} = state, %{file: file}) do
    case state.files[file] do
      nil -> register_file(state, file, File.read!(file))
      _ -> state
    end
  end

  @doc """
  Registers the source and AST for the given file and content.
  """
  def register_file(%SuiteResult{} = state, file, source) do
    case state.files[file] do
      nil ->
        file_result = %FileResult{
          file: file,
          source: source,
          ast: Sourceror.parse_string!(source)
        }

        Map.update!(state, :files, &Map.put(&1, file, file_result))

      _ ->
        state
    end
  end

  @doc """
  Returns the line number of the test in which the given assertion is running.
  """
  def get_test_line!(
        %SuiteResult{files: files},
        {_type, _actual, %{file: file, line: line}}
      ) do
    files
    |> Map.fetch!(file)
    |> Map.fetch!(:ast)
    |> Zipper.zip()
    |> Zipper.find(fn
      {:test, meta, _} ->
        case {meta[:do][:line], meta[:end][:line]} do
          {test_start, test_end} when is_integer(test_start) and is_integer(test_end) ->
            test_start <= line && test_end >= line

          _ ->
            false
        end

      _ ->
        false
    end)
    |> case do
      {{:test, meta, _}, _} -> Keyword.fetch!(meta, :line)
      nil -> raise ArgumentError, "unable to find test for assertion at #{file}:#{line}"
    end
  end

  defp patch_assertion(%{files: files} = state, {type, actual, context}, _opts) do
    files
    |> Map.fetch!(context.file)
    |> Map.fetch!(:ast)
    |> Zipper.zip()
    |> Zipper.find(fn node -> Mneme.Code.mneme_assertion?(node, context) end)
    |> Zipper.node()
    |> create_patch(state, type, actual, context)
  end

  defp create_patch(node, %SuiteResult{format_opts: format_opts}, type, value, context) do
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

  defp accept_patch?(patch, %{action: :prompt, prompter: prompter}) do
    prompter.prompt!(patch)
  end

  defp accept_patch?(_patch, %{action: :accept}), do: true
  defp accept_patch?(_patch, %{action: :reject}), do: false

  defp accept_patch(state, patch) do
    update_in(state.files[patch.context.file].accepted, &[patch | &1])
  end

  defp reject_patch(state, patch) do
    update_in(state.files[patch.context.file].rejected, &[patch | &1])
  end
end
