defmodule DemoTest do
  use ExUnit.Case
  use Mneme

  test "filter evens" do
    auto_assert Enum.filter(1..10, &(rem(&1, 2) == 0))
  end
end
