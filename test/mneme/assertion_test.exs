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
  end

  describe "auto_assert_raise" do
    test "with no message" do
      ast = quote(do: auto_assert_raise(ArgumentError, fn -> :ok end))

      auto_assert [
                    mneme: "auto_assert_raise ArgumentError, fn -> :ok end",
                    ex_unit: "assert_raise ArgumentError, fn -> :ok end",
                    eval: """
                    assert_raise ArgumentError, fn ->
                      raise %{__exception__: true, __struct__: ArgumentError, message: "argument error"}
                    end\
                    """
                  ] <- targets(ast, %ArgumentError{})
    end

    test "with message" do
      ast = quote(do: auto_assert_raise(ArgumentError, "", fn -> :ok end))

      auto_assert [
                    mneme: "auto_assert_raise ArgumentError, \"message\", fn -> :ok end",
                    ex_unit: "assert_raise ArgumentError, \"message\", fn -> :ok end",
                    eval: """
                    assert_raise ArgumentError, "message", fn ->
                      raise %{__exception__: true, __struct__: ArgumentError, message: "message"}
                    end\
                    """
                  ] <- targets(ast, %ArgumentError{message: "message"})
    end

    test "with message containing characters that have to be escaped" do
      ast = quote(do: auto_assert_raise(ArgumentError, "", fn -> :ok end))

      auto_assert [
                    mneme:
                      "auto_assert_raise ArgumentError, \"This \\\"is\\\" a\\nmessage\", fn -> :ok end",
                    ex_unit:
                      "assert_raise ArgumentError, \"This \\\"is\\\" a\\nmessage\", fn -> :ok end",
                    eval: """
                    assert_raise ArgumentError, "This \\"is\\" a\\nmessage", fn ->
                      raise %{__exception__: true, __struct__: ArgumentError, message: "This \\"is\\" a\\nmessage"}
                    end\
                    """
                  ] <- targets(ast, %ArgumentError{message: ~S|This "is" a\nmessage|})
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
      Assertion.new(ast, value, context)
      |> Assertion.put_rich_ast(ast)
      |> Assertion.generate_code(:mneme)

    [
      mneme: assertion.code |> Sourceror.to_string(@format_opts),
      ex_unit: assertion |> Assertion.to_code(:ex_unit) |> Sourceror.to_string(@format_opts),
      eval: assertion |> Assertion.code_for_eval() |> Sourceror.to_string(@format_opts)
    ]
  end
end
