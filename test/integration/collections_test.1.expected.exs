defmodule MnemeIntegration.CollectionsTest do
  use ExUnit.Case
  import Mneme

  test "tuples" do
    auto_assert {1, 2, 3} <- {1, 2, 3}
  end

  test "lists" do
    auto_assert [1, 2, 3] <- [1, 2, 3]
  end
end
