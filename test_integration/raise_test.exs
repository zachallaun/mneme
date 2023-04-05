defmodule Mneme.Integration.RaiseTest do
  use ExUnit.Case
  use Mneme

  describe "auto_assert_raise" do
    test "defaults to no message" do
      # y
      auto_assert_raise ArgumentError, fn ->
        error!("message")
      end
    end

    test "can also match a message" do
      # k y
      auto_assert_raise ArgumentError, "message", fn ->
        error!("message")
      end
    end
  end

  defp error!(s) do
    raise ArgumentError, s
  end
end
