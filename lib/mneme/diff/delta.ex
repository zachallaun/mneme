defmodule Mneme.Diff.Delta do
  @moduledoc false

  import Kernel, except: [node: 1]

  alias __MODULE__
  alias Mneme.Diff.SyntaxNode

  defstruct [
    :changed?,
    :kind,
    :side,
    :left,
    :right,
    :next_left,
    :next_right,
    depth_difference: 0,
    edit_script: []
  ]

  @type t :: %Delta{
          changed?: boolean(),
          kind: :branch | :node,
          side: :left | :right,
          depth_difference: non_neg_integer(),
          left: SyntaxNode.t(),
          right: SyntaxNode.t(),
          next_left: {SyntaxNode.t(), SyntaxNode.t()},
          next_right: {SyntaxNode.t(), SyntaxNode.t()},
          edit_script: [{:eq | :novel, String.t()}]
        }

  @doc "Construct a delta representing a changed node."
  def changed(kind, side, left, right, edit_script \\ []) do
    %Delta{
      changed?: true,
      kind: kind,
      side: side,
      left: left,
      right: right,
      edit_script: edit_script
    }
  end

  @doc "Construct a delta representing an unchanged node."
  def unchanged(kind, left, right, depth_difference) do
    %Delta{
      changed?: false,
      kind: kind,
      left: left,
      right: right,
      depth_difference: depth_difference
    }
  end

  @doc "Returns the syntax node associated with this delta."
  def node(%Delta{side: :left, left: node}), do: node
  def node(%Delta{side: :right, right: node}), do: node

  @doc "The cost of this delta, used for pathfinding."
  def cost(delta)

  def cost(%Delta{changed?: false, kind: :node, depth_difference: dd}), do: dd + 1
  def cost(%Delta{changed?: false, kind: :branch, depth_difference: dd}), do: dd + 10
  def cost(%Delta{changed?: true, kind: :branch}), do: 300

  def cost(%Delta{changed?: true, kind: :node} = delta) do
    290 + 160 * node(delta).n_descendants
  end
end
