# Derived from bitwalker/libgraph:
# https://github.com/bitwalker/libgraph/blob/main/lib/graph/pathfinding.ex

defmodule Mneme.Diff.Pathfinding do
  @moduledoc false

  import Graph.Utils, only: [edge_weight: 3]

  @type heuristic_fun :: (Graph.vertex() -> integer)
  @type next_fun :: (Graph.t(), Graph.vertex() -> {:cont, Graph.t()} | :halt)

  @doc """
  Finds the shortest path between `a` and a target vertex, lazily computing
  the graph using `next_fun`.

  The given `next_fun` receives the graph and the current vertex under
  consideration, and must return either `{:cont, graph}` to continue
  searching, or `:halt` to indicate that the target vertex has been found.
  """
  @spec lazy_dijkstra(Graph.t(), Graph.vertex(), next_fun) :: {Graph.t(), [Graph.vertex()]} | nil
  def lazy_dijkstra(%Graph{} = g, a, next_fun) do
    lazy_a_star(g, a, next_fun, fn _v -> 0 end)
  end

  @doc false
  @spec lazy_a_star(Graph.t(), Graph.vertex(), next_fun, heuristic_fun) ::
          {Graph.t(), [Graph.vertex()]} | nil
  def lazy_a_star(%Graph{type: :directed} = g, v, next_fun, hfun)
      when is_function(hfun, 1) do
    v_id = g.vertex_identifier.(v)
    tree = Graph.new(vertex_identifier: &Function.identity/1) |> Graph.add_vertex(v_id)
    q = PriorityQueue.new()

    with {:cont, %Graph{out_edges: oe} = g} <- next_fun.(g, v),
         {:ok, v_out} <- Map.fetch(oe, v_id) do
      q
      |> push_vertices(g, v_id, v_out, hfun)
      |> do_lazy_bfs(g, tree, next_fun, hfun)
      |> case do
        {:ok, %Graph{vertices: vs} = g, path} -> {g, for(id <- path, do: Map.get(vs, id))}
        :error -> nil
      end
    else
      :halt -> {g, [v]}
      :error -> nil
    end
  end

  ## Private

  defp do_lazy_bfs(q, %Graph{type: :directed} = g, tree, next_fun, hfun) do
    case PriorityQueue.pop(q) do
      {{:value, {v1_id, v2_id, acc_cost}}, q} ->
        v2 = Map.fetch!(g.vertices, v2_id)

        case next_fun.(g, v2) do
          :halt ->
            {:ok, g, construct_path(v1_id, tree, [v2_id])}

          {:cont, %Graph{out_edges: oe} = g} ->
            cond do
              Map.has_key?(tree.vertices, v2_id) ->
                do_lazy_bfs(q, g, tree, next_fun, hfun)

              v2_out = Map.get(oe, v2_id) ->
                tree =
                  tree
                  |> Graph.add_vertex(v2_id)
                  |> Graph.add_edge(v2_id, v1_id)

                q
                |> push_vertices(g, v2_id, v2_out, hfun, acc_cost)
                |> do_lazy_bfs(g, tree, next_fun, hfun)

              true ->
                do_lazy_bfs(q, g, tree, next_fun, hfun)
            end
        end

      {:empty, _} ->
        :error
    end
  end

  defp push_vertices(q, g, v_id, ids, hfun, acc_cost \\ 0) do
    Enum.reduce(ids, q, fn v2_id, q ->
      q_cost = acc_cost + cost(g, v_id, v2_id, hfun)
      edge_cost = acc_cost + edge_weight(g, v_id, v2_id)

      PriorityQueue.push(q, {v_id, v2_id, edge_cost}, q_cost)
    end)
  end

  defp cost(%Graph{vertices: vs} = g, v1_id, v2_id, hfun) do
    edge_weight(g, v1_id, v2_id) + hfun.(Map.get(vs, v2_id))
  end

  defp construct_path(v_id, %Graph{out_edges: oe} = tree, path) do
    path = [v_id | path]

    case oe |> Map.get(v_id, MapSet.new()) |> MapSet.to_list() do
      [] -> path
      [next_id] -> construct_path(next_id, tree, path)
    end
  end
end
