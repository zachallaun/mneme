# TODO:
# - track depth_difference

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
    {graph, path} = Pathfinding.lazy_dijkstra(graph, root, &add_neighbors/2)
    finish = System.monotonic_time()

    {path,
     graph: Graph.info(graph),
     time_ms: System.convert_time_unit(finish - start, :native, :millisecond)}
  end

  defp split_novels(path, left_acc \\ [], right_acc \\ [])

  defp split_novels([{left, right, _}, {_, _, edge} = v | rest], left_acc, right_acc) do
    case edge do
      %Edge{type: :novel, side: :left} ->
        split_novels([v | rest], [left | left_acc], right_acc)

      %Edge{type: :novel, side: :right} ->
        split_novels([v | rest], left_acc, [right | right_acc])

      %Edge{type: :unchanged} ->
        split_novels([v | rest], left_acc, right_acc)
    end
  end

  defp split_novels(_path, left_acc, right_acc) do
    {Enum.reverse(left_acc), Enum.reverse(right_acc)}
  end

  defp coalesce(all_novels) do
    novel_ids = MapSet.new(for(%SyntaxNode{branch?: false, id: id} <- all_novels, do: id))

    novel_ids =
      for %SyntaxNode{branch?: true, id: id} = branch <- Enum.reverse(all_novels),
          reduce: novel_ids do
        ids ->
          if all_child_ids_in?(branch, ids) do
            MapSet.put(ids, id)
          else
            ids
          end
      end

    Enum.flat_map(all_novels, fn %SyntaxNode{branch?: branch?} = node ->
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

  defp add_neighbors(graph, {left, right, _} = v) do
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

  defp add_edge(graph, existing, new, %Edge{} = edge) do
    Graph.add_edge(graph, existing, new, weight: Edge.cost(edge))
  end

  defp maybe_add_unchanged_node(graph, {left, right, _} = v) do
    if SyntaxNode.similar?(left, right) do
      edge = Edge.unchanged(false, abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)))
      add_edge(graph, v, {SyntaxNode.skip(left), SyntaxNode.skip(right), edge}, edge)
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
      edge = Edge.unchanged(true)
      add_edge(graph, v, {SyntaxNode.next(left), SyntaxNode.next(right), edge}, edge)
    else
      graph
    end
  end

  defp maybe_add_unchanged_branch(graph, _v), do: graph

  defp add_novel_left(graph, {left, right, _} = v) do
    edge = Edge.novel(left.branch?, :left)
    add_edge(graph, v, {SyntaxNode.next(left), right, edge}, edge)
  end

  defp add_novel_right(graph, {left, right, _} = v) do
    edge = Edge.novel(right.branch?, :right)
    add_edge(graph, v, {left, SyntaxNode.next(right), edge}, edge)
  end
end
