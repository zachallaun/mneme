# Derived from bitwalker/libgraph:
# https://github.com/bitwalker/libgraph/blob/main/lib/graph/pathfinding.ex

defmodule Mneme.Diff.Pathfinding do
  @moduledoc false

  alias Mneme.Diff.PriorityQueue, as: PQueue

  @doc """
  Finds the shortest path between `v` and a target vertex.

  The given `next_fun` receives the vertex under consideration and must
  return `{:cont, neighbors}` to continue searching or `:halt` to
  indicate that the target has been found.
  """
  def lazy_dijkstra(v, vertex_identifier, next_fun) do
    lazy_a_star(v, vertex_identifier, next_fun, fn _v -> 0 end)
  end

  @doc false
  def lazy_a_star(v, vertex_identifier, next_fun, hfun) do
    v_id = vertex_identifier.(v)
    known = %{v_id => v}
    tree = Graph.new(vertex_identifier: &Function.identity/1) |> Graph.add_vertex(v_id)
    q = PQueue.new()

    with {:cont, vs_out} <- next_fun.(v) do
      {vs_out, known} = push_known(known, vs_out, vertex_identifier)

      q
      |> push_vertices(known, v_id, vs_out, hfun)
      |> do_lazy_bfs(known, tree, vertex_identifier, next_fun, hfun)
      |> case do
        {:ok, known, path} -> for(id <- path, do: Map.get(known, id))
        :error -> nil
      end
    else
      :halt -> [v]
      :error -> nil
    end
  end

  ## Private

  defp do_lazy_bfs(q, known, tree, vertex_identifier, next_fun, hfun) do
    case PQueue.pop(q) do
      {:ok, {v1_id, v2_id, acc_cost}, q} ->
        v2 = Map.fetch!(known, v2_id)

        case next_fun.(v2) do
          :halt ->
            {:ok, known, construct_path(v1_id, tree, [v2_id])}

          {:cont, vs_out} ->
            if Map.has_key?(tree.vertices, v2_id) do
              do_lazy_bfs(q, known, tree, vertex_identifier, next_fun, hfun)
            else
              {v2_out, known} = push_known(known, vs_out, vertex_identifier)

              tree =
                tree
                |> Graph.add_vertex(v2_id)
                |> Graph.add_edge(v2_id, v1_id)

              q
              |> push_vertices(known, v2_id, v2_out, hfun, acc_cost)
              |> do_lazy_bfs(known, tree, vertex_identifier, next_fun, hfun)
            end
        end

      :error ->
        :error
    end
  end

  defp push_known(known, vs_out, vertex_identifier) do
    Enum.map_reduce(vs_out, known, fn {v, cost}, known ->
      id = vertex_identifier.(v)
      {{id, cost}, Map.put(known, id, v)}
    end)
  end

  defp push_vertices(q, known, v_id, vs_out, hfun, acc_cost \\ 0) do
    Enum.reduce(vs_out, q, fn {v2_id, cost}, q ->
      edge_cost = acc_cost + cost
      q_cost = edge_cost + hfun.(Map.get(known, v2_id))

      PQueue.push(q, {v_id, v2_id, edge_cost}, q_cost)
    end)
  end

  defp construct_path(v_id, %Graph{out_edges: oe} = tree, path) do
    path = [v_id | path]

    case oe |> Map.get(v_id, MapSet.new()) |> MapSet.to_list() do
      [] -> path
      [next_id] -> construct_path(next_id, tree, path)
    end
  end
end
