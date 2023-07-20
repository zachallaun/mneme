# exit: 2
defmodule Mneme.Integration.RejectTest1 do
  @moduledoc false
  use ExUnit.Case
  use Mneme

  test "integers" do
    # y
    auto_assert 4 <- 2 + 2

    # n
    auto_assert 4 <- 2 + 1, 4 <- 2 + 1
  end
end
