defmodule Mneme.Patcher do
  @moduledoc false

  alias Mneme.Assertion
  alias Mneme.Terminal
  alias Rewrite.Source
  alias Sourceror.Zipper

  @type state :: Rewrite.t()
  @type source :: Source.t()

  @doc """
  Create initial patcher state.
  """
  @spec init() :: state
  def init do
    Rewrite.new()
  end

  @doc """
  Load and cache and source and AST required by the context.
  """
  @spec load_source!(state, String.t()) :: state
  def load_source!(%Rewrite{} = project, file) do
    if Rewrite.has_source?(project, file) do
      project
    else
      project
      |> Rewrite.read!(file)
      |> Rewrite.update!(file, fn %Source{} = source ->
        Source.put_private(source, :patched_ast, Source.get(source, :quoted))
      end)
    end
  end

  @doc """
  Finalize all patches, writing all results to disk.
  """
  @spec finalize!(state) :: :ok | {:error, term()}
  def finalize!(project) do
    case Rewrite.write_all(project) do
      {:ok, _project} ->
        :ok

      {:error, errors, _project} ->
        not_saved = Enum.map(errors, fn %Rewrite.SourceError{path: path} -> path end)

        {:error, {:not_saved, not_saved}}
    end
  end

  @doc """
  Patch an assertion.

  Returns `{result, patch_state}`.
  """
  @spec patch!(state, Assertion.t(), non_neg_integer()) ::
          {{:ok, Assertion.t()} | {:error, term()}, state}
  def patch!(%Rewrite{} = project, %Assertion{} = assertion, counter) do
    project = load_source!(project, assertion.context.file)

    case prepare_assertion(assertion, project) do
      {:ok, {assertion, node}} ->
        prompt_and_patch!(project, assertion, counter, node)

      {:error, :not_found} ->
        {{:error, :file_changed}, project}
    end
  rescue
    error ->
      {{:error, {:internal, error, __STACKTRACE__}}, project}
  end

  defp prompt_and_patch!(project, assertion, counter, node) do
    case prompt_change(assertion, counter) do
      :accept ->
        ast = replace_assertion_node(node, assertion.code)

        if assertion.options.dry_run do
          {{:ok, assertion}, project}
        else
          {:ok, project} =
            Rewrite.update(project, assertion.context.file, fn source ->
              source
              |> Source.update(:quoted, ast)
              |> Source.put_private(:patched_ast, ast)
            end)

          {{:ok, assertion}, project}
        end

      :reject ->
        {{:error, :rejected}, project}

      :skip ->
        {{:error, :skipped}, project}

      select ->
        prompt_and_patch!(project, Assertion.select(assertion, select), counter, node)
    end
  end

  defp prompt_change(%Assertion{options: %{action: :prompt}} = assertion, counter) do
    diff = %{left: format(assertion.rich_ast), right: format(assertion.code)}
    Terminal.prompt!(assertion, counter, diff)
  end

  defp prompt_change(%Assertion{options: %{action: action}}, _), do: action

  defp format(ast) do
    ast |> Source.Ex.format() |> String.trim()
  end

  defp prepare_assertion(assertion, project) do
    source = Rewrite.source!(project, assertion.context.file)

    zipper =
      source.private[:patched_ast]
      |> Zipper.zip()
      |> Zipper.find(&Assertion.same?(assertion, &1))

    if zipper do
      {rich_ast, comments} =
        zipper
        |> Zipper.node()
        |> Sourceror.Comments.extract_comments()

      {:ok, {Assertion.prepare_for_patch(assertion, rich_ast), {zipper, comments}}}
    else
      {:error, :not_found}
    end
  end

  defp replace_assertion_node({zipper, comments}, ast) do
    zipper
    |> Zipper.update(fn _ -> Sourceror.Comments.merge_comments(ast, comments) end)
    |> Zipper.root()
  end
end
