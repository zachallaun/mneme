defmodule Mneme.Diff.Vertex do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Diff.Zipper

  defstruct [:id, :left, :right]

  @type t :: %Vertex{
          id: integer(),
          left: {:branch | :leaf, Zipper.t()},
          right: {:branch | :leaf, Zipper.t()}
        }

  @doc false
  def new(left, right) do
    left = wrap(left)
    right = wrap(right)

    %Vertex{id: id(left, right), left: left, right: right}
  end

  defp id(left, right), do: :erlang.phash2({id(left), id(right)})
  defp id(nil), do: :erlang.phash2(nil)

  defp id({_, zipper}) do
    zipper
    |> Zipper.node()
    |> elem(1)
    |> Keyword.fetch!(:__id__)
  end

  defp wrap(nil), do: nil
  defp wrap({:branch, _} = wrapped), do: wrapped
  defp wrap({:leaf, _} = wrapped), do: wrapped

  defp wrap(zipper) do
    if zipper |> Zipper.node() |> Zipper.branch?() do
      {:branch, zipper}
    else
      {:leaf, zipper}
    end
  end
end
