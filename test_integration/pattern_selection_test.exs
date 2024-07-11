defmodule Mneme.Integration.PatternSelectionTest do
  use ExUnit.Case
  use Mneme

  test "k navigates to next pattern" do
    value = %{x: 10, y: 20, z: 30}

    # k y
    auto_assert %{x: 10, y: 20, z: 30} <- value
  end

  test "j navigates to prev pattern" do
    value = %{x: 10, y: 20, z: 30}

    # k j y
    auto_assert ^value <- value
  end

  test "k loops around to first pattern" do
    value = %{x: 10, y: 20, z: 30}

    # k k y
    auto_assert ^value <- value
  end

  test "j loops around to last pattern" do
    value = %{x: 10, y: 20, z: 30}

    # j y
    auto_assert %{x: 10, y: 20, z: 30} <- value
  end

  test "J goes to first pattern" do
    value = %{x: 10, y: 20, z: 30}

    # k J y
    auto_assert %{x: 1, y: 2} <- value, ^value <- value
  end

  test "K goes to last pattern" do
    value = %{x: 10, y: 20, z: 30}

    # j K y
    auto_assert %{x: 1, y: 2} <- value, %{x: 10, y: 20, z: 30} <- value
  end
end
