defmodule Mneme.Diff.Vertex do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Diff.Zipper

  defstruct [:id, :left, :left_branch?, :right, :right_branch?]

  @type t :: %Vertex{
          id: integer(),
          left: Zipper.t(),
          left_branch?: boolean(),
          right: Zipper.t(),
          right_branch?: boolean()
        }

  @doc false
  def new(left, right) do
    %Vertex{
      id: id(left, right),
      left: left,
      left_branch?: branch?(left),
      right: right,
      right_branch?: branch?(right)
    }
  end

  defp id(left, right), do: :erlang.phash2({id(left), id(right)})
  defp id(nil), do: :erlang.phash2(nil)

  defp id(zipper) do
    zipper
    |> Zipper.node()
    |> elem(1)
    |> Keyword.fetch!(:__id__)
  end

  defp branch?(nil), do: false
  defp branch?(zipper), do: zipper |> Zipper.node() |> Zipper.branch?()
end
