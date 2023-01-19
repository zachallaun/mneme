defmodule MnemeIntegration.LiteralsTest do
  use ExUnit.Case
  import Mneme

  test "integers" do
    auto_assert 2 + 2

    auto_assert 4 = 2 + 2

    auto_assert 4 = 2 + 1
  end

  test "strings" do
    auto_assert "foo" <> "bar"

    auto_assert "foobar" = "foo" <> "bar"

    auto_assert "foobar" = "foo" <> "baz"
  end
end
