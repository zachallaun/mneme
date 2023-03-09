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
      left_novels |> coalesce() |> Enum.map(&instruction(:del, &1)),
      right_novels |> coalesce() |> Enum.map(&instruction(:ins, &1))
    }
  end

  @doc false
  def compute_shortest_path!(left_code, right_code) do
    left = parse_to_zipper!(left_code)
    right = parse_to_zipper!(right_code)
    shortest_path(left, right)
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
      for {:node, zipper} <- all_novels do
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

          type == :node ->
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

  defp maybe_put_novel({{_, _, _} = call, _, args} = node, ids) when is_list(args) do
    node
    |> get_id()
    |> maybe_put_novel(ids, [call | args])
  end

  defp maybe_put_novel({_, _, args} = node, ids) when is_list(args) do
    node
    |> get_id()
    |> maybe_put_novel(ids, args)
  end

  defp maybe_put_novel(_, ids), do: ids

  defp maybe_put_novel(id, ids, args) do
    {all_novel?, ids} =
      Enum.reduce(args, {true, ids}, fn node, {all_novel?, ids} ->
        ids = maybe_put_novel(node, ids)
        {all_novel? && get_id(node) in ids, ids}
      end)

    if all_novel? do
      MapSet.put(ids, id)
    else
      ids
    end
  end

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
    # TODO: I _think_ there should always only be a single edge here,
    # but in one case that caused a match error. Need to look into this
    # more carefully.
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
    inner = Enum.map(args, &hash/1)
    :erlang.phash2({hash(call), inner})
  end

  defp hash({type, meta, value}) do
    if hash = meta[:__hash__] do
      hash
    else
      :erlang.phash2({type, value})
    end
  end

  defp hash(atom) when is_atom(atom) do
    :erlang.phash2(atom)
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
    graph
    |> neighbor_maybe_unchanged_subtree(v)
    |> neighbor_maybe_unchanged_branch_edge(v)
    |> neighbor_left_edges(v)
    |> neighbor_right_edges(v)
  end

  defp neighbor_maybe_unchanged_subtree(
         graph,
         %Vertex{left: l, right: r, left_branch?: branch?, right_branch?: branch?} = v
       ) do
    if syntax_eq?(l, r) do
      add_neighbor_edge(
        graph,
        v,
        Vertex.new(Zipper.skip(l), Zipper.skip(r)),
        Edge.unchanged(false, abs(get_depth(l) - get_depth(r)))
      )
    else
      graph
    end
  end

  defp neighbor_maybe_unchanged_subtree(graph, _vertex), do: graph

  defp neighbor_maybe_unchanged_branch_edge(
         graph,
         %Vertex{left: l, right: r, left_branch?: true, right_branch?: true} = v
       ) do
    unchanged_branch? =
      case {Zipper.node(l), Zipper.node(r)} do
        {{{:., _, _}, _, _}, {{:., _, _}, _, _}} -> true
        {{{:var, _, var}, _, _}, {{:var, _, var}, _, _}} -> true
        {{branch, _, _}, {branch, _, _}} -> true
        _ -> false
      end

    if unchanged_branch? do
      add_neighbor_edge(
        graph,
        v,
        Vertex.new(Zipper.next(l), Zipper.next(r)),
        Edge.unchanged(true)
      )
    else
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

  defp get_depth(zipper, acc \\ 0)
  defp get_depth(nil, acc), do: acc
  defp get_depth(zipper, acc), do: get_depth(Zipper.up(zipper), acc + 1)
end
