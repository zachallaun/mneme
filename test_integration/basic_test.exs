defmodule Mneme.Integration.BasicTest do
  use ExUnit.Case
  use Mneme

  test "integers" do
    # y
    auto_assert 4 <- 2 + 2

    # y
    auto_assert 4 <- 2 + 1, 3 <- 2 + 1
  end

  test "strings" do
    # y
    auto_assert "foobar" <- "foo" <> "bar"

    # y
    auto_assert "foobar" <- "foo" <> "baz", "foobaz" <- "foo" <> "baz"
  end

  test "tuples" do
    # y
    auto_assert {1, 2, 3} <- {1, 2, 3}
  end

  test "lists" do
    # y
    auto_assert [1, 2, 3] <- [1, 2, 3]
  end
end
