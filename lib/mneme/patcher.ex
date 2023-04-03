defmodule Mneme.Patcher do
  @moduledoc false

  alias Mneme.Assertion
  alias Sourceror.Zipper
  alias Rewrite.Project
  alias Rewrite.Source

  @type state :: Project.t()
  @type source :: Source.t()

  @doc """
  Create initial patcher state.
  """
  @spec init() :: state
  def init do
    Rewrite.Project.from_sources([])
  end

  @doc """
  Load and cache and source and AST required by the context.
  """
  @spec load_source!(state, String.t()) :: {state, source}
  def load_source!(%Project{} = project, file) do
    case Project.source(project, file) do
      {:ok, source} ->
        {project, source}

      :error ->
        source =
          file
          |> Source.read!()
          |> Source.put_private(:hash, content_hash(file))

        {Project.update(project, source), source}
    end
  end

  @doc """
  Finalize all patches, writing all results to disk.
  """
  @spec finalize!(state) :: :ok | {:error, term()}
  def finalize!(project) do
    if Application.get_env(:mneme, :dry_run) do
      :ok
    else
      unsaved_files =
        project
        |> Project.sources()
        |> Enum.flat_map(fn source ->
          file = Source.path(source)

          if source.private[:hash] == content_hash(file) do
            case Source.save(source) do
              :ok -> []
              _ -> [file]
            end
          else
            [file]
          end
        end)

      if unsaved_files == [] do
        :ok
      else
        {:error, {:not_saved, unsaved_files}}
      end
    end
  end

  defp content_hash(file) do
    data = File.read!(file)
    :crypto.hash(:sha256, data)
  end

  @doc """
  Patch an assertion.

  Returns `{result, patch_state}`.
  """
  @spec patch!(state, Assertion.t(), map()) ::
          {{:ok, Assertion.t()} | {:error, term()}, state}
  def patch!(%Project{} = project, %Assertion{} = assertion, %{} = opts) do
    {project, source} = load_source!(project, assertion.context.file)
    {assertion, zipper} = prepare_assertion(assertion, source)
    patch!(project, source, assertion, zipper, opts)
  rescue
    error ->
      {{:error, {:internal, error, __STACKTRACE__}}, project}
  end

  defp patch!(_, _, %{value: :__mneme__super_secret_test_value_goes_boom__}, _, _) do
    raise ArgumentError, "I told you!"
  end

  defp patch!(project, source, assertion, zipper, opts) do
    assertion = Assertion.generate_code(assertion, opts.target, opts.default_pattern)

    case prompt_change(assertion, opts) do
      :accept ->
        ast =
          zipper
          |> Zipper.update(fn _ -> assertion.code end)
          |> Zipper.root()

        source = Source.update(source, :mneme, ast: ast)

        {{:ok, assertion}, Project.update(project, source)}

      :reject ->
        {{:error, :no_pattern}, project}

      :skip ->
        {{:error, :skip}, project}

      :prev ->
        patch!(project, source, Assertion.prev(assertion), zipper, opts)

      :next ->
        patch!(project, source, Assertion.next(assertion), zipper, opts)
    end
  end

  defp prompt_change(assertion, %{action: :prompt, prompter: prompter} = opts) do
    diff = %{left: format_node(assertion.rich_ast), right: format_node(assertion.code)}
    prompter.prompt!(assertion, diff, opts)
  end

  defp prompt_change(_, %{action: action}), do: action

  defp prepare_assertion(assertion, source) do
    zipper =
      source
      |> Source.ast()
      |> Zipper.zip()
      |> Zipper.find(&Assertion.same?(assertion, &1))

    {Assertion.put_rich_ast(assertion, Zipper.node(zipper)), zipper}
  end

  defp format_node(node) do
    node
    |> Source.from_ast()
    |> Source.code()
  end
end
