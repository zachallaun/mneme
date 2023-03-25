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
  alias Mneme.Diff.Edge
  alias Mneme.Diff.Formatter
  alias Mneme.Diff.Pathfinding
  alias Mneme.Diff.SyntaxNode

  @doc """
  Formats `left` and `right` as `t:Owl.Data.t()`.
  """
  def format(left, right) do
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

  @doc """
  Formats `code` as `t:Owl.Data.t()` using the given instructions.
  """
  def format_lines(code, instructions) when is_binary(code) do
    Formatter.highlight_lines(code, instructions)
  end

  @doc """
  Returns a tuple of `{deletions, insertions}`.
  """
  def compute(left_code, right_code) when is_binary(left_code) and is_binary(right_code) do
    {path, _meta} = shortest_path!(left_code, right_code)

    {left_novels, right_novels} = split_novels(path)

    {deletions, insertions} =
      {to_instructions(left_novels, :del), to_instructions(right_novels, :ins)}

    if debug?() do
      debug_inspect(summarize_path(path), "path")
    end

    {deletions, insertions}
  end

  defp to_instructions(novel_edges, ins_kind) when ins_kind in [:ins, :del] do
    novel_edges
    |> coalesce()
    |> Enum.map(fn
      {kind, node} -> {ins_kind, kind, node.zipper}
      {kind, node, edit_script} -> {ins_kind, kind, node.zipper, edit_script}
    end)
  end

  @doc false
  def summarize_path(path), do: Enum.map(path, &summarize_edge/1)

  defp summarize_edge(%Edge{type: type, kind: :node, side: side, node: node}) do
    {type, side, :node, summarize_node(node)}
  end

  defp summarize_edge(%Edge{type: type, kind: :branch, side: side, node: node}) do
    ast =
      case SyntaxNode.ast(node) do
        {{:., _, _}, _, _} -> {{:., [], "..."}, [], "..."}
        {form, _, _} -> {form, [], "..."}
        {_, _} -> {"...", "..."}
        list when is_list(list) -> ["..."]
      end

    {type, side, :branch, ast}
  end

  defp summarize_edge(nil), do: nil

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

  @doc false
  def shortest_path!(left_code, right_code) do
    shortest_path({SyntaxNode.root!(left_code), SyntaxNode.root!(right_code), nil})
  end

  @doc false
  def shortest_path(root) do
    start = System.monotonic_time()
    [_root | path] = Pathfinding.lazy_dijkstra(root, &vertex_id/1, &neighbors/1)
    finish = System.monotonic_time()

    meta = %{
      time_ms: System.convert_time_unit(finish - start, :native, :millisecond)
    }

    {Enum.map(path, &elem(&1, 2)), meta}
  end

  defp vertex_id({%{id: l_id, parent: nil}, %{id: r_id, parent: nil}, edge}) do
    {l_id, r_id, edge_id(edge)}
  end

  defp vertex_id({%{id: l_id, parent: {entry, _}}, %{id: r_id, parent: nil}, edge}) do
    {l_id, r_id, entry, edge_id(edge)}
  end

  defp vertex_id({%{id: l_id, parent: nil}, %{id: r_id, parent: {entry, _}}, edge}) do
    {l_id, r_id, entry, edge_id(edge)}
  end

  defp vertex_id({%{id: l_id, parent: {e1, _}}, %{id: r_id, parent: {e2, _}}, edge}) do
    {l_id, r_id, e1, e2, edge_id(edge)}
  end

  defp edge_id(nil), do: nil
  defp edge_id({e1, e2}), do: {e1.type, e1.node.id, e2.type, e2.node.id}
  defp edge_id(e), do: {e.type, e.node.id}

  defp split_novels(path) do
    path
    |> Stream.flat_map(fn
      {left, right} -> [left, right]
      %Edge{type: :novel} = edge -> [edge]
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

  defp coalesce(novel_edges) do
    novel_node_ids =
      for %{kind: :node, node: node} <- novel_edges do
        node.id
      end
      |> MapSet.new()

    novel_ids =
      for %{kind: :branch, node: branch} <- Enum.reverse(novel_edges),
          reduce: novel_node_ids do
        ids ->
          if all_child_ids_in?(branch, ids) do
            MapSet.put(ids, branch.id)
          else
            ids
          end
      end

    Enum.flat_map(novel_edges, fn %{kind: kind, node: node, edit_script: edit_script} ->
      branch? = kind == :branch
      parent = SyntaxNode.parent(node)

      cond do
        parent && parent.id in novel_ids ->
          []

        !branch? && edit_script != [] ->
          [{:node, node, edit_script}]

        !branch? ->
          [{:node, node}]

        all_child_ids_in?(node, novel_ids) ->
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
      debug_inspect(summarize_edge(e), "e")
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
       |> add_novel_edges(v)}
    end
  end

  defp add_unchanged_node(neighbors, {left, right, _} = v) do
    edge = Edge.unchanged(:node, left, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))
    add_edge(neighbors, v, {SyntaxNode.next_sibling(left), SyntaxNode.next_sibling(right), edge})
  end

  defp maybe_add_unchanged_branch(
         neighbors,
         {%{branch?: true} = left, %{branch?: true} = right, _} = v
       ) do
    if SyntaxNode.similar_branch?(left, right) do
      edge = Edge.unchanged(:branch, left, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))
      v2 = {SyntaxNode.next_child(left, :pop_both), SyntaxNode.next_child(right, :pop_both), edge}

      add_edge(neighbors, v, v2)
    else
      neighbors
    end
  end

  defp maybe_add_unchanged_branch(neighbors, _v), do: neighbors

  defp add_novel_edges(neighbors, {left, right, _} = v) do
    with {:string, _, s1} <- SyntaxNode.ast(left),
         {:string, _, s2} <- SyntaxNode.ast(right),
         dist when dist > 0.5 <- String.bag_distance(s1, s2) do
      {left_edit, right_edit} = myers_edit_scripts(s1, s2)
      left_edge = Edge.novel(:node, :left, left, left_edit)
      right_edge = Edge.novel(:node, :right, right, right_edit)

      v2 = {
        SyntaxNode.next_sibling(left),
        SyntaxNode.next_sibling(right),
        {left_edge, right_edge}
      }

      add_edge(neighbors, v, v2)
    else
      _ ->
        neighbors
        |> add_novel_left(v)
        |> add_novel_right(v)
    end
  end

  defp add_novel_left(neighbors, {left, %{null?: true} = right, _} = v) do
    neighbors
    |> add_edge(v, {SyntaxNode.next_sibling(left), right, Edge.novel(:node, :left, left)})
  end

  defp add_novel_left(neighbors, {%{branch?: true} = left, right, _} = v) do
    neighbors
    |> add_edge(v, {SyntaxNode.next_sibling(left), right, Edge.novel(:node, :left, left)})
    |> add_edge(v, {SyntaxNode.next_child(left), right, Edge.novel(:branch, :left, left)})
  end

  defp add_novel_left(neighbors, {%{branch?: false} = left, right, _} = v) do
    neighbors
    |> add_edge(v, {SyntaxNode.next_sibling(left), right, Edge.novel(:node, :left, left)})
  end

  defp add_novel_right(neighbors, {%{null?: true} = left, right, _} = v) do
    neighbors
    |> add_edge(v, {left, SyntaxNode.next_sibling(right), Edge.novel(:node, :right, right)})
  end

  defp add_novel_right(neighbors, {left, %{branch?: true} = right, _} = v) do
    neighbors
    |> add_edge(v, {left, SyntaxNode.next_sibling(right), Edge.novel(:node, :right, right)})
    |> add_edge(v, {left, SyntaxNode.next_child(right), Edge.novel(:branch, :right, right)})
  end

  defp add_novel_right(neighbors, {left, %{branch?: false} = right, _} = v) do
    neighbors
    |> add_edge(v, {left, SyntaxNode.next_sibling(right), Edge.novel(:node, :right, right)})
  end

  defp add_edge(neighbors, _v1, {left, right, edge}) do
    {left, right} = SyntaxNode.pop(left, right)
    [{{left, right, edge}, edge_cost(edge)} | neighbors]
  end

  defp edge_cost(%Edge{} = edge), do: Edge.cost(edge)
  defp edge_cost({left, right}), do: Edge.cost(left) + Edge.cost(right)

  defp myers_edit_scripts(s1, s2) do
    String.myers_difference(s1, s2)
    |> Enum.reduce({[], []}, fn
      {:eq, s}, {left, right} -> {[{:eq, s} | left], [{:eq, s} | right]}
      {:del, s}, {left, right} -> {[{:novel, s} | left], right}
      {:ins, s}, {left, right} -> {left, [{:novel, s} | right]}
    end)
    |> then(fn {left, right} -> {Enum.reverse(left), Enum.reverse(right)} end)
  end

  defp debug?, do: !!System.get_env("DEBUG_DIFF")
  defp debug?(value), do: System.get_env("DEBUG_DIFF") == value

  defp debug_inspect(term, label) do
    IO.inspect(term, label: label, pretty: true, syntax_colors: IO.ANSI.syntax_colors())
  end
end
