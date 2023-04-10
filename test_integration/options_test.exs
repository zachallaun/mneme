# exit: 2
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

  describe "target: :ex_unit" do
    @mneme_describe target: :ex_unit, action: :accept
    test "should rewrite to ExUnit assertion 1" do
      # auto_assert
      assert 2 = 1 + 1
    end

    test "should rewrite to ExUnit assertion 2" do
      # auto_assert
      assert 4 = 2 + 2
    end

    test "should rewrite to ExUnit assertion with pin" do
      me = self()
      # auto_assert
      assert ^me = Function.identity(me)
    end

    test "should rewrite falsy values as == comparisons" do
      # auto_assert
      assert nil <- Function.identity(nil), Function.identity(nil) == nil
    end
  end

  describe ":default_pattern" do
    @mneme_describe action: :accept

    @mneme default_pattern: :last
    test "should default to the last in the list of pattern options" do
      auto_assert %{foo: 1} <- %{foo: 1}

      me = self()
      auto_assert %{foo: pid} when is_pid(pid) <- %{foo: me}
    end

    @mneme target: :ex_unit
    test "should default to using same pattern when rewriting to :ex_unit" do
      # auto_assert
      assert %{foo: 1} <- %{foo: 1}, %{foo: 1} = %{foo: 1}
    end

    @mneme target: :ex_unit, default_pattern: :first
    test "should replace pattern when rewriting to :ex_unit with default_pattern: :first" do
      # auto_assert
      assert %{foo: 1} <- %{foo: 1}, %{} = %{foo: 1}
    end
  end

  @mneme action: :accept, default_pattern: :last, force_update: true
  test "should force an update for a passing assertion (1)" do
    auto_assert %{} <- %{foo: :bar}, %{foo: :bar} <- %{foo: :bar}
  end

  @mneme [:force_update, action: :accept, default_pattern: :last]
  test "should force an update for a passing assertion (2)" do
    auto_assert %{} <- %{foo: :bar}, %{foo: :bar} <- %{foo: :bar}
  end
end
