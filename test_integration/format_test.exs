defmodule Mneme.Integration.FormatTest do
  use ExUnit.Case
  use Mneme

  describe "multi-line strings" do
    test "should be formatted as heredocs" do
      # y
      auto_assert """
                  foo
                  bar
                  """ <- "foo\nbar\n"

      # y
      auto_assert """
                  foo
                  bar\
                  """ <- "foo\nbar"
    end
  end
end
