defmodule Mneme.Diff.Delta do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Diff.SyntaxNode

  defstruct [:changed?, :kind, :side, :node, depth_difference: 0, edit_script: []]

  @type t :: %Delta{
          changed?: boolean(),
          kind: :branch | :node,
          side: :left | :right,
          depth_difference: non_neg_integer(),
          node: SyntaxNode.t(),
          edit_script: [{:eq | :novel, String.t()}]
        }

  @doc "Construct a delta representing a changed node."
  def changed(kind, side, node, edit_script \\ []) do
    %Delta{changed?: true, kind: kind, side: side, node: node, edit_script: edit_script}
  end

  @doc "Construct a delta representing an unchanged node."
  def unchanged(kind, node, depth_difference \\ 0) do
    %Delta{changed?: false, kind: kind, node: node, depth_difference: depth_difference}
  end

  @doc "The cost of this delta, used for pathfinding."
  def cost(edge)

  def cost(%Delta{changed?: false, kind: :node, depth_difference: dd}), do: dd + 1
  def cost(%Delta{changed?: false, kind: :branch, depth_difference: dd}), do: dd + 10

  def cost(%Delta{changed?: true, kind: :branch}), do: 300

  def cost(%Delta{changed?: true, kind: :node, node: node}) do
    290 + 160 * node.n_descendants
  end
end
