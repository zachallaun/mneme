defmodule Mneme.PatchTest do
  use ExUnit.Case, async: true
  import Mneme
  alias Mneme.Patch

  describe "get_test_line!/2" do
    test "finds the test line containing the given line" do
      source = """
      describe "some description" do
        test "first test" do
          # line 3
          # line 4
          # line 5
        end

        test "second test" do
          # line 9
        end
      end
      """

      state = Patch.register_file(Patch.init(), "nofile", source)

      auto_assert 2 <- Patch.get_test_line!(state, {nil, nil, %{file: "nofile", line: 4}})
      auto_assert 2 <- Patch.get_test_line!(state, {nil, nil, %{file: "nofile", line: 5}})
      auto_assert 8 <- Patch.get_test_line!(state, {nil, nil, %{file: "nofile", line: 9}})
    end

    test "handles unimplemented tests and weird formatting" do
      source = """
      describe "some description" do
        test "unimplemented"

        test "third test" do
          nil end
      end
      """

      state = Patch.register_file(Patch.init(), "nofile", source)

      auto_assert 4 <- Patch.get_test_line!(state, {nil, nil, %{file: "nofile", line: 5}})
    end
  end
end
