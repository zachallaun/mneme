defmodule Mneme.Patch do
  @moduledoc false

  alias Mneme.Format
  alias Mneme.Serialize
  alias Rewrite.DotFormatter
  alias Rewrite.Project
  alias Rewrite.Source
  alias Sourceror.Zipper

  def project, do: %Project{}

  def apply_changes!(project) do
    :ok = Project.save(project)
    project()
  end

  def handle_assertion(project, {type, _expr, actual, meta}) do
    file = meta[:file]
    line = meta[:line]

    {source, project} = get_source(project, file)

    {_, patch} =
      source
      |> Source.ast()
      |> Zipper.zip()
      |> Zipper.traverse(nil, fn
        {{:auto_assert, assert_meta, [_]} = assert, _} = zipper, nil ->
          if assert_meta[:line] == line do
            {zipper, assertion_patch(type, meta, actual, assert)}
          else
            {zipper, nil}
          end

        zipper, patch ->
          {zipper, patch}
      end)

    if patch do
      {{:ok, patch.expr}, update_in(state.patches[file], &[patch | &1])}
    else
      {:error, state}
    end
  end

  defp get_source(project, file) do
    case Project.source(project, file) do
      {:ok, source} ->
        {source, project}

      :error ->
        source = Source.read!(file)
        project = Project.update(project, source)
        {source, project}
    end
  end

  defp assertion_patch(
         type,
         meta,
         actual,
         {:auto_assert, _, [inner]} = assert
       ) do
    format_opts = DotFormatter.opts()
    original = {:auto_assert, [], [inner]} |> Sourceror.to_string(format_opts)
    expr = update_match(type, inner, Serialize.to_match_expressions(actual, meta))

    replacement =
      {:auto_assert, [], [expr]}
      |> Sourceror.to_string(format_opts)

    if accept_change?(type, meta, original, replacement) do
      %{expr: expr, change: replacement, range: Sourceror.get_range(assert)}
    end
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

  defp patch_file!({_file, []}), do: :ok

  defp patch_file!({file, patches}) do
    source = File.read!(file)
    patched = Sourceror.patch_string(source, patches)
    File.write!(file, patched)
  end

  defp accept_change?(type, meta, original, replacement) do
    operation =
      case type do
        :new -> "New"
        :replace -> "Update"
      end

    message = """
    \n[Mneme] #{operation} assertion - #{meta[:file]}:#{meta[:line]}

    #{Format.prefix_lines(original, "- ")}
    #{Format.prefix_lines(replacement, "+ ")}
    """

    IO.puts(message)
    prompt_action("Accept change? (y/n) ")
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
end
