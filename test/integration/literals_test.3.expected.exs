defmodule MnemeIntegration.LiteralsTest do
  use ExUnit.Case
  import Mneme

  test "integers" do
    # no assertion yet
    auto_assert 2 + 2

    # correct assertion
    auto_assert 4 = 2 + 2

    # incorrect assertion
    auto_assert 4 = 2 + 1
  end

  test "strings" do
    # no assertion yet
    auto_assert "foo" <> "bar"

    # correct assertion
    auto_assert "foobar" = "foo" <> "bar"

    # incorrect assertion
    auto_assert "foobar" = "foo" <> "baz"
  end
end
