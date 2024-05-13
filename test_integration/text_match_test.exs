defmodule Mneme.Integration.TextMatchTest do
  use ExUnit.Case
  use Mneme

  describe "<~ operator" do
    test "succeeds for substrings and regular expressions" do
      # ignore
      auto_assert "bc" <~ "abcd"
      # ignore
      auto_assert ~r/cde?/ <~ "abcd"
    end

    test "rewrites to <- if the value is not a string" do
      # y
      auto_assert "bc" <~ :foo, :foo <- :foo
    end

    test "rewrites to <- if the pattern is not a string or regex" do
      # y
      auto_assert :foo <~ :foo, :foo <- :foo
    end

    test "is suggested for single-line strings with ignorable content" do
      # y
      auto_assert "foo bar" <~ "\n foo bar \n"
    end
  end
end
