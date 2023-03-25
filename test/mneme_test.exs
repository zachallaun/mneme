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

    test "raises at compile-time if called outside of a test" do
      code = """
      defmodule MnemeCompileExceptionTest do
        use ExUnit.Case
        use Mneme

        auto_assert :foo
      end
      """

      assert_raise Mneme.CompileError, "auto_assert can only be used inside of a test", fn ->
        Code.eval_string(code)
      end
    end
  end

  test "Mneme.Server doesn't blow up if something goes wrong" do
    error =
      assert_raise Mneme.InternalError, fn ->
        auto_assert :__mneme__super_secret_test_value_goes_boom__
      end

    assert String.contains?(Exception.message(error), """
           Mneme encountered an internal error. This is likely a bug in Mneme.

           Please consider reporting this error at https://github.com/zachallaun/mneme/issues. Thanks!

           ** (ArgumentError) I told you!
           """)
  end

  test "Mneme.Options.configure/0 can be called multiple times" do
    assert :ok = Mneme.Options.configure()
    assert :ok = Mneme.Options.configure()
  end
end
