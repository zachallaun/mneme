defmodule Mneme.Diff do
  @moduledoc false

  # Structural diffing for Elixir expressions.
  #
  # This module implements structural diffing for the subset of Elixir
  # expressions that would be found in Mneme auto-assertions. It may
  # expand in the future to cover the entire Elixir language, but that
  # is currently a non-goal.
  #
  # The strategy used here draws heavily (read: is shamelessly stolen)
  # from Difftastic (https://difftastic.wilfred.me.uk/) and Autochrome
  # (https://fazzone.github.io/autochrome.html).
  #
  # It models diffing as a directed graph/tree search, where vertices
  # are cursors in the source and target ASTs and edges are diff
  # instructions, i.e. "these nodes are the same" or "the left node is
  # different". Depending on the vertex, there are many possible edges
  # with different costs. Finding similar nodes is cheaper than marking
  # one side as unique, and Dijkstra's is used to find the cheapest path
  # to the end of both ASTs.
  #
  # I've vendored and modified a handful of modules from other libraries
  # to suit them better to this task:
  #
  #   * AST - Adapted from an experimental Sourceror branch that extends
  #     quoted expressions to make them more explicit, e.g. strings
  #     become `{:string, _meta, "some string"}`.
  #
  #   * Zipper - Sourceror's Zipper implementation modified slightly to
  #     work with the extended expressions defined in AST.
  #
  #   * Pathfinding - Adapted from libgraph's pathfinding module, but
  #     refactored to create lazy implementations of A* and Dijkstra's.
  #     This allows the graph to be created lazily during pathfinding
  #     instead of having to eagerly build it up front.
  #

  alias Mneme.Diff.AST
  alias Mneme.Diff.Delta
  alias Mneme.Diff.Formatter
  alias Mneme.Diff.Pathfinding
  alias Mneme.Diff.SyntaxNode
  alias Mneme.Diff.Zipper

  @type instruction ::
          {instruction_kind, :node | :delimiter, Zipper.t()}
          | {instruction_kind, :node, Zipper.t(), edit_script}

  @type instruction_kind :: :ins | :del

  @type edit_script :: [{:eq | :changed, String.t()}]

  @type vertex :: {left :: SyntaxNode.t(), right :: SyntaxNode.t(), delta :: Delta.t() | nil}

  @doc """
  Diffs and formats `left` (old) and `right` (new).
  """
  @spec format(String.t(), String.t()) ::
          {:ok, {left :: formatted, right :: formatted}} | {:error, term()}
        when formatted: [Formatter.formatted_line()] | nil
  def format(left, right) when is_binary(left) and is_binary(right) do
    result =
      case compute(left, right) do
        {[], []} -> {nil, nil}
        {[], ins} -> {nil, format_lines(right, ins)}
        {del, []} -> {format_lines(left, del), nil}
        {del, ins} -> {format_lines(left, del), format_lines(right, ins)}
      end

    {:ok, result}
  rescue
    e -> {:error, {:internal, e, __STACKTRACE__}}
  end

  @spec format_lines(String.t(), [instruction]) :: [Formatter.formatted_line()]
  defp format_lines(code, instructions) when is_binary(code) do
    Formatter.highlight_lines(code, instructions)
  end

  @spec compute(String.t(), String.t()) :: {[instruction], [instruction]}
  defp compute(left_code, right_code) when is_binary(left_code) and is_binary(right_code) do
    {left, right} = SyntaxNode.roots!(left_code, right_code)
    path = shortest_path({left, right, nil})

    if debug?() do
      debug_inspect(summarize_path(path), "path")
    end

    path
    |> split_changed()
    |> to_instructions()
  end

  @spec shortest_path(vertex) :: [Delta.t()]
  defp shortest_path(root) do
    [_root | path] = Pathfinding.lazy_dijkstra(root, &vertex_id/1, &neighbors/1)
    Enum.map(path, fn {_v1, _v2, delta} -> delta end)
  end

  @spec split_changed([Delta.t()]) :: {[Delta.t()], [Delta.t()]}
  defp split_changed(path) do
    path
    |> Stream.flat_map(fn
      %Delta{changed?: true} = delta -> [delta]
      changed when is_list(changed) -> changed
      _ -> []
    end)
    |> Enum.group_by(& &1.side)
    |> case do
      %{left: left, right: right} -> {left, right}
      %{left: left} -> {left, []}
      %{right: right} -> {[], right}
      _ -> {[], []}
    end
  end

  @spec to_instructions({[Delta.t()], [Delta.t()]}) :: {[instruction], [instruction]}
  defp to_instructions({left_changed, right_changed}) do
    {to_instructions(left_changed, :del), to_instructions(right_changed, :ins)}
  end

  defp to_instructions(changed_deltas, ins_kind) do
    changed_deltas
    |> coalesce()
    |> Enum.map(fn
      {kind, node} -> {ins_kind, kind, node.zipper}
      {kind, node, edit_script} -> {ins_kind, kind, node.zipper, edit_script}
    end)
  end

  defp coalesce(changed_deltas) do
    for_result =
      for %{kind: :node, node: node} <- changed_deltas do
        node.id
      end

    changed_node_ids =
      MapSet.new(for_result)

    changed_ids =
      for %{kind: :branch, node: branch} <- Enum.reverse(changed_deltas),
          reduce: changed_node_ids do
        ids ->
          if all_child_ids_in?(branch, ids) do
            MapSet.put(ids, branch.id)
          else
            ids
          end
      end

    Enum.flat_map(changed_deltas, fn %{kind: kind, node: node, edit_script: edit_script} ->
      branch? = kind == :branch
      parent = SyntaxNode.parent(node)

      cond do
        parent && parent.id in changed_ids ->
          []

        !branch? && edit_script != [] ->
          [{:node, node, edit_script}]

        !branch? ->
          [{:node, node}]

        all_child_ids_in?(node, changed_ids) ->
          [{:node, node}]

        true ->
          [{:delimiter, node}]
      end
    end)
  end

  defp all_child_ids_in?(branch, ids) do
    branch
    |> SyntaxNode.child_ids()
    |> Enum.all?(&(&1 in ids))
  end

  defp neighbors({l, r, e} = v) do
    if debug?("verbose") do
      debug_inspect(summarize_delta(e), "d")
      debug_inspect(summarize_node(l), "l")
      debug_inspect(summarize_node(r), "r")
      IO.puts("")
    end

    get_neighbors(v)
  end

  defp get_neighbors({%{terminal?: true}, %{terminal?: true}, _}), do: :halt

  defp get_neighbors({left, right, _} = v) do
    if SyntaxNode.similar?(left, right) do
      {:cont, add_unchanged_node([], v)}
    else
      {:cont,
       []
       |> maybe_add_unchanged_branch(v)
       |> add_changed_edges(v)}
    end
  end

  defp add_unchanged_node(neighbors, {left, right, _} = v) do
    delta = Delta.unchanged(:node, left, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))
    add_edge(neighbors, v, {SyntaxNode.next_sibling(left), SyntaxNode.next_sibling(right), delta})
  end

  defp maybe_add_unchanged_branch(
         neighbors,
         {%{branch?: true} = left, %{branch?: true} = right, _} = v
       ) do
    if SyntaxNode.similar_branch?(left, right) do
      delta =
        Delta.unchanged(:branch, left, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))

      pop_id = {left.id, right.id}

      v2 =
        {SyntaxNode.next_child(left, {:pop_both, pop_id}),
         SyntaxNode.next_child(right, {:pop_both, pop_id}), delta}

      add_edge(neighbors, v, v2)
    else
      neighbors
    end
  end

  defp maybe_add_unchanged_branch(neighbors, _v), do: neighbors

  # When both nodes are strings, we may want to include a Myers edit script
  defp add_changed_edges(neighbors, {%{form: :string} = left, %{form: :string} = right, _} = v) do
    case {SyntaxNode.ast(left), SyntaxNode.ast(right)} do
      {{:string, _, s1}, {:string, _, s2}} when is_binary(s1) and is_binary(s2) ->
        if String.bag_distance(s1, s2) > 0.5 do
          {left_edit, right_edit} = myers_edit_scripts(s1, s2)
          left_delta = Delta.changed(:node, :left, left, left_edit)
          right_delta = Delta.changed(:node, :right, right, right_edit)

          v2 = {
            SyntaxNode.next_sibling(left),
            SyntaxNode.next_sibling(right),
            [left_delta, right_delta]
          }

          add_edge(neighbors, v, v2)
        else
          add_changed_left_right(neighbors, v)
        end

      _ ->
        add_changed_left_right(neighbors, v)
    end
  end

  # When the parent is an unchanged binary operation, mark both nodes as
  # changed together to avoid arguments "sliding", e.g. `2 + 1` and `1 + 2`
  defp add_changed_edges(
         neighbors,
         {%{parent: {_, %{binary_op?: true}}} = left, right,
          %Delta{changed?: false, kind: :branch}} = v
       ) do
    v2 = {
      SyntaxNode.next_sibling(left),
      SyntaxNode.next_sibling(right),
      [Delta.changed(:node, :left, left), Delta.changed(:node, :right, right)]
    }

    add_edge(neighbors, v, v2)
  end

  defp add_changed_edges(neighbors, v) do
    add_changed_left_right(neighbors, v)
  end

  defp add_changed_left_right(neighbors, v) do
    neighbors
    |> add_changed_left(v)
    |> add_changed_right(v)
  end

  defp add_changed_left(neighbors, {left, %{null?: true} = right, _} = v) do
    add_edge(
      neighbors,
      v,
      {SyntaxNode.next_sibling(left), right, Delta.changed(:node, :left, left)}
    )
  end

  defp add_changed_left(neighbors, {%{branch?: true} = left, right, _} = v) do
    neighbors
    |> add_edge(v, {SyntaxNode.next_sibling(left), right, Delta.changed(:node, :left, left)})
    |> add_edge(v, {SyntaxNode.next_child(left), right, Delta.changed(:branch, :left, left)})
  end

  defp add_changed_left(neighbors, {%{branch?: false} = left, right, _} = v) do
    add_edge(
      neighbors,
      v,
      {SyntaxNode.next_sibling(left), right, Delta.changed(:node, :left, left)}
    )
  end

  defp add_changed_right(neighbors, {%{null?: true} = left, right, _} = v) do
    add_edge(
      neighbors,
      v,
      {left, SyntaxNode.next_sibling(right), Delta.changed(:node, :right, right)}
    )
  end

  defp add_changed_right(neighbors, {left, %{branch?: true} = right, _} = v) do
    neighbors
    |> add_edge(v, {left, SyntaxNode.next_sibling(right), Delta.changed(:node, :right, right)})
    |> add_edge(v, {left, SyntaxNode.next_child(right), Delta.changed(:branch, :right, right)})
  end

  defp add_changed_right(neighbors, {left, %{branch?: false} = right, _} = v) do
    add_edge(
      neighbors,
      v,
      {left, SyntaxNode.next_sibling(right), Delta.changed(:node, :right, right)}
    )
  end

  defp add_edge(neighbors, _v1, {left, right, delta}) do
    {left, right} = SyntaxNode.pop(left, right)
    [{{left, right, delta}, delta_cost(delta)} | neighbors]
  end

  defp delta_cost(%Delta{} = delta), do: Delta.cost(delta)
  defp delta_cost(list) when is_list(list), do: list |> Enum.map(&Delta.cost/1) |> Enum.sum()

  defp vertex_id({%{id: l_id, parent: nil}, %{id: r_id, parent: nil}, delta}) do
    {l_id, r_id, delta_id(delta)}
  end

  defp vertex_id({%{id: l_id, parent: {entry, _}}, %{id: r_id, parent: nil}, delta}) do
    {l_id, r_id, entry, delta_id(delta)}
  end

  defp vertex_id({%{id: l_id, parent: nil}, %{id: r_id, parent: {entry, _}}, delta}) do
    {l_id, r_id, entry, delta_id(delta)}
  end

  defp vertex_id({%{id: l_id, parent: {e1, _}}, %{id: r_id, parent: {e2, _}}, delta}) do
    {l_id, r_id, e1, e2, delta_id(delta)}
  end

  defp delta_id(nil), do: nil
  defp delta_id(list) when is_list(list), do: Enum.map(list, &delta_id/1)
  defp delta_id(d), do: {d.changed?, d.node.id}

  defp myers_edit_scripts(s1, s2) do
    s1
    |> String.myers_difference(s2)
    |> Enum.reduce({[], []}, fn
      {:eq, s}, {left, right} -> {[{:eq, s} | left], [{:eq, s} | right]}
      {:del, s}, {left, right} -> {[{:changed, s} | left], right}
      {:ins, s}, {left, right} -> {left, [{:changed, s} | right]}
    end)
    |> then(fn {left, right} -> {Enum.reverse(left), Enum.reverse(right)} end)
  end

  defp debug?, do: !!System.get_env("DEBUG_DIFF")
  defp debug?(value), do: System.get_env("DEBUG_DIFF") == value

  defp debug_inspect(term, label) do
    IO.inspect(term, label: label, pretty: true, syntax_colors: IO.ANSI.syntax_colors())
  end

  @doc false
  def summarize_path(path), do: Enum.map(path, &summarize_delta/1)

  defp summarize_delta(deltas) when is_list(deltas) do
    Enum.map(deltas, &summarize_delta/1)
  end

  defp summarize_delta(%Delta{changed?: changed?, kind: :node, side: side, node: node}) do
    {changed?, side, :node, summarize_node(node)}
  end

  defp summarize_delta(%Delta{changed?: changed?, kind: :branch, side: side, node: node}) do
    ast =
      case SyntaxNode.ast(node) do
        {{:., _, _}, _, _} -> {{:., [], "..."}, [], "..."}
        {form, _, _} -> {form, [], "..."}
        {_, _} -> {"...", "..."}
        list when is_list(list) -> ["..."]
      end

    {changed?, side, :branch, ast}
  end

  defp summarize_delta(nil), do: nil

  defp summarize_node(%SyntaxNode{terminal?: true}), do: "TERMINAL"
  defp summarize_node(%SyntaxNode{null?: true}), do: "NULL"

  defp summarize_node(node) do
    node
    |> SyntaxNode.ast()
    |> AST.prewalk(fn
      {form, _meta, args} -> {form, [], args}
      quoted -> quoted
    end)
  end
end
