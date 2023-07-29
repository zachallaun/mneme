defmodule Mneme.Diff.Pathfinding do
  @moduledoc false

  # Originally derived from libgraph:
  # https://github.com/bitwalker/libgraph/blob/main/lib/graph/pathfinding.ex

  alias Mneme.Diff.PriorityQueue

  @doc """
  Performs a uniform cost search to find the shortest path between `node`
  and a target.

  This algorithm is a variant of Djikstra's algorithm.

  The `next_fun` will receive each node under consideration and must
  return one of:

    * `{:cont, neighbors}` to continue searching, where neighbors is a
      list of `{node, cost}` pairs
    * `{:halt, target}` to indicate that the search target has been found

  ### Options

    * `:id` `(node -> id)` - a function that returns a unique id for
      any given node
    * `:heuristic` `(node1, node2 -> non_neg_integer())` - a function
      that returns a heuristic value to be added to the node's cost
      (this can be used to implement a lazy version of A* search)

  """
  @spec uniform_cost_search(
          node,
          (node -> {:cont, [{node, cost}]} | {:halt, node}),
          keyword()
        ) ::
          {:ok, [node, ...]} | :error
        when node: term(), cost: non_neg_integer()
  def uniform_cost_search(root, next_fun, opts \\ []) do
    pqueue = PriorityQueue.new([{{root, 0}, 0}])
    costs = %{}

    funs = %{
      next: next_fun,
      id: Keyword.get(opts, :id, &Function.identity/1),
      heuristic: Keyword.get(opts, :heuristic, fn _, _ -> 0 end)
    }

    do_uniform_cost_search({pqueue, costs}, funs)
  end

  defp do_uniform_cost_search({pqueue, costs}, funs) do
    with {:value, {current, acc_cost}, pqueue} <- PriorityQueue.pop(pqueue),
         {:cont, neighbors} <- funs.next.(current) do
      neighbors
      |> Enum.reduce({pqueue, costs}, fn {neighbor, cost}, {pqueue, costs} ->
        id = funs.id.(neighbor)

        # The accumulated cost should not contain the heuristic value
        # to prevent it from compounding on subsequent nodes.
        acc_cost = acc_cost + cost
        priority_cost = acc_cost + funs.heuristic.(current, neighbor)

        case Map.fetch(costs, id) do
          {:ok, {_, prev_cost}} when acc_cost > prev_cost ->
            {pqueue, costs}

          _ ->
            pqueue = PriorityQueue.push(pqueue, {neighbor, acc_cost}, priority_cost)
            costs = Map.put(costs, id, {current, acc_cost})
            {pqueue, costs}
        end
      end)
      |> do_uniform_cost_search(funs)
    else
      {:halt, goal} -> {:ok, build_path(goal, costs, funs)}
      :empty -> :error
    end
  end

  defp build_path(node, costs, funs) do
    id = funs.id.(node)
    build_path(id, costs, funs, [node])
  end

  defp build_path(id, costs, funs, path) do
    case Map.fetch(costs, id) do
      {:ok, {node, _}} ->
        id = funs.id.(node)
        build_path(id, costs, funs, [node | path])

      :error ->
        path
    end
  end
end
