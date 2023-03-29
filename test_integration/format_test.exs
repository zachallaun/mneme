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

    test "should format nested as heredocs" do
      # y
      auto_assert {:ok,
                   """
                   foo
                   bar\
                   """} <- {:ok, "foo\nbar"}
    end
  end

  describe "escaped characters" do
    @mneme default_pattern: :last
    test "should correctly escape quotes and interpolations" do
      res =
        {:ok,
         %{
           database: {:literal, "\"my_app_test\#{System.get_env(\"MIX_TEST_PARTITION\")}\""}
         }}

      # y
      auto_assert {:ok,
                   %{
                     database:
                       {:literal, "\"my_app_test\#{System.get_env(\"MIX_TEST_PARTITION\")}\""}
                   }} <- res
    end
  end
end
