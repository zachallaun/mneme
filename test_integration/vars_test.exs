defmodule Mneme.Integration.VarsTest do
  use ExUnit.Case
  use Mneme

  test "vars for different values should be unique" do
    # y
    auto_assert [ref, ref1] when is_reference(ref) and is_reference(ref1) <-
                  [
                    make_ref(),
                    make_ref()
                  ]
  end

  test "vars shouldn't shouldn't shadow existing vars in scope" do
    ref = make_ref()

    # y
    auto_assert ref1 when is_reference(ref1) <- make_ref()

    pid = self()

    # y
    auto_assert ^pid <- self()
    # k y
    auto_assert pid1 when is_pid(pid1) <- self()
    # k k y
    auto_assert %{foo: [pid1]} when is_pid(pid1) <- %{foo: [self()]}
  end
end
