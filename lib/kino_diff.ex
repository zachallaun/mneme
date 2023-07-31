if Code.ensure_loaded?(Kino) do
  defmodule KinoDiff do
    @moduledoc """
    Provides Livebook visualizations of Mneme diffs using Kino.
    """

    alias Kino.Frame
    alias Mneme.Diff
    alias Mneme.Diff.Delta
    alias Mneme.Diff.SyntaxNode
    alias Mneme.Diff.Zipper, as: Z

    @colors [
      ins: [:white, :green_background],
      ins_highlight: [:white, :green_background, :bright],
      del: [:white, :red_background],
      del_highlight: [:white, :red_background, :bright],
      match: [:white, :light_black_background]
    ]

    defstruct [:highlighted]

    @doc """
    Creates an interactive diff that can be stepped through.
    """
    def new(original, modified) do
      frame = Frame.new()

      controls = [keyboard: Kino.Control.keyboard([:keydown])]
      Kino.render(controls[:keyboard])

      state = %{
        frame: frame,
        steps: KinoDiff.diff_steps(original, modified),
        current: 0
      }

      controls
      |> Kino.Control.tagged_stream()
      |> Kino.listen(state, &handle_event/2)

      render!(state)

      frame
    end

    defp handle_event({:keyboard, event}, state) do
      state =
        case event do
          %{type: :keydown, key: "ArrowRight"} ->
            Map.update!(state, :current, &min(&1 + 1, length(state.steps) - 1))

          %{type: :keydown, key: "ArrowLeft"} ->
            Map.update!(state, :current, &max(&1 - 1, 0))

          _ ->
            state
        end

      render!(state)

      {:cont, state}
    end

    defp render!(%{frame: frame, steps: steps, current: idx}) do
      step = Enum.at(steps, idx)

      content =
        Kino.Layout.grid([
          Kino.Text.new("<- #{idx + 1} of #{length(steps)} ->"),
          step
        ])

      Frame.render(frame, content)
    end

    @doc false
    def diff_steps(left_code, right_code) do
      {left, right} = SyntaxNode.from_strings!(left_code, right_code)
      path = Diff.shortest_path({left, right, nil})

      path
      |> Enum.reverse()
      |> diff_steps(left_code, right_code)
      |> Enum.reverse()
    end

    defp diff_steps([_ | rest] = path, left_code, right_code) do
      {left_changed, right_changed} = Diff.split_sides(path)

      left_ins = Diff.to_instructions(left_changed, :del)
      right_ins = Diff.to_instructions(right_changed, :ins)

      step =
        render_step({highlight(left_code, left_ins), highlight(right_code, right_ins)}, path)

      [step | diff_steps(rest, left_code, right_code)]
    end

    defp diff_steps([], _, _), do: []

    @doc false
    def highlight(code, instructions) do
      text =
        code
        |> Diff.Formatter.highlight_lines(instructions, colors: @colors)
        |> Owl.Data.unlines()
        |> Owl.Data.to_ansidata()
        |> IO.iodata_to_binary()

      %__MODULE__{highlighted: text}
    end

    defp render_step({left, right}, [delta | _] = path) do
      cost = path |> Enum.map(&Delta.cost/1) |> Enum.sum()

      Kino.Layout.grid([
        Kino.Markdown.new("**Current cost:** #{cost}"),
        Kino.Markdown.new(render_delta(delta)),
        Kino.Layout.grid([left, right], columns: 2),
        log_nodes(delta)
      ])
    end

    defp render_delta(deltas) when is_list(deltas) do
      Enum.map_join(deltas, "\n", &render_delta/1)
    end

    defp render_delta(%{changed?: false, kind: kind}) do
      """
      **Matched #{kind}**
      """
    end

    defp render_delta(%{changed?: true, kind: kind, side: side} = delta) do
      node = Delta.node(delta)
      tag = node.parent && elem(node.parent, 0)

      """
      **Changed #{kind}** (#{side}, cost #{Delta.cost(delta)}, parent #{tag})
      """
    end

    defp summarize_z(z) do
      case Z.node(z) do
        {form, meta, list} when is_list(list) ->
          {form, Map.take(meta, [:line, :column]), :...}

        {form, meta, val} ->
          {form, Map.take(meta, [:line, :column]), val}

        list when is_list(list) ->
          [:...]

        {_, _} ->
          {:..., :...}

        other ->
          other
      end
    end

    defp summarize_parent(nil), do: nil
    defp summarize_parent({tag, parent}), do: {tag, summarize_z(parent.zipper)}

    defp log_nodes(deltas) when is_list(deltas) do
      for d <- deltas, do: log_nodes(d)
    end

    defp log_nodes(d) do
      [
        left_node_______: summarize_z(d.left_node.zipper),
        left_pre_next___: summarize_z(d.left_node_before.zipper),
        left_post_next__: summarize_z(d.left_node_after.zipper),
        left_pre_parent_: summarize_parent(d.left_node_before.parent),
        left_post_parent: summarize_parent(d.left_node_after.parent),
        right_node_____: summarize_z(d.right_node.zipper),
        right_pre_next_: summarize_z(d.right_node_before.zipper),
        right_post_next: summarize_z(d.right_node_after.zipper),
        right_pre_parent_: summarize_parent(d.right_node_before.parent),
        right_post_parent: summarize_parent(d.right_node_after.parent)
      ]
    end

    defimpl Kino.Render do
      def to_livebook(%{highlighted: text}), do: {:text, text}
    end
  end
end
