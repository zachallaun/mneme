defmodule Mneme.Code do
  @moduledoc false

  alias Sourceror.Zipper

  defmodule AssertionResult do
    @moduledoc false
    defstruct [:type, :expr, :actual, :location]

    @type t :: %__MODULE__{
            type: :new | :replace,
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
    {_formatter, format_opts} = Mix.Tasks.Format.formatter_for_file(file)

    {_, patches} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse([], fn
        {{:auto_assert, _, [_]} = assert, _} = zipper, patches ->
          if result = find_matching_result(results, assert) do
            {zipper, [assertion_patch(result, assert, format_opts) | patches]}
          else
            {zipper, patches}
          end

        zipper, patches ->
          {zipper, patches}
      end)

    {file, source, patches}
  end

  defp find_matching_result(results, {_, meta, _}) do
    Enum.find(results, fn %{location: loc} ->
      loc[:line] == meta[:line]
    end)
  end

  defp assertion_patch(
         %{type: type, actual: actual},
         {:auto_assert, _, [inner]} = assert,
         format_opts
       ) do
    replacement =
      {:auto_assert, [], [update_match(type, inner, quote_actual(actual))]}
      |> Sourceror.to_string(format_opts)

    %{change: replacement, range: Sourceror.get_range(assert)}
  end

  defp update_match(:new, value, expected) do
    {:=, [], [expected, value]}
  end

  defp update_match(:replace, {:=, meta, [_old, value]}, expected) do
    {:=, meta, [expected, value]}
  end

  defp quote_actual(value) when is_integer(value), do: value
  defp quote_actual(value) when is_binary(value), do: value

  defp patch_file({_, _, []}), do: :ok

  defp patch_file({file, source, patches}) do
    patched = Sourceror.patch_string(source, patches)
    File.write!(file, patched)
  end
end
