defmodule Mneme.Prompter.Terminal do
  @moduledoc false

  @behaviour Mneme.Prompter

  import Owl.Data, only: [tag: 2]

  alias Mneme.Assertion
  alias Rewrite.Source

  @impl true
  def prompt!(%Source{} = source, %Assertion{} = assertion) do
    %{type: type, context: context, pattern_notes: notes} = assertion

    prefix = tag("│ ", :light_black)

    message =
      [
        type_tag(type),
        tag(" • auto_assert", :light_black),
        "\n",
        file_tag(context),
        "\n\n",
        diff(source),
        notes_tag(notes)
      ]
      |> Owl.Data.add_prefix(prefix)

    Owl.IO.puts(["\n", message])

    prompt_accept?([prefix, explanation_tag(type)])
  end

  defp prompt_accept?(prompt) do
    Owl.IO.confirm(message: prompt)
  end

  defp diff(source) do
    Rewrite.TextDiff.format(
      source |> Source.code(Source.version(source) - 1) |> eof_newline(),
      source |> Source.code() |> eof_newline(),
      line_numbers: false,
      format: [
        separator: "",
        gutter: [eq: "   ", ins: " + ", del: " - ", skip: "..."]
      ]
    )
  end

  defp eof_newline(code), do: String.trim_trailing(code) <> "\n"

  defp file_tag(%{file: file, line: line} = _context) do
    path = Path.relative_to_cwd(file)
    tag([path, ":", to_string(line)], :light_black)
  end

  defp type_tag(:new), do: tag("New", :green)
  defp type_tag(:update), do: tag("Changed", :yellow)

  defp explanation_tag(:new) do
    "Accept new assertion?"
  end

  defp explanation_tag(:update) do
    [
      tag("Value has changed! ", :yellow),
      "Update to new value?"
    ]
  end

  defp notes_tag([]), do: []

  defp notes_tag(notes) do
    notes = Enum.uniq(notes)

    [
      "\n🛈 Notes about this assertion:\n",
      notes |> Owl.Data.unlines() |> Owl.Data.add_prefix("  * "),
      "\n"
    ]
    |> tag(:light_black)
  end
end
