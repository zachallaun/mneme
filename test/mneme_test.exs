defmodule MnemeTest do
  use ExUnit.Case, async: true
  use Mneme

  describe "auto_assert/1" do
    @mneme action: :reject
    test "raises if no pattern is present" do
      assert_raise Mneme.AssertionError, "No pattern present", fn ->
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

      auto_assert_raise Mneme.CompileError, "auto_assert can only be used inside of a test", fn ->
        Code.eval_string(code)
      end
    end
  end

  describe "non-interactive" do
    import ExUnit.CaptureIO

    test "existing correct assertions succeed" do
      assertion =
        Mneme.Assertion.new(:auto_assert, quote(do: auto_assert(1 <- 1)), 1, context(__ENV__))

      assert Mneme.Assertion.run(assertion, __ENV__, false)
    end

    test "existing incorrect assertions fail with an ExUnit.AssertionError" do
      assertion =
        Mneme.Assertion.new(:auto_assert, quote(do: auto_assert(1 <- 2)), 2, context(__ENV__))

      assert capture_io(fn ->
               assert_raise ExUnit.AssertionError, fn ->
                 Mneme.Assertion.run(assertion, __ENV__, false)
               end
             end) =~ "Mneme is running in non-interactive mode."
    end

    test "new assertions fail with a Mneme.AssertionError" do
      assertion =
        Mneme.Assertion.new(:auto_assert, quote(do: auto_assert(1)), 1, context(__ENV__))

      assert capture_io(fn ->
               assert_raise Mneme.AssertionError, fn ->
                 Mneme.Assertion.run(assertion, __ENV__, false)
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
end
