defmodule Mneme.Diff.Edge do
  @moduledoc false

  alias __MODULE__

  defstruct [:type, :kind, :side, :depth_difference]

  @type t :: %Edge{
          type: :novel | :unchanged,
          kind: :branch | :node,
          side: :left | :right,
          depth_difference: non_neg_integer()
        }

  @doc "Construct an edge representing a novel node."
  def novel(branch?, side) do
    %Edge{type: :novel, kind: kind(branch?), side: side, depth_difference: 0}
  end

  @doc "Construct an edge representing an unchanged node."
  def unchanged(branch?, depth_difference \\ 0) do
    %Edge{type: :unchanged, kind: kind(branch?), depth_difference: depth_difference}
  end

  @doc "The cost of taking this edge."
  def cost(edge)

  def cost(%Edge{type: :unchanged, kind: :node, depth_difference: dd}), do: min(40, dd + 1)

  def cost(%Edge{type: :unchanged, kind: :branch, depth_difference: dd}) do
    100 + min(40, dd + 1)
  end

  def cost(%Edge{type: :novel}), do: 300

  defp kind(branch?)
  defp kind(true), do: :branch
  defp kind(false), do: :node
end
