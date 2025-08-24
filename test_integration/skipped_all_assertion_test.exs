# exit: 2
defmodule Mneme.Integration.SkippedAllAssertionTest do
  use ExUnit.Case
  use Mneme

  test "skipping all tests does not update code but does exit with an error code" do
    # S
    auto_assert 2 + 2

    auto_assert 2 + 2

    auto_assert 1 + 2
  end
  
  test "shouldn't run because skip all was used in the first test" do
    auto_assert 1 + 1
  end
end
