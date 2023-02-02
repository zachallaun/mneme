defmodule MnemeIntegration.LiteralsTest do
  use ExUnit.Case
  use Mneme

  test "integers" do
    # no assertion yet
    auto_assert 4 <- 2 + 2

    # correct assertion
    auto_assert 4 <- 2 + 2

    # incorrect assertion
    auto_assert 3 <- 2 + 1
  end

  test "strings" do
    # no assertion yet
    auto_assert "foobar" <- "foo" <> "bar"

    # correct assertion
    auto_assert "foobar" <- "foo" <> "bar"

    # incorrect assertion
    auto_assert "foobaz" <- "foo" <> "baz"
  end
end
