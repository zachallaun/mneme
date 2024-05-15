defmodule Mneme.Integration.TextMatchTest do
  use ExUnit.Case
  use Mneme

  describe "text/1" do
    test "succeeds for substrings and regular expressions" do
      # ignore
      auto_assert text("bc") <- "abcd"
      # ignore
      auto_assert text(~r/cde?/) <- "abcd"
    end

    test "rewrites without matcher if the value is not a string" do
      # y
      auto_assert text("bc") <- :foo, :foo <- :foo
    end

    test "rewrites without matcher if the pattern is not a string or regex" do
      # y
      auto_assert text(:foo) <- :foo, :foo <- :foo
    end

    test "is suggested for single-line strings with ignorable content" do
      # y
      auto_assert text("foo bar") <- "\n foo bar \n"
    end
  end
end
