defmodule Mneme.AssertionTest do
  use ExUnit.Case, async: true
  use Mneme

  alias Mneme.Assertion

  {_formatter, opts} = Mix.Tasks.Format.formatter_for_file(__ENV__.file)
  @format_opts opts

  describe "auto_assert" do
    test "w/o guard" do
      ast = quote(do: auto_assert([1, 2, 3] <- [1 | [2, 3]]))

      auto_assert [
                    mneme: "auto_assert [1, 2, 3] <- [1 | [2, 3]]",
                    ex_unit: "assert [1, 2, 3] = [1 | [2, 3]]",
                    eval: "assert [1, 2, 3] = value"
                  ] <- targets(ast, [1, 2, 3])
    end

    test "w/ guard" do
      ast = quote(do: auto_assert(pid when is_pid(pid) <- me))

      auto_assert [
                    mneme: "auto_assert pid when is_pid(pid) <- me",
                    ex_unit: """
                    assert pid = me
                    assert is_pid(pid)\
                    """,
                    eval: """
                    value = assert pid = value
                    assert is_pid(pid)
                    value\
                    """
                  ] <- targets(ast, self())
    end

    test "falsy values" do
      ast = quote(do: auto_assert(_ <- x))

      auto_assert [
                    mneme: "auto_assert nil <- x",
                    ex_unit: "assert x == nil",
                    eval: "assert nil == value"
                  ] <- targets(ast, nil)
    end

    test "should infer a default pattern closest to the original ast" do
      value = %{foo: 1, bar: 2, baz: 3}
      value_ast = {:%{}, [], [bar: 2, baz: 3, foo: 1]}

      ast1 = quote(do: auto_assert(%{foo: 1} <- unquote(value_ast)))

      auto_assert [
                    mneme: "auto_assert %{foo: 1} <- %{bar: 2, baz: 3, foo: 1}",
                    ex_unit: "assert %{foo: 1} = %{bar: 2, baz: 3, foo: 1}",
                    eval: "assert %{foo: 1} = value"
                  ] <- targets(ast1, value)

      ast2 = quote(do: auto_assert(%{foo: 1} <- unquote(value_ast)))

      auto_assert [
                    mneme: "auto_assert %{foo: 1} <- %{bar: 2, baz: 3, foo: 1}",
                    ex_unit: "assert %{foo: 1} = %{bar: 2, baz: 3, foo: 1}",
                    eval: "assert %{foo: 1} = value"
                  ] <- targets(ast2, value)

      ast3 = quote(do: auto_assert(%{other: :key, and: :value} <- unquote(value_ast)))

      auto_assert [
                    mneme: "auto_assert %{bar: 2, baz: 3, foo: 1} <- %{bar: 2, baz: 3, foo: 1}",
                    ex_unit: "assert %{bar: 2, baz: 3, foo: 1} = %{bar: 2, baz: 3, foo: 1}",
                    eval: "assert %{bar: 2, baz: 3, foo: 1} = value"
                  ] <- targets(ast3, value)
    end

    test "exposing variables from match LHO" do
      value = 42

      ast = quote(do: auto_assert(foo <- 42))

      auto_assert [
                    mneme: "auto_assert 42 <- 42",
                    ex_unit: "assert 42 = 42",
                    eval: "assert 42 = value"
                  ] <- targets(ast, value)

      auto_assert foo <- 42
      auto_assert 42 <- foo
      auto_assert [1] ++ foo <- [1, 2, 3]
      auto_assert [2, 3] <- foo
      auto_assert <<foo::binary-size(3), _::binary>> <- "abc def"
      auto_assert "abc" <- foo
      auto_assert ^foo <> " " <> foo <- "abc def"
      auto_assert "def" <- foo
      pinned = [3]
      auto_assert list when is_list(list) and length(list) == 3 <- [1, 2, 3]
      auto_assert [1, 2 | ^pinned] <- list
      result = auto_assert {e1, e2, e3} <- {1, 2, 3}
      auto_assert {1, 2, 3} <- result
      IO.inspect(result: result, e1: e1, e2: e2, e3: e3)

      auto_assert %{x: x, y: 2} <- %{x: 1, y: 2}
      auto_assert 1 <- x

      # auto_assert %{y: ^e1} <- %{y: 1}
      # auto_assert %{x: nil} <- Map.put(%{}, :x, x)
      # IO.inspect(x: x)
    end
  end

  describe "auto_assert_raise" do
    test "with no message" do
      ast = quote(do: auto_assert_raise(ArgumentError, fn -> :ok end))

      auto_assert [
                    mneme: "auto_assert_raise ArgumentError, fn -> :ok end",
                    ex_unit: "assert_raise ArgumentError, fn -> :ok end",
                    eval:
                      "assert_raise ArgumentError, fn -> raise %ArgumentError{message: \"argument error\"} end"
                  ] <- targets(ast, %ArgumentError{})
    end

    test "with message" do
      ast = quote(do: auto_assert_raise(ArgumentError, "", fn -> :ok end))

      auto_assert [
                    mneme: "auto_assert_raise ArgumentError, \"message\", fn -> :ok end",
                    ex_unit: "assert_raise ArgumentError, \"message\", fn -> :ok end",
                    eval:
                      "assert_raise ArgumentError, \"message\", fn -> raise %ArgumentError{message: \"message\"} end"
                  ] <- targets(ast, %ArgumentError{message: "message"})
    end

    test "with message containing characters that have to be escaped" do
      ast = quote(do: auto_assert_raise(ArgumentError, "", fn -> :ok end))

      auto_assert [
                    mneme:
                      "auto_assert_raise ArgumentError, \"This \\\"is\\\" a\\\\nmessage\", fn -> :ok end",
                    ex_unit:
                      "assert_raise ArgumentError, \"This \\\"is\\\" a\\nmessage\", fn -> :ok end",
                    eval: """
                    assert_raise ArgumentError, "This \\"is\\" a\\nmessage", fn ->
                      raise %ArgumentError{message: "This \\"is\\" a\\nmessage"}
                    end\
                    """
                  ] <- targets(ast, %ArgumentError{message: ~S|This "is" a\nmessage|})
    end

    test "with multi-line message" do
      ast = quote(do: auto_assert_raise(ArgumentError, "", fn -> :ok end))

      auto_assert [
                    mneme:
                      "auto_assert_raise ArgumentError, \"foo\\nbar\\nbaz\\n\", fn -> :ok end",
                    ex_unit: "assert_raise ArgumentError, \"foo\\nbar\\nbaz\\n\", fn -> :ok end",
                    eval:
                      "assert_raise ArgumentError, \"foo\nbar\nbaz\n\", fn -> raise %ArgumentError{message: \"foo\nbar\nbaz\n\"} end"
                  ] <- targets(ast, %ArgumentError{message: "foo\nbar\nbaz\n"})
    end
  end

  describe "auto_assert_receive" do
    test "without arguments" do
      ast = quote(do: auto_assert_receive())
      inbox = [{:message, "data"}]

      auto_assert [
                    mneme: "auto_assert_receive {:message, \"data\"}",
                    ex_unit: "assert_receive {:message, \"data\"}",
                    eval: "assert_receive {:message, \"data\"}, 0"
                  ] <- targets(ast, inbox)
    end

    test "without arguments, with a guard" do
      ast = quote(do: auto_assert_receive())
      inbox = [{:from, self()}]

      auto_assert [
                    mneme: "auto_assert_receive {:from, pid} when is_pid(pid)",
                    ex_unit: "assert_receive {:from, pid} when is_pid(pid)",
                    eval: "assert_receive {:from, pid} when is_pid(pid), 0"
                  ] <- targets(ast, inbox)
    end

    test "with existing pattern" do
      ast = quote(do: auto_assert_receive({:some, :message}))
      inbox = [{:other, :message}]

      auto_assert [
                    mneme: "auto_assert_receive {:other, :message}",
                    ex_unit: "assert_receive {:other, :message}",
                    eval: "assert_receive {:other, :message}, 0"
                  ] <- targets(ast, inbox)
    end

    test "with existing pattern, with a guard" do
      ast = quote(do: auto_assert_receive({:some, :message}))
      inbox = [{:from, self()}]

      auto_assert [
                    mneme: "auto_assert_receive {:from, pid} when is_pid(pid)",
                    ex_unit: "assert_receive {:from, pid} when is_pid(pid)",
                    eval: "assert_receive {:from, pid} when is_pid(pid), 0"
                  ] <- targets(ast, inbox)
    end

    test "with existing pattern and timeout" do
      ast = quote(do: auto_assert_receive({:some, :message}, 200))
      inbox = [{:other, :message}]

      auto_assert [
                    mneme: "auto_assert_receive {:other, :message}, 200",
                    ex_unit: "assert_receive {:other, :message}, 200",
                    eval: "assert_receive {:other, :message}, 0"
                  ] <- targets(ast, inbox)
    end
  end

  describe "auto_assert_received" do
    test "without arguments" do
      ast = quote(do: auto_assert_received())
      inbox = [{:message, "data"}]

      auto_assert [
                    mneme: "auto_assert_received {:message, \"data\"}",
                    ex_unit: "assert_received {:message, \"data\"}",
                    eval: "assert_received {:message, \"data\"}"
                  ] <- targets(ast, inbox)
    end

    test "without arguments, with a guard" do
      ast = quote(do: auto_assert_received())
      inbox = [{:from, self()}]

      auto_assert [
                    mneme: "auto_assert_received {:from, pid} when is_pid(pid)",
                    ex_unit: "assert_received {:from, pid} when is_pid(pid)",
                    eval: "assert_received {:from, pid} when is_pid(pid)"
                  ] <- targets(ast, inbox)
    end

    test "with existing pattern" do
      ast = quote(do: auto_assert_received({:some, :message}))
      inbox = [{:other, :message}]

      auto_assert [
                    mneme: "auto_assert_received {:other, :message}",
                    ex_unit: "assert_received {:other, :message}",
                    eval: "assert_received {:other, :message}"
                  ] <- targets(ast, inbox)
    end

    test "with existing pattern, with a guard" do
      ast = quote(do: auto_assert_received({:some, :message}))
      inbox = [{:from, self()}]

      auto_assert [
                    mneme: "auto_assert_received {:from, pid} when is_pid(pid)",
                    ex_unit: "assert_received {:from, pid} when is_pid(pid)",
                    eval: "assert_received {:from, pid} when is_pid(pid)"
                  ] <- targets(ast, inbox)
    end
  end

  defp targets(ast, value, context \\ %{}) do
    assertion =
      ast
      |> Assertion.new(value, context)
      |> Assertion.prepare_for_patch(ast)

    ex_unit_assertion =
      Assertion.prepare_for_patch(%{
        assertion
        | options: Map.put(assertion.options, :target, :ex_unit)
      })

    [
      mneme: Sourceror.to_string(assertion.code, @format_opts),
      ex_unit: Sourceror.to_string(ex_unit_assertion.code, @format_opts),
      eval: assertion |> Assertion.code_for_eval() |> Sourceror.to_string(@format_opts)
    ]
  end
end
