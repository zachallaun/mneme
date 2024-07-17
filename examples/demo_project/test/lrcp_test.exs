defmodule LRCPTest do
  use ExUnit.Case
  use Mneme, dry_run: true

  describe "parse/1" do
    @tag :first_example
    test "parses valid messages (1)" do
      auto_assert LRCP.parse("/connect/12345/")
      auto_assert LRCP.parse("/data/12345/0/hello!/")
    end

    @tag :second_example
    test "parses valid messages (2)" do
      auto_assert {:error, "hello\\//"} <-
                    LRCP.parse("/data/12345/0/hello\\//")
    end
  end
end
