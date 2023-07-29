defmodule Mneme.Diff.PriorityQueue do
  @moduledoc false

  @opaque t :: :gb_trees.tree()

  @type priority :: non_neg_integer()

  @doc """
  Creates a new priority queue.
  """
  @spec new() :: t
  def new do
    :gb_trees.empty()
  end

  @doc """
  Creates a new priority queue with initial values and priorities.
  """
  @spec new([{term(), priority}]) :: t
  def new(list) when is_list(list) do
    Enum.reduce(list, new(), fn {value, priority}, pqueue ->
      push(pqueue, value, priority)
    end)
  end

  @doc """
  Push a new element into the queue with a given priority.
  """
  @spec push(t, term(), priority) :: t
  def push(pqueue, value, priority) do
    case :gb_trees.lookup(priority, pqueue) do
      :none ->
        queue = :queue.new()
        queue = :queue.in(value, queue)
        :gb_trees.insert(priority, queue, pqueue)

      {:value, queue} ->
        new_queue = :queue.in(value, queue)
        :gb_trees.update(priority, new_queue, pqueue)
    end
  end

  @doc """
  Pop an element out of the queue, returning `{:value, value, queue}` or
  `:empty` if there is not an element to pop.
  """
  @spec pop(t) :: {:value, term(), t} | :empty
  def pop(pqueue) do
    if :gb_trees.is_empty(pqueue) do
      :empty
    else
      {priority, queue, pqueue} = :gb_trees.take_smallest(pqueue)
      {{:value, value}, queue} = :queue.out(queue)

      if :queue.is_empty(queue) do
        {:value, value, pqueue}
      else
        {:value, value, :gb_trees.insert(priority, queue, pqueue)}
      end
    end
  end
end
