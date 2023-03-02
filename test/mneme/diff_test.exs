defmodule Mneme.DiffTest do
  use ExUnit.Case
  use Mneme

  alias Mneme.Diff

  describe "compute/2" do
    test "should return the semantic diff between ASTs" do
      auto_assert [
                    left: [],
                    right: [{:ins, :"[]", closing: [line: 1, column: 7], line: 1, column: 5}]
                  ] <- Diff.compute("[1, 2]", "[1, [2]]")

      auto_assert [
                    left: [{:del, :"[]", closing: [line: 1, column: 4], line: 1, column: 2}],
                    right: [{:ins, :"[]", closing: [line: 1, column: 7], line: 1, column: 5}]
                  ] <- Diff.compute("[[1], 2]", "[1, [2]]")

      auto_assert [
                    left: [],
                    right: [
                      {:ins, :{}, line: 1, column: 11},
                      {:ins, :bar, line: 1, column: 11},
                      {:ins, 2, line: 1, column: 16}
                    ]
                  ] <- Diff.compute("%{foo: 1}", "%{foo: 1, bar: 2}")

      auto_assert [
                    left: [],
                    right: [
                      {:ins, :%, line: 1, column: 1},
                      {:ins, :__aliases__, line: 1, column: 2},
                      {:ins, :MyStruct, line: 1, column: 2}
                    ]
                  ] <- Diff.compute("%{foo: 1}", "%MyStruct{foo: 1}")

      auto_assert [
                    left: [],
                    right: [{:ins, :"[]", closing: [line: 1, column: 10], line: 1, column: 5}]
                  ] <- Diff.compute("[1, 2, 3]", "[1, [2, 3]]")

      auto_assert [
                    left: [{:del, :is_pid, closing: [line: 1, column: 20], line: 1, column: 10}],
                    right: [
                      {:ins, :is_reference, closing: [line: 1, column: 26], line: 1, column: 10}
                    ]
                  ] <- Diff.compute("foo when is_pid(foo)", "foo when is_reference(foo)")

      auto_assert [
                    left: [],
                    right: [{:ins, :"[]", closing: [line: 1, column: 3], line: 1, column: 1}]
                  ] <- Diff.compute("x", "[x]")

      auto_assert [
                    left: [{:del, :{}, closing: [line: 1, column: 3], line: 1, column: 1}],
                    right: [{:ins, :"[]", closing: [line: 1, column: 3], line: 1, column: 1}]
                  ] <- Diff.compute("{x}", "[x]")

      auto_assert [
                    left: [{:del, :"[]", closing: [line: 1, column: 14], line: 1, column: 9}],
                    right: [{:ins, :"[]", closing: [line: 1, column: 14], line: 1, column: 2}]
                  ] <- Diff.compute("[{{1}}, [2, 3]]", "[[{{1}}, 2, 3]]")

      auto_assert [
                    left: [],
                    right: [
                      {:ins, :"[]", closing: [line: 1, column: 7], line: 1, column: 5},
                      {:ins, 2, line: 1, column: 6}
                    ]
                  ] <- Diff.compute("[1, [3]]", "[1, [2], [3]]")

      auto_assert [
                    left: [{:del, 1, line: 1, column: 8}, {:del, :bar, line: 1, column: 11}],
                    right: [
                      {:ins, :%, line: 1, column: 1},
                      {:ins, :__aliases__, line: 1, column: 2},
                      {:ins, :MyStruct, line: 1, column: 2},
                      {:ins, 2, line: 1, column: 16},
                      {:ins, :baz, line: 1, column: 19}
                    ]
                  ] <- Diff.compute("%{foo: 1, bar: [2]}", "%MyStruct{foo: 2, baz: [2]}")

      auto_assert [
                    left: [
                      {:del, 1, line: 1, column: 8},
                      {:del, :bar, line: 1, column: 11},
                      {:del, :"[]", closing: [line: 1, column: 22], line: 1, column: 20}
                    ],
                    right: [
                      {:ins, :%, line: 1, column: 1},
                      {:ins, :__aliases__, line: 1, column: 2},
                      {:ins, :MyStruct, line: 1, column: 2},
                      {:ins, 2, line: 1, column: 16},
                      {:ins, :baz, line: 1, column: 19}
                    ]
                  ] <-
                    Diff.compute(
                      "%{foo: 1, bar: [2, [3]]}",
                      "%MyStruct{foo: 2, baz: [2, 3]}"
                    )
    end
  end
end
