defmodule Mneme.Diff.Edge do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Diff.SyntaxNode

  defstruct [:type, :kind, :side, :node, depth_difference: 0]

  @type t :: %Edge{
          type: :novel | :unchanged,
          kind: :branch | :node,
          side: :left | :right,
          depth_difference: non_neg_integer(),
          node: SyntaxNode.t()
        }

  @doc "Construct an edge representing a novel node."
  def novel(kind, side, node) do
    %Edge{type: :novel, kind: kind, side: side, node: node}
  end

  @doc "Construct an edge representing an unchanged node."
  def unchanged(kind, node, depth_difference \\ 0) do
    %Edge{type: :unchanged, kind: kind, node: node, depth_difference: depth_difference}
  end

  @doc "The cost of taking this edge."
  def cost(edge)

  def cost(%Edge{type: :unchanged, kind: :node, depth_difference: dd}), do: dd + 1
  def cost(%Edge{type: :unchanged, kind: :branch, depth_difference: dd}), do: dd + 10

  def cost(%Edge{type: :novel, kind: :branch}), do: 300

  def cost(%Edge{type: :novel, kind: :node, node: node}) do
    300 + 160 * SyntaxNode.n_descendants(node)
  end
end
