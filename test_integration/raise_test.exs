# version: >= 1.14.4
defmodule Mneme.Integration.RaiseTest do
  use ExUnit.Case
  use Mneme

  describe "auto_assert_raise" do
    test "defaults to no message" do
      # y
      auto_assert_raise ArgumentError, fn ->
        error!()
      end

      # y
      auto_assert_raise ArgumentError, &error!/0
    end

    test "can match a message" do
      # k y
      auto_assert_raise ArgumentError, "message", fn ->
        error!("message")
      end
    end

    test "can match a message with escaped characters" do
      # k y
      auto_assert_raise ArgumentError, "message with \"quotes\"", fn ->
        error!("message with \"quotes\"")
      end
    end

    test "can match a multi-line message with escaped characters" do
      # k k y
      auto_assert_raise ArgumentError,
                        """
                        foo
                        \\
                        bar
                        """,
                        fn ->
                          error!("""
                          foo
                          \\
                          bar
                          """)
                        end
    end

    test "raises if no exception is raised by function" do
      assert_raise Mneme.AssertionError, fn ->
        # ignore
        auto_assert_raise ArgumentError, fn -> :foo end
      end
    end
  end

  defp error!(s \\ "message") do
    raise ArgumentError, s
  end
end
