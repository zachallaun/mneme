defmodule MnemeIntegration.NonSerializableTest do
  use ExUnit.Case
  use Mneme

  test "pinned reference" do
    my_ref = make_ref()

    auto_assert ^my_ref <- Function.identity(my_ref)

    auto_assert [^my_ref] <- [my_ref]
  end

  test "is_reference guard" do
    auto_assert ref when is_reference(ref) <- make_ref()

    auto_assert [ref] when is_reference(ref) <- [make_ref()]

    auto_assert pid when is_pid(pid) <- self()
  end
end
