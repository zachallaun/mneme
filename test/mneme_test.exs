defmodule MnemeTest do
  use ExUnit.Case
  doctest Mneme

  test "greets the world" do
    assert Mneme.hello() == :world
  end
end
