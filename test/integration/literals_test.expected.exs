defmodule MnemeIntegration.LiteralsTest do
  use ExUnit.Case
  import Mneme

  test "integers" do
    # no assertion yet
    auto_assert 4 = 2 + 2

    # correct assertion
    auto_assert 4 = 2 + 2
  end

  test "strings" do
    # no assertion yet
    auto_assert "foobar" = "foo" <> "bar"

    # correct assertion
    auto_assert "foobar" = "foo" <> "bar"
  end
end
