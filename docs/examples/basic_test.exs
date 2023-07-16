defmodule ExampleTest do
  use ExUnit.Case
  use Mneme

  test "String.to_atom/1" do
    auto_assert String.to_atom("mneme")
  end
end
