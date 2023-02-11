defmodule Mneme.Integration.NonSerializableTest do
  use ExUnit.Case
  use Mneme

  test "pinned" do
    my_ref = make_ref()

    # a
    auto_assert ^my_ref <- Function.identity(my_ref)

    # a
    auto_assert [^my_ref] <- [my_ref]
  end

  test "guard" do
    # a
    auto_assert ref when is_reference(ref) <- make_ref()

    # a
    auto_assert [ref] when is_reference(ref) <- [make_ref()]

    # a
    auto_assert pid when is_pid(pid) <- self()
  end

  test "shrink and expand" do
    my_ref = make_ref()

    # n a
    auto_assert ref when is_reference(ref) <- my_ref

    # n p a
    auto_assert ^my_ref <- my_ref

    # p a
    auto_assert ^my_ref <- my_ref
  end
end
