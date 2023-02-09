defmodule Mneme.Patcher do
  @moduledoc false

  alias Mneme.Utils
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
    %SuiteResult{format_opts: Utils.formatter_opts()}
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
    {patch, assertion} = patch_assertion(state, assertion, opts)

    if accept_patch?(patch, opts) do
      {{:ok, assertion}, accept_patch(state, patch, assertion)}
    else
      {:error, reject_patch(state, patch, assertion)}
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

  defp patch_assertion(%{files: files} = state, assertion, opts) do
    files
    |> Map.fetch!(assertion.context.file)
    |> Map.fetch!(:ast)
    |> Zipper.zip()
    |> Zipper.find(fn node -> Mneme.Assertion.same?(assertion, node) end)
    |> Zipper.node()
    |> create_patch(state, assertion, opts)
  end

  defp create_patch(node, %SuiteResult{format_opts: format_opts}, assertion, opts) do
    # HACK: String serialization fix
    # Sourceror's AST is richer than the one we get from the macro call.
    # In particular, string literals are in a :__block__ tuple and include
    # delimiter information. We use this when formatting to ensure that
    # the same delimiters are used.
    node = remove_comments(node)
    assertion = Map.put(assertion, :code, node)

    new_assertion = Mneme.Assertion.regenerate_code(assertion, opts.target)

    patch = %{
      change: Mneme.Assertion.format(new_assertion, format_opts),
      range: Sourceror.get_range(node),
      original: assertion,
      replacement: new_assertion,
      format_opts: format_opts
    }

    {patch, new_assertion}
  end

  defp remove_comments({call, meta, body}) do
    meta = Keyword.drop(meta, [:leading_comments, :trailing_comments])
    {call, meta, body}
  end

  defp accept_patch?(patch, %{action: :prompt, prompter: prompter}) do
    prompter.prompt!(patch)
  end

  defp accept_patch?(_patch, %{action: :accept}), do: true
  defp accept_patch?(_patch, %{action: :reject}), do: false

  defp accept_patch(state, patch, assertion) do
    update_in(state.files[assertion.context.file].accepted, &[patch | &1])
  end

  defp reject_patch(state, patch, assertion) do
    update_in(state.files[assertion.context.file].rejected, &[patch | &1])
  end
end
