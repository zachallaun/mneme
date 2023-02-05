defmodule Mneme.AssertionTest do
  use ExUnit.Case
  use Mneme
  alias Mneme.Assertion

  test "w/o guard" do
    assertion = Assertion.new(quote(do: [1, 2, 3] <- [1, 2, 3]), [1, 2, 3], %{})

    auto_assert "auto_assert([1, 2, 3] <- [1, 2, 3])" <-
                  assertion |> Assertion.convert(target: :mneme) |> Sourceror.to_string()

    auto_assert "assert [1, 2, 3] = [1, 2, 3]" <-
                  assertion |> Assertion.convert(target: :ex_unit) |> Sourceror.to_string()
  end

  test "w/ guard" do
    me = self()

    assertion =
      Assertion.new(
        quote(do: pid when is_pid(pid) <- me),
        me,
        %{locals: [me: me]}
      )

    auto_assert "auto_assert(pid when is_pid(pid) <- me)" <-
                  assertion |> Assertion.convert(target: :mneme) |> Sourceror.to_string()

    auto_assert """
                value = assert pid = me
                assert is_pid(pid)
                value\
                """ <- assertion |> Assertion.convert(target: :ex_unit) |> Sourceror.to_string()
  end

  test "falsy values" do
    x = nil

    assertion =
      Assertion.new(
        quote(do: _ <- x),
        x,
        %{locals: [x: x]}
      )

    auto_assert "auto_assert(x == nil)" <-
                  assertion |> Assertion.convert(target: :mneme) |> Sourceror.to_string()

    auto_assert "assert x == nil" <-
                  assertion |> Assertion.convert(target: :ex_unit) |> Sourceror.to_string()
  end
end
