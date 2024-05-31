defmodule MnemeTest do
  use ExUnit.Case, async: true
  use Mneme

  import ExUnit.CaptureIO

  describe "auto_assert/1" do
    test "raises at compile-time if called outside of a test" do
      code = """
      defmodule MnemeCompileExceptionTest do
        use ExUnit.Case
        use Mneme

        auto_assert :foo
      end
      """

      auto_assert_raise Mneme.CompileError, "auto_assert can only be used inside of a test", fn ->
        Code.eval_string(code)
      end
    end

    test "warns at compile-time if the assertion cannot ever fail" do
      code = """
      defmodule MnemeUselessAssertionTest do
        use ExUnit.Case
        use Mneme

        test "always succeeds" do
          auto_assert foo <- 1 + 1
          foo # suppress unused var warning
        end
      end
      """

      assert capture_io(fn -> Code.eval_string(code) end) =~ """
             (nofile:6) assertion will always succeed:

                 auto_assert foo <- 1 + 1

             Consider rewriting to:

                 foo = 1 + 1
             """
    end
  end

  describe "<-/2" do
    test "raises at compile-time if used outside of a form that supports it" do
      code = """
      import Mneme
      :foo <- :bar
      """

      auto_assert_raise Mneme.CompileError,
                        "`<-` can only be used in `auto_assert` or in special forms like `for`",
                        fn ->
                          Code.eval_string(code)
                        end
    end
  end

  describe "non-interactive" do
    test "existing correct assertions succeed" do
      assertion = Mneme.Assertion.new(quote(do: auto_assert(1 <- 1)), 1, context(__ENV__))

      assert Mneme.Assertion.run!(assertion, __ENV__, false)
    end

    test "existing incorrect assertions fail with an ExUnit.AssertionError" do
      assertion = Mneme.Assertion.new(quote(do: auto_assert(1 <- 2)), 2, context(__ENV__))

      assert capture_io(fn ->
               assert_raise ExUnit.AssertionError, fn ->
                 Mneme.Assertion.run!(assertion, __ENV__, false)
               end
             end) =~ "Mneme is running in non-interactive mode."
    end

    test "new assertions fail with a Mneme.AssertionError" do
      assertion = Mneme.Assertion.new(quote(do: auto_assert(1)), 1, context(__ENV__))

      assert capture_io(fn ->
               assert_raise Mneme.AssertionError, fn ->
                 Mneme.Assertion.run!(assertion, __ENV__, false)
               end
             end) =~ "Mneme is running in non-interactive mode."
    end

    defp context(env) do
      env
      |> Mneme.Assertion.assertion_context()
      |> Keyword.put(:binding, [])
    end
  end

  test "Mneme.Server doesn't blow up if something goes wrong" do
    message = ~r"""
    Mneme encountered an internal error. This is likely a bug in Mneme.

    Please consider reporting this error at https://github.com/zachallaun/mneme/issues. Thanks!

    \*\* \(ArgumentError\) I told you!
    """

    assert_raise Mneme.InternalError, message, fn ->
      auto_assert :__mneme__super_secret_test_value_goes_boom__
    end
  end
end
