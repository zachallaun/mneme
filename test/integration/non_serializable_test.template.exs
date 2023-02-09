defmodule MnemeIntegration.NonSerializableTest do
  use ExUnit.Case
  use Mneme

  test "pinned" do
    my_ref = make_ref()

    auto_assert Function.identity(my_ref)

    auto_assert [my_ref]
  end

  test "guard" do
    auto_assert make_ref()

    auto_assert [make_ref()]

    auto_assert self()
  end
end
