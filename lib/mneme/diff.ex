# TODO:
# - track depth_difference

defmodule Mneme.Diff do
  @moduledoc false

  alias Mneme.Diff.AST
  alias Mneme.Diff.Edge
  alias Mneme.Diff.Formatter
  alias Mneme.Diff.Pathfinding
  alias Mneme.Diff.Vertex
  alias Mneme.Diff.Zipper

  @doc """
  Formats `code` as `t:Owl.Data.t()` using the given instructions.
  """
  def format(code, instructions) when is_binary(code) do
    Formatter.highlight_lines(code, instructions)
  end

  @doc """
  Returns a tuple of `{deletions, insertions}`.
  """
  def compute(left_code, right_code) when is_binary(left_code) and is_binary(right_code) do
    left = parse_to_zipper!(left_code)
    right = parse_to_zipper!(right_code)

    {edges, _meta} = shortest_path(left, right)

    {left_novels, right_novels} = split_novels(edges)

    {
      left_novels |> coalesce() |> Enum.map(&instruction(:del, &1)),
      right_novels |> coalesce() |> Enum.map(&instruction(:ins, &1))
    }
  end

  defp split_novels(edges) do
    {left_acc, right_acc} =
      for %Graph.Edge{label: edge, v1: vertex} <- edges,
          %Vertex{left: left, right: right} = vertex,
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

  defp instruction(op, {node_or_delimiter, zipper}) do
    {op, node_or_delimiter, zipper}
  end

  defp coalesce(all_novels) do
    novel_node_ids =
      for {:leaf, zipper} <- all_novels do
        get_id(zipper)
      end
      |> MapSet.new()

    novel_node_ids =
      for {:branch, zipper} <- all_novels, reduce: novel_node_ids do
        ids -> maybe_put_novel(Zipper.node(zipper), ids)
      end

    Enum.flat_map(all_novels, fn
      {type, zipper} ->
        cond do
          get_parent_id(zipper) in novel_node_ids ->
            []

          type == :leaf ->
            [{:node, zipper}]

          all_descendant_ids_in(zipper, novel_node_ids) ->
            [{:node, zipper}]

          true ->
            [{:delimiter, zipper}]
        end
    end)
  end

  defp all_descendant_ids_in(zipper, ids) do
    zipper
    |> Zipper.node()
    |> descendant_ids()
    |> Enum.all?(&(&1 in ids))
  end

  defp descendant_ids({_, _, args}) do
    for {_, meta, _} <- args do
      Keyword.fetch!(meta, :__id__)
    end
  end

  defp get_id({_, _} = zipper) do
    zipper
    |> Zipper.node()
    |> get_id()
  end

  defp get_id({_, meta, _}) do
    Keyword.fetch!(meta, :__id__)
  end

  defp get_id(_), do: nil

  defp get_parent_id(zipper) do
    zipper
    |> Zipper.up()
    |> get_id()
  end

  defp maybe_put_novel({_, _, args} = node, ids) when is_list(args) do
    {all_novel?, ids} =
      Enum.reduce(args, {true, ids}, fn node, {all_novel?, ids} ->
        ids = maybe_put_novel(node, ids)
        {all_novel? && get_id(node) in ids, ids}
      end)

    if all_novel? do
      MapSet.put(ids, get_id(node))
    else
      ids
    end
  end

  defp maybe_put_novel(_, ids), do: ids

  @doc false
  def shortest_path(left, right) do
    root = Vertex.new(left, right)

    graph =
      Graph.new(vertex_identifier: fn %Vertex{id: id} -> id end)
      |> Graph.add_vertex(root)

    start = System.monotonic_time()
    {graph, path} = Pathfinding.lazy_dijkstra(graph, root, &add_neighbors/2)
    finish = System.monotonic_time()

    edges = to_edges(path, graph)

    {edges,
     graph: Graph.info(graph),
     time_ms: System.convert_time_unit(finish - start, :native, :millisecond)}
  end

  defp to_edges([v1, v2 | rest], graph) do
    [edge] = Graph.edges(graph, v1, v2)
    [edge | to_edges([v2 | rest], graph)]
  end

  defp to_edges([_last], _graph), do: []

  defp parse_to_zipper!(code) when is_binary(code) do
    code
    |> AST.parse_string!()
    |> AST.postwalk(0, fn quoted, i ->
      hash = hash(quoted)

      quoted =
        Macro.update_meta(
          quoted,
          &Keyword.merge(&1, __hash__: hash, __id__: :erlang.phash2({hash, i}))
        )

      {quoted, i + 1}
    end)
    |> elem(0)
    |> Zipper.zip()
  end

  defp hash({call, _, args}) when is_list(args) do
    inner =
      Enum.map(args, fn
        {a, b} -> {hash(a), hash(b)}
        arg -> hash(arg)
      end)

    :erlang.phash2({call, inner})
  end

  defp hash({type, _, value}) do
    :erlang.phash2({type, value})
  end

  defp fetch_hash!(nil), do: 0
  defp fetch_hash!(zipper), do: zipper |> Zipper.node() |> elem(1) |> Keyword.fetch!(:__hash__)

  defp syntax_eq?(left, right) do
    left_h = left |> fetch_hash!()
    left_parent_h = left |> Zipper.up() |> fetch_hash!()
    right_h = right |> fetch_hash!()
    right_parent_h = right |> Zipper.up() |> fetch_hash!()

    left_h == right_h && left_parent_h && right_parent_h
  end

  defp add_neighbors(_graph, %Vertex{left: nil, right: nil}), do: :halt

  defp add_neighbors(graph, %Vertex{} = v) do
    result = do_add_neighbors(graph, v)
    {:cont, result}
  end

  defp add_neighbor_edge(graph, existing, new, %Edge{} = edge) do
    Graph.add_edge(graph, existing, new, label: edge, weight: Edge.cost(edge))
  end

  defp do_add_neighbors(graph, %Vertex{right: nil} = v) do
    graph |> neighbor_left_edges(v)
  end

  defp do_add_neighbors(graph, %Vertex{left: nil} = v) do
    graph |> neighbor_right_edges(v)
  end

  defp do_add_neighbors(graph, %Vertex{} = v) do
    case neighbor_maybe_unchanged_subtree(graph, v) do
      {:ok, graph} ->
        graph

      :error ->
        graph
        |> neighbor_maybe_unchanged_branch_edge(v)
        |> neighbor_left_edges(v)
        |> neighbor_right_edges(v)
    end
  end

  defp neighbor_maybe_unchanged_subtree(
         graph,
         %Vertex{left: l, right: r, left_branch?: branch?, right_branch?: branch?} = v
       ) do
    if syntax_eq?(l, r) do
      {:ok,
       add_neighbor_edge(
         graph,
         v,
         Vertex.new(Zipper.skip(l), Zipper.skip(r)),
         Edge.unchanged(branch?)
       )}
    else
      :error
    end
  end

  defp neighbor_maybe_unchanged_subtree(_graph, _vertex), do: :error

  defp neighbor_maybe_unchanged_branch_edge(
         graph,
         %Vertex{left: l, right: r, left_branch?: true, right_branch?: true} = v
       ) do
    case {Zipper.node(l), Zipper.node(r)} do
      {{branch, _, _}, {branch, _, _}} ->
        add_neighbor_edge(
          graph,
          v,
          Vertex.new(Zipper.next(l), Zipper.next(r)),
          Edge.unchanged(true)
        )

      _ ->
        graph
    end
  end

  defp neighbor_maybe_unchanged_branch_edge(graph, _), do: graph

  defp neighbor_left_edges(graph, %Vertex{left: l, left_branch?: branch?} = v) do
    add_neighbor_edge(graph, v, Vertex.new(Zipper.next(l), v.right), Edge.novel(branch?, :left))
  end

  defp neighbor_right_edges(graph, %Vertex{right: r, right_branch?: branch?} = v) do
    add_neighbor_edge(graph, v, Vertex.new(v.left, Zipper.next(r)), Edge.novel(branch?, :right))
  end
end
