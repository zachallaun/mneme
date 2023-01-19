defmodule Mneme.Code do
  @moduledoc false

  alias Sourceror.Zipper

  defmodule AssertionResult do
    @moduledoc false
    defstruct [:type, :expr, :actual, :location]

    @type t :: %__MODULE__{
            type: :new | :fail,
            expr: Macro.t(),
            actual: any(),
            location: keyword()
          }
  end

  def handle_results(results) do
    results
    |> group_by_file()
    |> Enum.map(&get_patches/1)
    |> Enum.each(&patch_file/1)
  end

  defp group_by_file(results) do
    results
    |> Enum.sort_by(fn %{location: loc} -> {loc[:file], loc[:line]} end)
    |> Enum.chunk_by(fn %{location: loc} -> loc[:file] end)
    |> Enum.map(fn [%{location: loc} | _] = results -> {loc[:file], results} end)
  end

  defp get_patches({file, results}) do
    source = file |> File.read!()
    ast = Sourceror.parse_string!(source)

    {_, patches} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse([], fn
        {{:auto_assert, _, [inner]}, _} = zipper, patches ->
          if result = find_matching_result(results, inner) do
            {zipper, [assertion_patch(result, inner) | patches]}
          else
            {zipper, patches}
          end

        zipper, patches ->
          {zipper, patches}
      end)

    {file, source, patches}
  end

  defp find_matching_result(results, expr) do
    Enum.find(results, &result_matches?(&1, expr))
  end

  defp result_matches?(%{type: :new, location: loc}, {_, meta, _}) do
    loc[:line] == meta[:line]
  end

  defp result_matches?(%{}, _expr), do: false

  defp assertion_patch(%{type: :new, actual: actual}, ast) do
    replacement =
      {:=, [], [quote_actual(actual), ast]}
      |> Sourceror.to_string()

    %{change: replacement, range: Sourceror.get_range(ast)}
  end

  defp quote_actual(value) when is_integer(value), do: value
  defp quote_actual(value) when is_binary(value), do: value

  defp prompt_for_patch(%{type: :new} = result, ast) do
    nil
  end

  defp prompt_for_patch(_, _) do
    nil
  end

  defp patch_file({file, source, patches}) do
    patched = Sourceror.patch_string(source, patches)

    IO.puts(file)
    IO.puts(patched)
  end
end
