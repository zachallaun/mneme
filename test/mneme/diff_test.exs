defmodule Mneme.DiffTest do
  use ExUnit.Case
  use Mneme, default_pattern: :last

  alias Mneme.Diff
  alias Owl.Tag, warn: false

  describe "format/2" do
    test "formats list insertions" do
      left = "[1, 2_000]"
      right = "[1, [2_000]]"
      {_deletions, insertions} = Diff.compute(left, right)

      auto_assert [
                    "[1, ",
                    %Tag{data: "[", sequences: [:green]},
                    "2_000",
                    %Tag{data: "]", sequences: [:green]},
                    "]"
                  ] <- Diff.format(right, insertions)
    end

    test "formats integer insertions" do
      left = "[1]"
      right = "[1, 2_000]"
      {_, insertions} = Diff.compute(left, right)

      auto_assert ["[1, ", %Tag{data: "2_000", sequences: [:green]}, "]"] <-
                    Diff.format(right, insertions)
    end
  end

  describe "compute/2" do
    test "should return the semantic diff between ASTs" do
      auto_assert {[], [{:ins, :"[]", %{closing: %{column: 7, line: 1}, column: 5, line: 1}}]} <-
                    Diff.compute("[1, 2]", "[1, [2]]")

      auto_assert {[{:del, :"[]", %{closing: %{column: 4, line: 1}, column: 2, line: 1}}],
                   [{:ins, :"[]", %{closing: %{column: 7, line: 1}, column: 5, line: 1}}]} <-
                    Diff.compute("[[1], 2]", "[1, [2]]")

      auto_assert {[],
                   [
                     {:ins, :{}, %{column: 11, format: :keyword, line: 1}},
                     {:ins, {:atom, :bar}, %{column: 11, format: :keyword, line: 1}},
                     {:ins, {:int, 2}, %{column: 16, line: 1, token: "2"}}
                   ]} <- Diff.compute("%{foo: 1}", "%{foo: 1, bar: 2}")

      auto_assert {[],
                   [
                     {:ins, :%, %{column: 1, line: 1}},
                     {:ins, :__aliases__, %{column: 2, last: [line: 1, column: 2], line: 1}},
                     {:ins, {:atom, :MyStruct}, %{column: 2, line: 1}}
                   ]} <- Diff.compute("%{foo: 1}", "%MyStruct{foo: 1}")

      auto_assert {[], [{:ins, :"[]", %{closing: %{column: 10, line: 1}, column: 5, line: 1}}]} <-
                    Diff.compute("[1, 2, 3]", "[1, [2, 3]]")

      auto_assert {[{:del, :is_pid, %{closing: %{column: 20, line: 1}, column: 10, line: 1}}],
                   [
                     {:ins, :is_reference,
                      %{closing: %{column: 26, line: 1}, column: 10, line: 1}}
                   ]} <- Diff.compute("foo when is_pid(foo)", "foo when is_reference(foo)")

      auto_assert {[], [{:ins, :"[]", %{closing: %{column: 3, line: 1}, column: 1, line: 1}}]} <-
                    Diff.compute("x", "[x]")

      auto_assert {[{:del, :{}, %{closing: %{column: 3, line: 1}, column: 1, line: 1}}],
                   [{:ins, :"[]", %{closing: %{column: 3, line: 1}, column: 1, line: 1}}]} <-
                    Diff.compute("{x}", "[x]")

      auto_assert {[{:del, :"[]", %{closing: %{column: 14, line: 1}, column: 9, line: 1}}],
                   [{:ins, :"[]", %{closing: %{column: 14, line: 1}, column: 2, line: 1}}]} <-
                    Diff.compute("[{{1}}, [2, 3]]", "[[{{1}}, 2, 3]]")

      auto_assert {[],
                   [
                     {:ins, :"[]", %{closing: %{column: 7, line: 1}, column: 5, line: 1}},
                     {:ins, {:int, 2}, %{column: 6, line: 1, token: "2"}}
                   ]} <- Diff.compute("[1, [3]]", "[1, [2], [3]]")

      auto_assert {[
                     {:del, {:int, 1}, %{column: 8, line: 1, token: "1"}},
                     {:del, {:atom, :bar}, %{column: 11, format: :keyword, line: 1}}
                   ],
                   [
                     {:ins, :%, %{column: 1, line: 1}},
                     {:ins, :__aliases__, %{column: 2, last: [line: 1, column: 2], line: 1}},
                     {:ins, {:atom, :MyStruct}, %{column: 2, line: 1}},
                     {:ins, {:int, 2}, %{column: 16, line: 1, token: "2"}},
                     {:ins, {:atom, :baz}, %{column: 19, format: :keyword, line: 1}}
                   ]} <- Diff.compute("%{foo: 1, bar: [2]}", "%MyStruct{foo: 2, baz: [2]}")

      auto_assert {[
                     {:del, {:int, 1}, %{column: 8, line: 1, token: "1"}},
                     {:del, {:atom, :bar}, %{column: 11, format: :keyword, line: 1}},
                     {:del, :"[]", %{closing: %{column: 22, line: 1}, column: 20, line: 1}}
                   ],
                   [
                     {:ins, :%, %{column: 1, line: 1}},
                     {:ins, :__aliases__, %{column: 2, last: [line: 1, column: 2], line: 1}},
                     {:ins, {:atom, :MyStruct}, %{column: 2, line: 1}},
                     {:ins, {:int, 2}, %{column: 16, line: 1, token: "2"}},
                     {:ins, {:atom, :baz}, %{column: 19, format: :keyword, line: 1}}
                   ]} <-
                    Diff.compute(
                      "%{foo: 1, bar: [2, [3]]}",
                      "%MyStruct{foo: 2, baz: [2, 3]}"
                    )
    end
  end
end
