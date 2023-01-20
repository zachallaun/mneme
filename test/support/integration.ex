defmodule Mneme.Integration.TestError do
  defexception [:message]
end

defmodule Mneme.Integration do
  @integration_test_dir File.cwd!() |> Path.join("test/integration")

  @doc """
  Generate an integration test module that will be run by ExUnit.
  """
  defmacro integration_test(basename) when is_binary(basename) do
    quote do
      defmodule unquote(module_name(basename)) do
        use ExUnit.Case, async: true

        @tag :tmp_dir
        test unquote(basename), %{tmp_dir: tmp_dir} do
          Mneme.Integration.__run__(unquote(basename), tmp_dir)
        end
      end
    end
  end

  def __run__(basename, tmp_dir) do
    template_file = Path.join(@integration_test_dir, basename <> ".template.exs")
    source_file = Path.join(tmp_dir, basename <> ".exs")
    File.cp!(template_file, source_file)

    expected_source = File.read!(Path.join(@integration_test_dir, basename <> ".expected.exs"))
    expected_output = File.read!(Path.join(@integration_test_dir, basename <> ".output.txt"))

    {output, exit_code} = System.shell("yes 2>/dev/null | mix test #{source_file}")

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

  defp normalize_output(output) do
    output
    |> String.replace(~r/Finished in.+\n/, "")
    |> String.replace(~r/\nRandomized with seed.+\n/, "")
  end

  defp module_name(basename) do
    Module.concat(__MODULE__, Macro.camelize(basename))
  end

  defp indent(message, indentation) do
    message
    |> String.split("\n")
    |> Enum.map(&[indentation, &1])
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end
end
