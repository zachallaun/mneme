defmodule Mneme.Integration.NonSerializableTest do
  use ExUnit.Case
  use Mneme

  test "pinned" do
    my_ref = make_ref()

    # y
    auto_assert ^my_ref <- Function.identity(my_ref)

    # y
    auto_assert [^my_ref] <- [my_ref]
  end

  test "guard" do
    # y
    auto_assert ref when is_reference(ref) <- make_ref()

    # y
    auto_assert [ref_1] when is_reference(ref_1) <- [make_ref()]

    # y
    auto_assert pid when is_pid(pid) <- self()
  end

  test "shrink and expand" do
    my_ref = make_ref()

    # y
    auto_assert ^my_ref <- my_ref

    # k y
    auto_assert ref when is_reference(ref) <- my_ref
  end
end
