# TODO:
# - track depth_difference

defmodule Mneme.Diff do
  @moduledoc false

  alias Mneme.Diff.AST
  alias Mneme.Diff.Pathfinding
  alias Mneme.Diff.Zipper

  defmodule Edge do
    defstruct [:type, :kind, :side, :depth_difference]

    @type t :: %Edge{
            type: :novel | :unchanged,
            kind: :branch | :leaf,
            side: :left | :right,
            depth_difference: non_neg_integer()
          }

    @doc "Construct an edge representing a novel node."
    def novel(kind, side, depth_difference \\ 0) do
      %Edge{type: :novel, kind: kind, side: side, depth_difference: depth_difference}
    end

    @doc "Construct an edge representing an unchanged node."
    def unchanged(kind, depth_difference \\ 0) do
      %Edge{type: :unchanged, kind: kind, depth_difference: depth_difference}
    end

    @doc "The cost of taking this edge."
    def cost(edge)

    def cost(%Edge{type: :unchanged, kind: :leaf, depth_difference: dd}), do: min(40, dd + 1)

    def cost(%Edge{type: :unchanged, kind: :branch, depth_difference: dd}) do
      100 + min(40, dd + 1)
    end

    def cost(%Edge{type: :novel}), do: 300
  end

  defmodule Vertex do
    defstruct [:id, :left, :right]

    @type t :: %Vertex{
            id: integer(),
            left: {:branch | :leaf, Zipper.t()},
            right: {:branch | :leaf, Zipper.t()}
          }

    @doc false
    def new(left, right) do
      left = wrap(left)
      right = wrap(right)

      %Vertex{id: id(left, right), left: left, right: right}
    end

    defp id(left, right), do: :erlang.phash2({id(left), id(right)})
    defp id(nil), do: :erlang.phash2(nil)

    defp id({_, zipper}) do
      zipper
      |> Zipper.node()
      |> elem(1)
      |> Keyword.fetch!(:__id__)
    end

    defp wrap(nil), do: nil
    defp wrap({:branch, _} = wrapped), do: wrapped
    defp wrap({:leaf, _} = wrapped), do: wrapped

    defp wrap(zipper) do
      if zipper |> Zipper.node() |> Zipper.branch?() do
        {:branch, zipper}
      else
        {:leaf, zipper}
      end
    end
  end

  @doc """
  Returns the set of instructions to convert `left_code` to `right_code`.
  """
  def compute(left_code, right_code) when is_binary(left_code) and is_binary(right_code) do
    left = parse_to_zipper!(left_code)
    right = parse_to_zipper!(right_code)

    {edges, _meta} = shortest_path(left, right)

    diff_instructions(edges)
  end

  defp diff_instructions(edges) do
    {left_acc, right_acc} =
      for %Graph.Edge{label: edge, v1: vertex} <- edges,
          %Vertex{left: left, right: right} = vertex,
          reduce: {[], []} do
        {left_acc, right_acc} ->
          case edge do
            %Edge{type: :novel, side: :left, kind: kind} ->
              {[instruction(:del, kind, left |> elem(1) |> Zipper.node()) | left_acc], right_acc}

            %Edge{type: :novel, side: :right, kind: kind} ->
              {left_acc, [instruction(:ins, kind, right |> elem(1) |> Zipper.node()) | right_acc]}

            %Edge{type: :unchanged} ->
              {left_acc, right_acc}
          end
      end

    [left: Enum.reverse(left_acc), right: Enum.reverse(right_acc)]
  end

  defp instruction(op, :leaf, {_, meta, value}) do
    {op, value, Keyword.take(meta, [:line, :column])}
  end

  defp instruction(op, :branch, {call, meta, _}) do
    {op, call, Keyword.take(meta, [:line, :column, :closing])}
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
    [edge] = Graph.edges(graph, v1, v2)
    [edge | to_edges([v2 | rest], graph)]
  end

  defp to_edges([_last], _graph), do: []

  defp parse_to_zipper!(code) when is_binary(code) do
    code
    |> AST.parse!()
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

  defp neighbor_maybe_unchanged_subtree(graph, %Vertex{left: {kind, l}, right: {kind, r}} = v) do
    if syntax_eq?(l, r) do
      {:ok,
       add_neighbor_edge(
         graph,
         v,
         Vertex.new(Zipper.skip(l), Zipper.skip(r)),
         Edge.unchanged(kind)
       )}
    else
      :error
    end
  end

  defp neighbor_maybe_unchanged_subtree(_graph, _vertex), do: :error

  defp neighbor_maybe_unchanged_branch_edge(
         graph,
         %Vertex{left: {:branch, l}, right: {:branch, r}} = v
       ) do
    case {Zipper.node(l), Zipper.node(r)} do
      {{branch, _, _}, {branch, _, _}} ->
        add_neighbor_edge(
          graph,
          v,
          Vertex.new(Zipper.next(l), Zipper.next(r)),
          Edge.unchanged(:branch)
        )

      _ ->
        graph
    end
  end

  defp neighbor_maybe_unchanged_branch_edge(graph, _), do: graph

  defp neighbor_left_edges(graph, %Vertex{left: {:leaf, l}} = v) do
    add_neighbor_edge(graph, v, Vertex.new(Zipper.next(l), v.right), Edge.novel(:leaf, :left))
  end

  defp neighbor_left_edges(graph, %Vertex{left: {:branch, l}} = v) do
    add_neighbor_edge(graph, v, Vertex.new(Zipper.next(l), v.right), Edge.novel(:branch, :left))
  end

  defp neighbor_right_edges(graph, %Vertex{right: {:leaf, r}} = v) do
    add_neighbor_edge(graph, v, Vertex.new(v.left, Zipper.next(r)), Edge.novel(:leaf, :right))
  end

  defp neighbor_right_edges(graph, %Vertex{right: {:branch, r}} = v) do
    add_neighbor_edge(graph, v, Vertex.new(v.left, Zipper.next(r)), Edge.novel(:branch, :right))
  end
end
