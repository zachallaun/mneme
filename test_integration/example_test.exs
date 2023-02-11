# exit:2
defmodule Mneme.Integration.ExampleTest do
  use ExUnit.Case
  use Mneme

  test "first example" do
    # a
    auto_assert [1, 2, 3] <- [1, 2, 3]
  end

  test "second example" do
    # a
    auto_assert [1, 2, 3] <- [4, 5, 6], [4, 5, 6] <- [4, 5, 6]
  end

  test "third example" do
    # r
    auto_assert [4, 5, 6]

    auto_assert [7, 8, 9]
  end

  test "fourth example" do
    # a
    auto_assert Function.identity(nil) == false, Function.identity(nil) == nil

    # a
    auto_assert Function.identity(nil) == nil
  end
end
