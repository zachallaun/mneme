defmodule Mneme.Integration.BindingTest do
  use ExUnit.Case
  use Mneme

  test "bindings should stay in scope" do
    # y
    auto_assert pid when is_pid(pid) <- self()
    # y
    auto_assert ^pid <- self()
  end

  test "subsequent generated bindings should be unique" do
    # y
    auto_assert ref when is_reference(ref) <- make_ref()
    # y
    auto_assert ref_1 when is_reference(ref_1) <- make_ref()
    # y
    auto_assert ref_2 when is_reference(ref_2) <- make_ref()
  end

  test "bindings from mneme can be shadowed by user bindings" do
    # y
    auto_assert pid when is_pid(pid) <- self()

    pid = :foo
    # suppress warning
    _ = pid

    # y
    auto_assert pid_1 when is_pid(pid_1) <- self()
  end
end
