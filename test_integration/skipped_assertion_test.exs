# exit: 2
defmodule Mneme.Integration.SkippedAssertionTest do
  use ExUnit.Case
  use Mneme

  test "skipped tests do not update code but do cause an error exit at end" do
    # s
    auto_assert 2 + 2

    # y
    auto_assert 4 <- 2 + 1, 3 <- 2 + 1
  end
end
