defmodule Mneme.Prompter.Terminal do
  @moduledoc false

  @behaviour Mneme.Prompter

  import Owl.Data, only: [tag: 2]

  alias Mneme.Assertion
  alias Rewrite.Source

  @impl true
  def prompt!(%Source{} = source, %Assertion{} = assertion, reprompt) do
    %{type: type, context: context, patterns: patterns} = assertion
    [{_, _, notes} | _] = patterns

    prefix = tag("│ ", :light_black)

    header =
      if reprompt do
        []
      else
        [
          type_tag(type),
          tag(" • auto_assert", :light_black),
          "\n",
          file_tag(context),
          "\n"
        ]
      end

    message =
      [
        header,
        "\n",
        diff(source),
        notes_tag(notes),
        "\n",
        explanation_tag(type),
        " ",
        input_options_tag(assertion)
      ]
      |> Owl.Data.add_prefix(prefix)

    if reprompt do
      Owl.IO.puts(message)
    else
      Owl.IO.puts(["\n", message])
    end

    prompt = tag([prefix, "> "], :light_black) |> Owl.Data.to_ansidata()
    input(prompt, assertion)
  end

  defp input(prompt, assertion) do
    case gets(prompt) do
      "a" ->
        :accept

      "r" ->
        :reject

      "p" ->
        if Assertion.has_prev?(assertion) do
          :prev
        else
          input(prompt, assertion)
        end

      "n" ->
        if Assertion.has_next?(assertion) do
          :next
        else
          input(prompt, assertion)
        end

      _ ->
        input(prompt, assertion)
    end
  end

  defp gets(prompt) do
    prompt
    |> Owl.Data.to_ansidata()
    |> IO.gets()
    |> normalize_gets()
  end

  defp normalize_gets(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      string -> String.downcase(string)
    end
  end

  defp normalize_gets(_), do: nil

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

  defp input_options_tag(assertion) do
    bullet = tag("●", [:faint, :light_black])

    [
      input_option("a", "accept", :green, true),
      input_option("r", "reject", :red, true),
      input_option("n", "next", :cyan, Assertion.has_next?(assertion)),
      input_option("p", "previous", :cyan, Assertion.has_prev?(assertion))
    ]
    |> Enum.intersperse([" ", bullet, " "])
  end

  defp input_option(char, name, color, enabled?) do
    [
      tag(char, if(enabled?, do: color, else: [:faint, :light_black])),
      " ",
      tag(name, if(enabled?, do: [:faint, color], else: [:faint, :light_black]))
    ]
  end
end
