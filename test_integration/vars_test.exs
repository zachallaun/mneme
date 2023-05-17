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

  test "re-use var with single guard if same value appears multiple times" do
    # y
    auto_assert [pid, pid] when is_pid(pid) <- [self(), self()]
    # y
    auto_assert [pid, [pid, [pid]]] when is_pid(pid) <- [self(), [self(), [self()]]]
    # k y
    auto_assert [pid, %{p: pid, r: ref}] when is_pid(pid) and is_reference(ref) <-
                  [
                    self(),
                    %{p: self(), r: make_ref()}
                  ]
  end
end
