defmodule Mneme.Integration.InferredPatternTest do
  use ExUnit.Case
  use Mneme

  test "partial maps" do
    # y
    auto_assert %{x: 1} <- %{x: "X", y: 2}, %{x: "X"} <- %{x: "X", y: 2}
  end

  test "ignored partial map values stay ignored" do
    # y
    auto_assert %{x: 1, y: _} <- %{x: "X", y: 2, z: 3}, %{x: "X", y: _} <- %{x: "X", y: 2, z: 3}
  end

  test "ignored full map values stay ignored" do
    # y
    auto_assert %{x: 1, y: _} <- %{x: "X", y: 2}, %{x: "X", y: _} <- %{x: "X", y: 2}
  end

  test "partial maps stay in order" do
    # y
    auto_assert %{z: 3, y: 2} <- %{x: 1, y: 2, z: "z"},
                %{z: "z", y: 2} <- %{x: 1, y: 2, z: "z"}
  end

  test "partial maps stay in order with ignored values" do
    # y
    auto_assert %{z: 3, y: _} <- %{x: 1, y: 2, z: "z"}, %{z: "z", y: _} <- %{x: 1, y: 2, z: "z"}
  end
end
