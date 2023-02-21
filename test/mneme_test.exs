defmodule MnemeTest do
  use ExUnit.Case
  use Mneme

  describe "auto_assert/1" do
    @mneme action: :reject
    test "raises if no pattern is present" do
      assert_raise Mneme.AssertionError, fn ->
        auto_assert :foo
      end
    end

    @mneme action: :reject
    test "raises when the match fails" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          auto_assert :foo <- :bar
        end

      assert %{left: :foo, right: :bar, message: "match (=) failed"} = error
    end
  end
end
