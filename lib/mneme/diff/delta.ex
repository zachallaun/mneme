defmodule Mneme.Diff.Delta do
  @moduledoc false

  import Kernel, except: [node: 1]

  alias __MODULE__
  alias Mneme.Diff.SyntaxNode

  defstruct [
    :changed?,
    :kind,
    :side,
    :left_node,
    :left_node_after,
    :left_node_before,
    :right_node,
    :right_node_after,
    :right_node_before,
    :adjacent?,
    depth_difference: 0,
    edit_script: []
  ]

  @type t :: %Delta{
          changed?: boolean(),
          kind: :branch | :node,
          side: :left | :right,
          depth_difference: non_neg_integer(),
          left_node: SyntaxNode.t(),
          right_node: SyntaxNode.t(),
          edit_script: [{:eq | :novel, String.t()}]
        }

  @doc "Construct a delta representing a changed node."
  def changed(kind, side, left_node, right_node, edit_script \\ []) do
    %Delta{
      changed?: true,
      kind: kind,
      side: side,
      left_node: left_node,
      right_node: right_node,
      edit_script: edit_script
    }
  end

  @doc "Construct a delta representing an unchanged node."
  def unchanged(kind, left_node, right_node, depth_difference, prev_delta) do
    %Delta{
      changed?: false,
      kind: kind,
      left_node: left_node,
      right_node: right_node,
      depth_difference: depth_difference,
      adjacent?: adjacent_unchanged?(prev_delta)
    }
  end

  defp adjacent_unchanged?(nil), do: false
  defp adjacent_unchanged?([%Delta{changed?: true} | _]), do: false
  defp adjacent_unchanged?(%Delta{changed?: true}), do: false
  defp adjacent_unchanged?(%Delta{changed?: false}), do: true

  @doc "Returns the syntax node associated with this delta."
  def node(%Delta{side: :left, left_node: node}), do: node
  def node(%Delta{side: :right, right_node: node}), do: node

  @doc "The cost of this delta, used for pathfinding."
  def cost(delta)

  def cost(deltas) when is_list(deltas), do: deltas |> Enum.map(&cost/1) |> Enum.sum()

  # def cost(%Delta{changed?: false, kind: :node, depth_difference: dd, adjacent?: false}),
  #   do: dd + 100

  def cost(%Delta{changed?: false, kind: :node, depth_difference: dd}), do: dd + 1
  def cost(%Delta{changed?: false, kind: :branch, depth_difference: dd}), do: dd + 10

  # TODO:
  # The cost for a changed branch where the opposing node is a similar
  # branch is much higher to reduce cases where the same branch is
  # removed and re-added.
  def cost(%Delta{changed?: true, kind: :branch}) do
    # if SyntaxNode.similar_branch?(node, opposing) do
    #   something higher than 300
    # else
    300
    # end
  end

  def cost(%Delta{changed?: true, kind: :node} = delta) do
    290 + 160 * node(delta).n_descendants
  end
end
