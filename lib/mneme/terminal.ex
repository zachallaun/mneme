defmodule Mneme.Terminal do
  @moduledoc false

  import Owl.Data, only: [tag: 2]

  alias Mneme.Assertion
  alias Mneme.Diff

  @middle_dot_char "·"
  @bullet_char "●"
  @empty_bullet_char "○"
  @arrow_left_char "❮"
  @arrow_right_char "❯"

  @box_horizontal "─"
  @box_vertical "│"
  @box_cross_down "┬"
  @box_cross_up "┴"

  def prompt!(%Assertion{} = assertion, counter, diff) do
    Owl.IO.puts(["\n", message(assertion, counter, diff, assertion.options)])
    input()
  end

  @doc false
  def message(%Assertion{} = assertion, counter, diff, opts) do
    notes = Assertion.pattern(assertion).notes

    [
      format_header(assertion, counter, opts),
      "\n",
      format_diff(diff, opts),
      format_notes(notes),
      format_input(assertion, opts),
      "\n"
    ]
  end

  defp input do
    case gets() do
      "y" -> :accept
      "n" -> :reject
      "s" -> :skip
      "k" -> :next
      "K" -> :last
      "j" -> :prev
      "J" -> :first
      _ -> input()
    end
  end

  defp gets do
    clear_to_end_of_line = "\e[0K"

    # Note: The cursor_up and cursor_right amounts need to be in sync
    # with the number of lines after the prompt and number of chars
    # before the prompt
    resp =
      [IO.ANSI.cursor_up(3), IO.ANSI.cursor_right(2), clear_to_end_of_line]
      |> IO.gets()
      |> normalize_gets()

    IO.write([IO.ANSI.cursor_down(2), "\r"])

    resp
  end

  defp normalize_gets(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      string -> string
    end
  end

  defp normalize_gets(_), do: nil

  defp format_diff(%{left: left, right: right}, %{diff: :text}) do
    TextDiff.format(eof_newline(left), eof_newline(right),
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

  defp format_diff(diff, %{diff: :semantic} = opts) do
    case await_semantic_diff(diff) do
      {del, ins} -> format_semantic_diff({del, ins}, opts)
      nil -> format_diff(diff, Map.put(opts, :diff, :text))
    end
  end

  defp await_semantic_diff(%{left: left, right: right}) do
    task = Task.async(Diff, :format, [left, right])

    case Task.yield(task, 1500) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, {nil, nil}}} -> {Owl.Data.lines(left), Owl.Data.lines(right)}
      {:ok, {:ok, {nil, ins}}} -> {Owl.Data.lines(left), ins}
      {:ok, {:ok, {del, nil}}} -> {del, Owl.Data.lines(right)}
      {:ok, {:ok, {del, ins}}} -> {del, ins}
      {:ok, {:error, {:internal, e, stacktrace}}} -> reraise e, stacktrace
      _ -> nil
    end
  end

  defp format_semantic_diff({del, ins}, opts) do
    del = tag_lines(del)
    ins = tag_lines(ins)

    del_height = length(del)
    ins_height = length(ins)

    del_length = del |> Enum.map(&Owl.Data.length/1) |> Enum.max()
    ins_length = ins |> Enum.map(&Owl.Data.length/1) |> Enum.max()

    deletions = del |> Owl.Data.unlines() |> Owl.Data.add_prefix(tag("  -  ", :red))
    insertions = ins |> Owl.Data.unlines() |> Owl.Data.add_prefix(tag("  +  ", :green))

    # add the size of the prefix added to each side of the diff above
    required_width = max(del_length, ins_length) + 5

    if cols_each = diff_side_by_side(opts, required_width) do
      height_padding =
        if del_height == ins_height do
          []
        else
          [
            "\n",
            "\n"
            |> String.duplicate(abs(del_height - ins_height) - 1)
            |> Owl.Data.add_prefix(tag("  #{@middle_dot_char} ", :faint))
          ]
        end

      {deletions, insertions} =
        if del_height < ins_height do
          {[deletions, height_padding], insertions}
        else
          {deletions, [insertions, height_padding]}
        end

      height = max(del_height, ins_height)
      left = diff_box(tag("old", :red), deletions, height, cols_each)
      right = diff_box(tag("new", :green), insertions, height, cols_each)

      joiner =
        tag(
          [
            @box_cross_down,
            "\n",
            String.duplicate("#{@box_vertical}\n", height),
            @box_cross_up
          ],
          :faint
        )

      [
        Enum.reduce([right, joiner, left], &Owl.Data.zip/2),
        "\n"
      ]
    else
      width = terminal_width(opts)

      [
        horizontal_border(width),
        "\n",
        deletions,
        "\n",
        horizontal_border(width),
        "\n",
        insertions,
        "\n",
        horizontal_border(width),
        "\n"
      ]
    end
  end

  @doc false
  @spec tag_lines([Diff.Formatter.formatted_line()] | [Owl.Data.t()]) :: [Owl.Data.t()]
  def tag_lines(lines) do
    Enum.map(lines, &tag_line/1)
  end

  defp tag_line(line) when is_binary(line), do: line

  defp tag_line({text, sequences}) when is_binary(text) do
    Owl.Data.tag(text, sequences)
  end

  defp tag_line(segments) when is_list(segments) do
    Enum.map(segments, fn
      {_, _} = tagged -> tag_line(tagged)
      other -> other
    end)
  end

  defp diff_box(title, content, height, width) do
    top_border = horizontal_border(width, title)

    bottom_border =
      if height > 8 do
        ["\n", top_border]
      else
        ["\n", horizontal_border(width)]
      end

    data = [top_border, "\n", content, bottom_border]

    Owl.Box.new(data, border_style: :none, min_width: width)
  end

  defp diff_side_by_side(%{diff_style: :side_by_side} = opts, largest_side) do
    width = terminal_width(opts)

    if largest_side * 2 <= width do
      div(width, 2)
    end
  end

  defp diff_side_by_side(%{diff_style: :stacked}, _), do: nil

  defp terminal_width(%{terminal_width: width}) when is_integer(width), do: width
  defp terminal_width(_opts), do: (Owl.IO.columns() || 99) - 1

  defp eof_newline(code), do: String.trim_trailing(code) <> "\n"

  defp format_header(assertion, counter, opts) do
    %{context: %{module: module, test: test}} = assertion
    overrides = Mneme.Options.overrides(opts)

    stage =
      case assertion.stage do
        :new -> tag("[#{counter}] New", :cyan)
        :update -> tag("[#{counter}] Update", :yellow)
      end

    [
      stage,
      tag([" ", @middle_dot_char, " "], :faint),
      to_string(test),
      [" (", inspect(module), ")"],
      if(overrides == [],
        do: [],
        else: tag([" ", @middle_dot_char, " ", inspect(overrides)], :faint)
      ),
      "\n",
      format_file(assertion),
      "\n"
    ]
  end

  defp format_file(%Assertion{context: %{file: file, line: line}}) do
    path = Path.relative_to_cwd(file)
    tag([path, ":", to_string(line)], :faint)
  end

  defp format_notes([]), do: []

  defp format_notes(notes) do
    notes = Enum.uniq(notes)

    [
      "\n",
      notes |> Owl.Data.unlines() |> Owl.Data.add_prefix(tag("Note: ", :magenta)),
      "\n"
    ]
  end

  defp format_input(assertion, opts) do
    [
      "\n",
      format_explanation(assertion.stage, opts),
      "\n",
      tag("> ", :faint),
      "\n",
      format_input_options(assertion)
    ]
  end

  defp format_input_options(assertion) do
    Enum.intersperse(
      [
        [tag("y", :green), " ", tag("yes", :faint)],
        [tag("n", :red), " ", tag("no", :faint)],
        [tag("s", :yellow), " ", tag("skip", :faint)],
        format_nav_options(assertion)
      ],
      ["  "]
    )
  end

  defp format_nav_options(%Assertion{} = assertion) do
    assertion |> Assertion.pattern_index() |> format_nav_options()
  end

  defp format_nav_options({_, 1}), do: ""

  defp format_nav_options({index, count}) do
    dots =
      Enum.map(0..(count - 1), fn
        ^index -> @bullet_char
        _ -> @empty_bullet_char
      end)

    [
      tag(@arrow_left_char, :faint),
      [" J", tag("/", :faint), "j "],
      tag(dots, :faint),
      [" k", tag("/", :faint), "K "],
      tag(@arrow_right_char, :faint)
    ]
  end

  defp format_explanation(:new, _opts) do
    "Accept new assertion?"
  end

  defp format_explanation(:update, %{force_update: true}) do
    [
      tag("Value may have changed.", :yellow),
      " Update pattern?"
    ]
  end

  defp format_explanation(:update, _opts) do
    [
      tag("Value has changed!", :yellow),
      " Update pattern?"
    ]
  end

  defp horizontal_border(width) when is_integer(width) do
    @box_horizontal |> String.duplicate(width) |> tag(:faint)
  end

  defp horizontal_border(width, title) when is_integer(width) do
    [
      tag(@box_horizontal, :faint),
      title,
      @box_horizontal |> String.duplicate(width - Owl.Data.length(title) - 1) |> tag(:faint)
    ]
  end
end
