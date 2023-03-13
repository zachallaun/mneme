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
    {path, _meta} = compute_shortest_path!(left_code, right_code)

    {left_novels, right_novels} = split_novels(path)

    {
      left_novels |> coalesce() |> Enum.map(fn {type, node} -> {:del, type, node.zipper} end),
      right_novels |> coalesce() |> Enum.map(fn {type, node} -> {:ins, type, node.zipper} end)
    }
  end

  @doc false
  def summarize_path(path) do
    for %Edge{type: type, kind: kind, side: side, node: node} <- path do
      ast =
        node
        |> SyntaxNode.ast()
        |> AST.prewalk(fn
          {form, _meta, args} -> {form, [], args}
          quoted -> quoted
        end)

      {type, side, kind, ast}
    end
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
      Graph.new(vertex_identifier: fn {left, right, in_edge} -> {left.id, right.id, in_edge} end)
      |> Graph.add_vertex(root)

    start = System.monotonic_time()
    {graph, [_root | path]} = Pathfinding.lazy_dijkstra(graph, root, &add_neighbors/2)
    finish = System.monotonic_time()

    {Enum.map(path, &elem(&1, 2)),
     graph: Graph.info(graph),
     time_ms: System.convert_time_unit(finish - start, :native, :millisecond)}
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

  defp add_neighbors(_graph, {%{terminal?: true}, %{terminal?: true}, _}), do: :halt

  defp add_neighbors(graph, {%{null?: false}, %{null?: true}, _} = v) do
    {:cont, graph |> add_novel_left(v)}
  end

  defp add_neighbors(graph, {%{null?: true}, %{null?: false}, _} = v) do
    {:cont, graph |> add_novel_right(v)}
  end

  defp add_neighbors(graph, v) do
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
    unchanged_branch? =
      case {SyntaxNode.ast(left), SyntaxNode.ast(right)} do
        {{{:., _, _}, _, _}, {{:., _, _}, _, _}} -> true
        {{branch, _, _}, {branch, _, _}} -> true
        _ -> false
      end

    if unchanged_branch? do
      edge = Edge.unchanged(:branch, left, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))
      add_edge(graph, v, {SyntaxNode.next_child(left), SyntaxNode.next_child(right), edge})
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
    {left, right} =
      if left.null? && right.null? do
        {SyntaxNode.skip(left), SyntaxNode.skip(right)}
      else
        {left, right}
      end

    Graph.add_edge(graph, v1, {left, right, edge}, weight: Edge.cost(edge))
  end
end
