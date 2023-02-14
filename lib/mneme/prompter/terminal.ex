defmodule Mneme.Prompter.Terminal do
  @moduledoc false

  @behaviour Mneme.Prompter

  import Owl.Data, only: [tag: 2]

  alias Mneme.Assertion
  alias Rewrite.Source

  @cursor_save "\e7"
  @cursor_restore "\e8"

  @bullet_char "●"
  @empty_bullet_char "○"
  @info_char "🛈"
  @arrow_left_char "❮"
  @arrow_right_car "❯"

  @impl true
  def prompt!(%Source{} = source, %Assertion{} = assertion, _prompt_state) do
    %{type: type, context: context} = assertion

    message =
      message(
        source,
        type,
        context,
        Assertion.pattern_index(assertion),
        Assertion.notes(assertion)
      )

    Owl.IO.puts(["\n\n", message])
    result = input()
    IO.write([IO.ANSI.cursor_down(2), "\r"])

    {result, nil}
  end

  @doc false
  def message(source, type, context, pattern_nav, notes) do
    prefix = tag("│ ", :light_black)

    [
      header_tag(type, context),
      "\n",
      diff(source),
      notes_tag(notes),
      "\n",
      explanation_tag(type),
      "\n",
      tag("> ", :light_black),
      @cursor_save,
      "\n",
      input_options_tag(pattern_nav)
    ]
    |> Owl.Data.add_prefix(prefix)
  end

  defp input() do
    IO.write(@cursor_restore)

    case gets() do
      "y" -> :accept
      "n" -> :reject
      "k" -> :next
      "j" -> :prev
      _ -> input()
    end
  end

  defp gets do
    IO.gets("") |> normalize_gets()
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
        gutter: [eq: "   ", ins: " + ", del: " - ", skip: "..."],
        colors: [
          ins: [text: :green, space: IO.ANSI.color_background(0, 1, 0)],
          del: [text: :red, space: IO.ANSI.color_background(1, 0, 0)],
          skip: [text: :yellow],
          separator: [text: :yellow]
        ]
      ],
      colorizer: &tag/2
    )
  end

  defp eof_newline(code), do: String.trim_trailing(code) <> "\n"

  defp header_tag(type, context) do
    [
      type_tag(type),
      tag([" ", @bullet_char, " "], [:faint, :light_black]),
      to_string(context.test),
      " (",
      to_string(context.module),
      ")\n",
      file_tag(context),
      "\n"
    ]
  end

  defp file_tag(%{file: file, line: line} = _context) do
    path = Path.relative_to_cwd(file)
    tag([path, ":", to_string(line)], :light_black)
  end

  defp type_tag(:new), do: tag("[Mneme] New", :green)
  defp type_tag(:update), do: tag("[Mneme] Changed", :yellow)

  defp explanation_tag(:new) do
    "Accept new assertion?"
  end

  defp explanation_tag(:update) do
    [
      tag("Value has changed! ", :yellow),
      "Update pattern?"
    ]
  end

  defp notes_tag([]), do: []

  defp notes_tag(notes) do
    notes = Enum.uniq(notes)

    [
      "\n#{@info_char} Notes about this assertion:\n",
      notes |> Owl.Data.unlines() |> Owl.Data.add_prefix("  * "),
      "\n"
    ]
    |> tag(:light_black)
  end

  defp input_options_tag(nav) do
    [
      [tag("y ", :green), tag("yes", [:faint, :green])],
      [tag("n ", :red), tag("no", [:faint, :red])],
      nav_options_tag(nav)
    ]
    |> Enum.intersperse(["  "])
  end

  defp nav_options_tag({index, count}) do
    dots = Enum.map(0..(count - 1), &if(&1 == index, do: @bullet_char, else: @empty_bullet_char))

    tag(
      ["#{@arrow_left_char} j ", dots, " k #{@arrow_right_car}"],
      if(count > 1, do: :light_black, else: [:faint, :light_black])
    )
  end
end
