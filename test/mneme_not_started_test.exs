defmodule Mneme.MnemeNotStartedTest do
  use ExUnit.Case
  use Mneme

  @tag :mneme_not_started
  test "assertion error is raised" do
    assert_raise Mneme.AssertionError, fn ->
      auto_assert 2 + 2
    end
  end
end
