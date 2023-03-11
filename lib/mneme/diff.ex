# TODO:
# - track depth_difference

defmodule Mneme.Diff do
  @moduledoc false

  alias Mneme.Diff.AST2, as: AST
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
    {edges, _meta} = compute_shortest_path!(left_code, right_code)

    {left_novels, right_novels} = split_novels(edges)

    {
      left_novels |> coalesce() |> Enum.map(fn {type, node} -> {:del, type, node.zipper} end),
      right_novels |> coalesce() |> Enum.map(fn {type, node} -> {:ins, type, node.zipper} end)
    }
  end

  @doc false
  def compute_shortest_path!(left_code, right_code) do
    left = left_code |> AST.parse_string!() |> SyntaxNode.root()
    right = right_code |> AST.parse_string!() |> SyntaxNode.root()
    shortest_path({left, right})
  end

  @doc false
  def shortest_path(root) do
    graph =
      Graph.new(vertex_identifier: fn {left, right} -> {left.id, right.id} end)
      |> Graph.add_vertex(root)

    start = System.monotonic_time()
    {graph, path} = Pathfinding.lazy_dijkstra(graph, root, &add_neighbors/2)
    finish = System.monotonic_time()

    edges = to_edges(path, graph)

    {edges,
     graph: Graph.info(graph),
     time_ms: System.convert_time_unit(finish - start, :native, :millisecond)}
  end

  defp split_novels(edges) do
    {left_acc, right_acc} =
      for %Graph.Edge{label: edge, v1: {left, right}} <- edges,
          reduce: {[], []} do
        {left_acc, right_acc} ->
          case edge do
            %Edge{type: :novel, side: :left, kind: kind} ->
              {[{kind, left} | left_acc], right_acc}

            %Edge{type: :novel, side: :right, kind: kind} ->
              {left_acc, [{kind, right} | right_acc]}

            %Edge{type: :unchanged} ->
              {left_acc, right_acc}
          end
      end

    {Enum.reverse(left_acc), Enum.reverse(right_acc)}
  end

  defp coalesce(all_novels) do
    novel_ids = MapSet.new(for({:node, node} <- all_novels, do: node.id))

    novel_ids =
      for {:branch, branch} <- all_novels,
          reduce: novel_ids do
        ids ->
          if all_child_ids_in?(branch, ids) do
            MapSet.put(ids, branch.id)
          else
            ids
          end
      end

    Enum.flat_map(all_novels, fn {type, node} ->
      cond do
        SyntaxNode.parent(node).id in novel_ids ->
          []

        type == :node ->
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

  defp to_edges([v1, v2 | rest], graph) do
    # TODO: I _think_ there should always only be a single edge here,
    # but in one case that caused a match error. Need to look into this
    # more carefully.
    [edge | _] = Graph.edges(graph, v1, v2)
    [edge | to_edges([v2 | rest], graph)]
  end

  defp to_edges([_last], _graph), do: []

  defp add_neighbors(graph, {left, right} = v) do
    case {SyntaxNode.terminal?(left), SyntaxNode.terminal?(right)} do
      {true, true} ->
        :halt

      {false, true} ->
        {:cont, graph |> add_novel_left(v)}

      {true, false} ->
        {:cont, graph |> add_novel_right(v)}

      {false, false} ->
        {:cont,
         graph
         |> maybe_add_unchanged_node(v)
         |> maybe_add_unchanged_branch(v)
         |> add_novel_left(v)
         |> add_novel_right(v)}
    end
  end

  defp add_neighbor_edge(graph, existing, new, %Edge{} = edge) do
    Graph.add_edge(graph, existing, new, label: edge, weight: Edge.cost(edge))
  end

  defp maybe_add_unchanged_node(graph, {left, right} = v) do
    if SyntaxNode.similar?(left, right) do
      add_neighbor_edge(
        graph,
        v,
        {SyntaxNode.skip(left), SyntaxNode.skip(right)},
        Edge.unchanged(false, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))
      )
    else
      graph
    end
  end

  defp maybe_add_unchanged_branch(graph, {left, right} = v) do
    unchanged_branch? =
      case {SyntaxNode.ast(left), SyntaxNode.ast(right)} do
        {{{:., _, _}, _, _}, {{:., _, _}, _, _}} -> true
        {{branch, _, _}, {branch, _, _}} -> true
        _ -> false
      end

    if unchanged_branch? do
      add_neighbor_edge(
        graph,
        v,
        {SyntaxNode.next(left), SyntaxNode.next(right)},
        Edge.unchanged(true)
      )
    else
      graph
    end
  end

  defp add_novel_left(graph, {left, right}) do
    add_neighbor_edge(
      graph,
      {left, right},
      {SyntaxNode.next(left), right},
      Edge.novel(left.branch?, :left)
    )
  end

  defp add_novel_right(graph, {left, right}) do
    add_neighbor_edge(
      graph,
      {left, right},
      {left, SyntaxNode.next(right)},
      Edge.novel(right.branch?, :right)
    )
  end
end
