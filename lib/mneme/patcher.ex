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
        Project.update(project, Source.read!(file))
    end
  end

  @doc """
  Finalize all patches, writing all results to disk.
  """
  def finalize!(project) do
    :ok = Project.save(project)
    project
  end

  @doc """
  Run an assertion patch.

  Returns `{result, patch_state}`.
  """
  def patch!(%Project{} = project, assertion, opts, prompt_state \\ nil) do
    {source, assertion} = patch_assertion(project, assertion, opts)

    case prompt_change(source, assertion, opts, prompt_state) do
      {:accept, _} ->
        {{:ok, assertion}, Project.update(project, source)}

      {:reject, _} ->
        {:error, project}

      {:prev, prompt_state} ->
        patch!(project, Assertion.prev(assertion, opts.target), opts, prompt_state)

      {:next, prompt_state} ->
        patch!(project, Assertion.next(assertion, opts.target), opts, prompt_state)
    end
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

  defp patch_assertion(project, assertion, opts) do
    source = Project.source!(project, assertion.file)

    zipper =
      source
      |> Source.ast()
      |> Zipper.zip()
      |> Zipper.find(&Assertion.same?(assertion, &1))

    # Hack: String serialization fix
    # Sourceror's AST is richer than the one we get back from a macro call.
    # String literals are in a :__block__ tuple and include a delimiter;
    # we use this information when formatting to ensure that the same
    # delimiters are used for output.
    assertion =
      assertion
      |> Map.put(:code, Zipper.node(zipper))
      |> Assertion.regenerate_code(opts.target, opts.default_pattern)

    ast =
      zipper
      |> zipper_update_with_meta(assertion.code)
      |> Zipper.root()
      |> escape_newlines()

    source =
      source
      |> Source.update(:mneme, ast: ast)
      |> Source.put_private(:diff, %{
        left: zipper |> Zipper.node() |> format_node(),
        right: assertion.code |> format_node()
      })

    {Source.update(source, :mneme, ast: ast), assertion}
  end

  defp format_node(node) do
    node
    |> Source.from_ast()
    |> Source.code()
  end

  defp zipper_update_with_meta(zipper, {:__block__, _, [{call1, _, args1}, {call2, _, args2}]}) do
    {_, meta, _} = Zipper.node(zipper)
    call1_meta = Keyword.put(meta, :end_of_expression, newlines: 1)

    zipper
    |> Zipper.insert_left({call1, call1_meta, args1})
    |> Zipper.insert_left({call2, meta, args2})
    |> Zipper.remove()
  end

  defp zipper_update_with_meta(zipper, {call, _, args}) do
    Zipper.update(zipper, fn {_, meta, _} -> {call, meta, args} end)
  end

  defp escape_newlines(code) when is_list(code) do
    Enum.map(code, &escape_newlines/1)
  end

  defp escape_newlines(code) do
    Sourceror.prewalk(code, fn
      {:__block__, meta, [string]} = quoted, state when is_binary(string) ->
        case meta[:delimiter] do
          "\"" -> {{:__block__, meta, [String.replace(string, "\n", "\\n")]}, state}
          _ -> {quoted, state}
        end

      quoted, state ->
        {quoted, state}
    end)
  end
end
