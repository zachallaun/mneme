# exit: 2
defmodule Mneme.Integration.RejectTest2 do
  use ExUnit.Case
  use Mneme

  test "integers" do
    # n
    auto_assert 2 + 2, 2 + 2

    auto_assert 2 + 1
  end

  test "strings" do
    # n
    auto_assert "foo" <> "bar", "foo" <> "bar"

    auto_assert "foo" <> "baz"
  end
end
