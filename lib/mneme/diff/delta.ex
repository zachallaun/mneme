defmodule Mneme.Diff.Delta do
  @moduledoc false

  import Kernel, except: [node: 1]

  alias __MODULE__
  alias Mneme.Diff.SyntaxNode

  defstruct [:changed?, :kind, :side, :left_node, :right_node, depth_difference: 0, edit_script: []]

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
  def unchanged(kind, left_node, right_node, depth_difference \\ 0) do
    %Delta{
      changed?: false,
      kind: kind,
      left_node: left_node,
      right_node: right_node,
      depth_difference: depth_difference
    }
  end

  @doc "Returns the syntax node associated with this delta."
  def node(%Delta{side: :left, left_node: node}), do: node
  def node(%Delta{side: :right, right_node: node}), do: node

  @doc "The cost of this delta, used for pathfinding."
  def cost(edge)

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
