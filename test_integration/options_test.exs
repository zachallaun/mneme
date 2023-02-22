# exit:2
defmodule Mneme.Integration.OptionsTest do
  use ExUnit.Case
  use Mneme

  @mneme action: :accept
  test "should accept without prompt" do
    auto_assert 2 <- 1 + 1
  end

  @mneme action: :reject
  test "should reject without prompt" do
    auto_assert 1 + 1
  end

  @mneme target: :ex_unit, action: :accept
  test "should rewrite to an ExUnit assertion" do
    assert 2 = 1 + 1
  end

  describe "describe tag attributes" do
    @mneme_describe target: :ex_unit, action: :accept

    test "should rewrite to ExUnit assertion 1" do
      assert 2 = 1 + 1
    end

    test "should rewrite to ExUnit assertion 2" do
      assert 4 = 2 + 2
    end

    test "should rewrite to ExUnit assertion with pin" do
      me = self()
      assert ^me = Function.identity(me)
    end

    test "should rewrite to ExUnit assertion keeping the same pattern" do
      assert %{foo: 1} <- %{foo: 1}, %{foo: 1} = %{foo: 1}
    end
  end
end
