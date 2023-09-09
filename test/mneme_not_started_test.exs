defmodule Mneme.MnemeNotStartedTest do
  use ExUnit.Case
  use Mneme

  @tag :mneme_not_started
  test "error" do
    assert_raise RuntimeError, ~r/Did you start Mneme/, fn ->
      code = """
      defmodule Mneme.StartedTest.ExampleTest do
        use ExUnit.Case
        use Mneme

        test "a test" do
          auto_assert 2 + 2
        end
      end
      """

      assert [{_, _}] = Code.compile_string(code)
    end
  end
end
