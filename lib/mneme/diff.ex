defmodule Mneme.Diff do
  @moduledoc false

  alias Mneme.Diff.AST
  alias Mneme.Diff.Edge
  alias Mneme.Diff.Formatter
  alias Mneme.Diff.Pathfinding
  alias Mneme.Diff.SyntaxNode

  @doc """
  Formats `left` and `right` as `t:Owl.Data.t()`.
  """
  def format(left, right) do
    case compute(left, right) do
      {[], []} -> {nil, nil}
      {[], ins} -> {nil, format_lines(right, ins)}
      {del, []} -> {format_lines(left, del), nil}
      {del, ins} -> {format_lines(left, del), format_lines(right, ins)}
    end
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
    {path, meta} = compute_shortest_path!(left_code, right_code)

    {left_novels, right_novels} = split_novels(path)

    if debug?(), do: dbg()
    # debug_inspect(summarize_path(path), "path")

    {
      left_novels |> coalesce() |> Enum.map(fn {type, node} -> {:del, type, node.zipper} end),
      right_novels |> coalesce() |> Enum.map(fn {type, node} -> {:ins, type, node.zipper} end)
    }
  end

  @doc false
  def summarize_path(path), do: Enum.map(path, &summarize_edge/1)

  defp summarize_edge(%Edge{type: type, kind: :node, side: side, node: node}) do
    {type, side, :node, summarize_node(node)}
  end

  defp summarize_edge(%Edge{type: type, kind: :branch, side: side, node: node}) do
    ast =
      case SyntaxNode.ast(node) do
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
  def compute_shortest_path!(left_code, right_code) do
    left = left_code |> AST.parse_string!() |> SyntaxNode.root()
    right = right_code |> AST.parse_string!() |> SyntaxNode.root()
    shortest_path({left, right, nil})
  end

  @doc false
  def shortest_path(root) do
    graph =
      Graph.new(vertex_identifier: &vertex_id/1)
      |> Graph.add_vertex(root)

    start = System.monotonic_time()
    {graph, [_root | path]} = Pathfinding.lazy_a_star(graph, root, &add_neighbors/2, &heuristic/1)
    finish = System.monotonic_time()

    {Enum.map(path, &elem(&1, 2)),
     %{
       graph: graph,
       info: Graph.info(graph),
       time_ms: System.convert_time_unit(finish - start, :native, :millisecond)
     }}
  end

  defp heuristic(_), do: 0
  # defp heuristic({left, right, _}) do
  #   400 * (SyntaxNode.n_left(left) + SyntaxNode.n_left(right))
  # end

  defp vertex_id({%{id: l_id, parent: nil}, %{id: r_id, parent: nil}, edge}) do
    {l_id, r_id, edge && {edge.type, edge.node.id}}
  end

  defp vertex_id({%{id: l_id, parent: {entry, _}}, %{id: r_id, parent: nil}, edge}) do
    {l_id, r_id, entry, edge && {edge.type, edge.node.id}}
  end

  defp vertex_id({%{id: l_id, parent: nil}, %{id: r_id, parent: {entry, _}}, edge}) do
    {l_id, r_id, entry, edge && {edge.type, edge.node.id}}
  end

  defp vertex_id({%{id: l_id, parent: {e1, _}}, %{id: r_id, parent: {e2, _}}, edge}) do
    {l_id, r_id, e1, e2, edge && {edge.type, edge.node.id}}
  end

  defp split_novels(path) do
    path
    |> Stream.filter(&(&1.type == :novel))
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

    Enum.flat_map(novel_edges, fn %{kind: kind, node: node} ->
      branch? = kind == :branch
      parent = SyntaxNode.parent(node)

      cond do
        parent && parent.id in novel_ids ->
          []

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

  defp add_neighbors(graph, {l, r, e} = v) do
    if debug?() do
      debug_inspect(summarize_edge(e), "e")
      debug_inspect(summarize_node(l), "l")
      debug_inspect(summarize_node(r), "r")
      IO.puts("")
    end

    do_add_neighbors(graph, v)
  end

  defp do_add_neighbors(_graph, {%{terminal?: true}, %{terminal?: true}, _}), do: :halt

  defp do_add_neighbors(graph, {_, %{null?: true}, _} = v) do
    {:cont, graph |> add_novel_left(v)}
  end

  defp do_add_neighbors(graph, {%{null?: true}, _, _} = v) do
    {:cont, graph |> add_novel_right(v)}
  end

  defp do_add_neighbors(graph, v) do
    {:cont,
     graph
     |> maybe_add_unchanged_node(v)
     |> maybe_add_unchanged_branch(v)
     |> add_novel_left(v)
     |> add_novel_right(v)}
  end

  defp maybe_add_unchanged_node(graph, {left, right, _} = v) do
    if SyntaxNode.similar?(left, right) do
      edge = Edge.unchanged(:node, left, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))
      add_edge(graph, v, {SyntaxNode.next_sibling(left), SyntaxNode.next_sibling(right), edge})
    else
      graph
    end
  end

  defp maybe_add_unchanged_branch(
         graph,
         {%{branch?: true} = left, %{branch?: true} = right, _} = v
       ) do
    if SyntaxNode.similar_branch?(left, right) do
      edge = Edge.unchanged(:branch, left, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))
      v2 = {SyntaxNode.next_child(left, :pop_both), SyntaxNode.next_child(right, :pop_both), edge}

      add_edge(graph, v, v2)
    else
      graph
    end
  end

  defp maybe_add_unchanged_branch(graph, _v), do: graph

  defp add_novel_left(graph, {%{branch?: true} = left, right, _} = v) do
    graph
    |> add_edge(v, {SyntaxNode.next_sibling(left), right, Edge.novel(:node, :left, left)})
    |> add_edge(v, {SyntaxNode.next_child(left), right, Edge.novel(:branch, :left, left)})
  end

  defp add_novel_left(graph, {%{branch?: false} = left, right, _} = v) do
    graph
    |> add_edge(v, {SyntaxNode.next_sibling(left), right, Edge.novel(:node, :left, left)})
  end

  defp add_novel_right(graph, {left, %{branch?: true} = right, _} = v) do
    graph
    |> add_edge(v, {left, SyntaxNode.next_sibling(right), Edge.novel(:node, :right, right)})
    |> add_edge(v, {left, SyntaxNode.next_child(right), Edge.novel(:branch, :right, right)})
  end

  defp add_novel_right(graph, {left, %{branch?: false} = right, _} = v) do
    graph
    |> add_edge(v, {left, SyntaxNode.next_sibling(right), Edge.novel(:node, :right, right)})
  end

  defp add_edge(graph, v1, {left, right, edge}) do
    {left, right} = SyntaxNode.pop(left, right)
    Graph.add_edge(graph, v1, {left, right, edge}, weight: Edge.cost(edge))
  end

  defp debug?, do: !!System.get_env("DBG_PATH")

  defp debug_inspect(term, label) do
    IO.inspect(term, label: label, pretty: true, syntax_colors: IO.ANSI.syntax_colors())
  end
end
