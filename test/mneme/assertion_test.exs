defmodule Mneme.AssertionTest do
  use ExUnit.Case, async: true
  use Mneme
  alias Mneme.Assertion

  @format_opts Mneme.Utils.formatter_opts()

  test "w/o guard" do
    assertion = new_assertion(quote(do: auto_assert([1, 2, 3] <- [1, 2, 3])), [1, 2, 3])

    auto_assert "auto_assert [1, 2, 3] <- [1, 2, 3]" <- to_code_string(assertion, :mneme)

    auto_assert "assert [1, 2, 3] = [1, 2, 3]" <- to_code_string(assertion, :ex_unit)

    auto_assert "assert [1, 2, 3] = value" <- to_code_string(assertion, :eval)
  end

  test "w/ guard" do
    me = self()
    assertion = new_assertion(quote(do: auto_assert(pid when is_pid(pid) <- me)), me)

    auto_assert "auto_assert pid when is_pid(pid) <- me" <- to_code_string(assertion, :mneme)

    auto_assert """
                assert pid = me
                assert is_pid(pid)\
                """ <- to_code_string(assertion, :ex_unit)

    auto_assert """
                value = assert pid = value
                assert is_pid(pid)
                value\
                """ <- to_code_string(assertion, :eval)
  end

  test "falsy values" do
    x = nil
    assertion = new_assertion(quote(do: auto_assert(_ <- x)), x)

    auto_assert "auto_assert x == nil" <- to_code_string(assertion, :mneme)

    auto_assert "assert x == nil" <- to_code_string(assertion, :ex_unit)

    auto_assert "assert nil == value" <- to_code_string(assertion, :eval)
  end

  defp new_assertion(ast, value, context \\ %{}) do
    Assertion.new(ast, value, context)
    |> Assertion.put_rich_ast(ast)
    |> Assertion.generate_code(:mneme)
  end

  defp to_code_string(assertion, :eval) do
    assertion |> Assertion.code_for_eval() |> Sourceror.to_string(@format_opts)
  end

  defp to_code_string(assertion, target) do
    assertion |> Assertion.to_code(target) |> Sourceror.to_string(@format_opts)
  end
end
