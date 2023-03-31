defmodule Mneme.Diff.Delta do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Diff.SyntaxNode

  defstruct [:type, :kind, :side, :node, depth_difference: 0, edit_script: []]

  @type t :: %Delta{
          type: :novel | :unchanged,
          kind: :branch | :node,
          side: :left | :right,
          depth_difference: non_neg_integer(),
          node: SyntaxNode.t(),
          edit_script: [{:eq | :novel, String.t()}]
        }

  @doc "Construct a delta representing a novel node."
  def novel(kind, side, node, edit_script \\ []) do
    %Delta{type: :novel, kind: kind, side: side, node: node, edit_script: edit_script}
  end

  @doc "Construct a delta representing an unchanged node."
  def unchanged(kind, node, depth_difference \\ 0) do
    %Delta{type: :unchanged, kind: kind, node: node, depth_difference: depth_difference}
  end

  @doc "The cost of this delta, used for pathfinding."
  def cost(edge)

  def cost(%Delta{type: :unchanged, kind: :node, depth_difference: dd}), do: dd + 1
  def cost(%Delta{type: :unchanged, kind: :branch, depth_difference: dd}), do: dd + 10

  def cost(%Delta{type: :novel, kind: :branch}), do: 300

  def cost(%Delta{type: :novel, kind: :node, node: node}) do
    290 + 160 * node.n_descendants
  end
end
