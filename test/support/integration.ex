defmodule Mneme.Integration.TestError do
  defexception [:message]
end

defmodule Mneme.Integration do
  alias Mneme.Format

  @integration_test_dir File.cwd!() |> Path.join("test/integration")

  @doc """
  Generate an integration test module that will be run by ExUnit.
  """
  defmacro integration_test(basename) when is_binary(basename) do
    quote do
      defmodule unquote(unique_module_name(basename)) do
        use ExUnit.Case, async: true

        @tag :tmp_dir
        test unquote(basename), %{tmp_dir: tmp_dir} do
          Mneme.Integration.__run__(unquote(basename), tmp_dir)
        end
      end
    end
  end

  def __run__(basename, tmp_dir) do
    source_file = Path.join(tmp_dir, basename <> ".exs")
    File.cp!(file(:template, basename), source_file)

    {input, expected_output} = read_io_file!(basename)
    expected_source = read!(:expected, basename)

    {output, exit_code} = System.shell(~s(echo "#{input}" | mix test #{source_file} --seed 0))

    actual_source = File.read!(source_file)
    actual_output = normalize_output(output)

    errors =
      [
        {exit_code == 0, "Exit code was not zero (was #{exit_code})"},
        {actual_source == expected_source,
         """
         Source does not match:

           Expected:
         #{indent(expected_source, "    ")}

           Actual:
         #{indent(actual_source, "    ")}
         """},
        {actual_output == expected_output,
         """
         Output does not match:

           Expected:
         #{indent(expected_output, "    ")}
           Actual:
         #{indent(actual_output, "    ")}
         """}
      ]
      |> Enum.reject(fn {check, _} -> check end)
      |> Enum.map(fn {_, message} -> message end)

    unless errors == [] do
      message = "\n" <> Enum.join(errors, "\n")
      raise Mneme.Integration.TestError, message: message
    end
  end

  defp file(:template, basename),
    do: Path.join(@integration_test_dir, basename <> ".template.exs")

  defp file(:io, basename), do: Path.join(@integration_test_dir, basename <> ".io.txt")

  defp file(:expected, basename),
    do: Path.join(@integration_test_dir, basename <> ".expected.exs")

  defp read!(type, basename), do: file(type, basename) |> File.read!()

  defp read_io_file!(basename) do
    {outputs, inputs} =
      read!(:io, basename)
      |> String.split(~r/!\{[^}]+\}/, include_captures: true)
      |> alternate()

    input =
      inputs
      |> Enum.map(&(&1 |> String.trim_leading("!{") |> String.trim_trailing("}")))
      |> Enum.join()

    output =
      outputs
      |> Enum.join()
      |> normalize_output()

    {input, output}
  end

  defp alternate(list), do: alternate(list, :left, {[], []})

  defp alternate([], _, {left, right}) do
    {Enum.reverse(left), Enum.reverse(right)}
  end

  defp alternate([head | tail], :left, {left, right}) do
    alternate(tail, :right, {[head | left], right})
  end

  defp alternate([head | tail], :right, {left, right}) do
    alternate(tail, :left, {left, [head | right]})
  end

  defp normalize_output(output) do
    output
    |> String.replace(~r/Finished in.+\n/, "")
    |> String.replace(~r/\nRandomized with seed.+\n/, "")
    |> String.replace(~r/\[Mneme\] ((Update)|(New)) assertion.+\n/, "[Mneme] \\1 assertion\n")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.join("\n")
  end

  defp unique_module_name(basename, i \\ 0) do
    module = Module.concat([__MODULE__, Macro.camelize(basename), to_string(i)])

    case function_exported?(module, :__info__, 1) do
      true -> unique_module_name(basename, i + 1)
      false -> module
    end
  end

  defp indent(message, indentation) do
    Format.prefix_lines(message, indentation)
  end
end
