defmodule Mneme.Patcher do
  @moduledoc false

  alias Mneme.Assertion
  alias Sourceror.Zipper
  alias Rewrite.Project
  alias Rewrite.Source

  @doc """
  Initialize patch state.
  """
  def init do
    Rewrite.Project.from_sources([])
  end

  @doc """
  Load and cache and source and AST required by the context.
  """
  def load_file!(%Project{} = project, file) do
    case Project.source(project, file) do
      {:ok, _source} ->
        project

      :error ->
        source =
          file
          |> Source.read!()
          |> Source.put_private(:hash, content_hash(file))

        Project.update(project, source)
    end
  end

  @doc """
  Finalize all patches, writing all results to disk.
  """
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
  Run an assertion patch.

  Returns `{result, patch_state}`.
  """
  def patch!(%Project{} = project, assertion, opts, prompt_state \\ nil) do
    project = load_file!(project, assertion.context.file)
    {source, assertion} = patch_assertion(project, assertion, opts)

    case prompt_change(source, assertion, opts, prompt_state) do
      {:accept, _} ->
        {{:ok, assertion}, Project.update(project, source)}

      {:reject, _} ->
        {{:error, :no_pattern}, project}

      {:skip, _} ->
        {{:error, :skip}, project}

      {:prev, prompt_state} ->
        patch!(project, Assertion.prev(assertion, opts.target), opts, prompt_state)

      {:next, prompt_state} ->
        patch!(project, Assertion.next(assertion, opts.target), opts, prompt_state)
    end
  rescue
    error ->
      {{:error, {:internal, error, __STACKTRACE__}}, project}
  end

  defp prompt_change(
         source,
         assertion,
         %{action: :prompt, prompter: prompter} = opts,
         prompt_state
       ) do
    prompter.prompt!(source, assertion, opts, prompt_state)
  end

  defp prompt_change(_, _, %{action: action}, _), do: {action, nil}

  defp patch_assertion(_, %{value: :__mneme__super_secret_test_value_goes_boom__}, _) do
    raise ArgumentError, "I told you!"
  end

  defp patch_assertion(project, assertion, opts) do
    source = Project.source!(project, assertion.context.file)

    zipper =
      source
      |> Source.ast()
      |> Zipper.zip()
      |> Zipper.find(&Assertion.same?(assertion, &1))

    # Sourceror's AST is richer than the one we get back from a macro call.
    # String literals are in a :__block__ tuple and include a delimiter;
    # we use this information when formatting to ensure that the same
    # delimiters are used for output.
    assertion =
      assertion
      |> Map.put(:code, Zipper.node(zipper))
      |> Assertion.regenerate_code(opts.target, opts.default_pattern)

    code = escape_strings(assertion.code)

    ast =
      zipper
      |> Zipper.update(fn _ -> code end)
      |> Zipper.root()

    source =
      source
      |> Source.update(:mneme, ast: ast)
      |> Source.put_private(:diff, %{
        left: zipper |> Zipper.node() |> format_node(),
        right: code |> format_node()
      })

    {source, assertion}
  end

  defp format_node(node) do
    node
    |> Source.from_ast()
    |> Source.code()
  end

  def escape_strings(code) when is_list(code) do
    Enum.map(code, &escape_strings/1)
  end

  def escape_strings(code) do
    Sourceror.prewalk(code, fn
      {:__block__, meta, [string]} = quoted, state when is_binary(string) ->
        case meta[:delimiter] do
          "\"" -> {{:__block__, meta, [escape_string(string)]}, state}
          _ -> {quoted, state}
        end

      quoted, state ->
        {quoted, state}
    end)
  end

  defp escape_string(string) when is_binary(string) do
    string
    |> String.replace("\n", "\\n")
    |> String.replace("\#{", "\\\#{")

    # |> String.replace("\"", "\\\"")
  end
end
