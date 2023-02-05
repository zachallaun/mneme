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

    for {_, %FileResult{file: file, source: source, accepted: [_ | _] = patches}} <- files do
      patched_iodata =
        source
        |> Sourceror.patch_string(patches)
        |> Sourceror.parse_string!()
        |> Sourceror.to_string(format_opts)

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
      {{:ok, patch.assertion}, accept_patch(state, patch)}
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

  defp patch_assertion(%{files: files} = state, assertion, _opts) do
    files
    |> Map.fetch!(assertion.context.file)
    |> Map.fetch!(:ast)
    |> Zipper.zip()
    |> Zipper.find(fn node -> Mneme.Assertion.same?(assertion, node) end)
    |> Zipper.node()
    |> Sourceror.get_range()
    |> create_patch(state, assertion)
  end

  defp create_patch(range, %SuiteResult{format_opts: format_opts}, assertion) do
    original = Mneme.Assertion.format(assertion, format_opts)
    {_, _, [new_code]} = Mneme.Assertion.convert(assertion, target: :mneme)
    new_assertion = Map.put(assertion, :code, new_code)
    replacement = Mneme.Assertion.format(new_assertion, format_opts)

    %{
      range: range,
      change: replacement,
      assertion: new_assertion,
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
    update_in(state.files[patch.assertion.context.file].accepted, &[patch | &1])
  end

  defp reject_patch(state, patch) do
    update_in(state.files[patch.assertion.context.file].rejected, &[patch | &1])
  end
end
