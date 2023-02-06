defmodule MnemeIntegration.FormatTest do
  use ExUnit.Case
  use Mneme

  describe "multi-line strings" do
    test "should be formatted as heredocs" do
      auto_assert "foo\nbar\n"
      auto_assert "foo\nbar"
    end
  end
end
