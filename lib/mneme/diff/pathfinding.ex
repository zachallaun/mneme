defmodule Mneme.Diff.Pathfinding do
  @moduledoc false

  # Originally derived from libgraph:
  # https://github.com/bitwalker/libgraph/blob/main/lib/graph/pathfinding.ex

  alias Mneme.Diff.PriorityQueue

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
    q = PriorityQueue.new()

    case next_fun.(v) do
      {:cont, vs_out} ->
        {vs_out, known} = push_known(known, vs_out, vertex_identifier)

        q
        |> push_vertices(known, v_id, vs_out, hfun)
        |> do_lazy_bfs(known, %{}, vertex_identifier, next_fun, hfun)
        |> case do
          {:ok, known, path} -> for(id <- path, do: Map.get(known, id))
          :error -> nil
        end

      :halt ->
        [v]

      :error ->
        nil
    end
  end

  ## Private

  defp do_lazy_bfs(q, known, history, vertex_identifier, next_fun, hfun) do
    case PriorityQueue.pop(q) do
      {:ok, {v1_id, v2_id, acc_cost}, q} ->
        v2 = Map.fetch!(known, v2_id)

        case next_fun.(v2) do
          :halt ->
            {:ok, known, construct_path(history, v1_id, [v2_id])}

          {:cont, vs_out} ->
            if Map.has_key?(history, v2_id) do
              do_lazy_bfs(q, known, history, vertex_identifier, next_fun, hfun)
            else
              {v2_out, known} = push_known(known, vs_out, vertex_identifier)
              history = Map.put(history, v2_id, v1_id)

              q
              |> push_vertices(known, v2_id, v2_out, hfun, acc_cost)
              |> do_lazy_bfs(known, history, vertex_identifier, next_fun, hfun)
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

      PriorityQueue.push(q, {v_id, v2_id, edge_cost}, q_cost)
    end)
  end

  defp construct_path(history, v_id, path) do
    path = [v_id | path]

    case history do
      %{^v_id => next_id} -> construct_path(history, next_id, path)
      _ -> path
    end
  end
end
