defmodule MnemeIntegration.OptionsTest do
  use ExUnit.Case
  use Mneme

  @mneme action: :accept
  test "should accept without prompt" do
    auto_assert 1 + 1
  end

  @mneme action: :reject
  test "should reject without prompt" do
    auto_assert 1 + 1
  end

  @mneme target: :assert
  test "should rewrite to an ExUnit assertion" do
    auto_assert 1 + 1
  end

  describe "describe tag attributes" do
    @mneme_describe target: :assert, action: :accept

    test "should rewrite to ExUnit assertion 1" do
      auto_assert 1 + 1
    end

    test "should rewrite to ExUnit assertion 2" do
      auto_assert 2 + 2
    end

    test "should rewrite to ExUnit assertion with guards/pins" do
      auto_assert self()

      me = self()
      auto_assert Function.identity(me)
    end
  end
end
