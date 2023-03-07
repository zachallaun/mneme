defmodule Mneme.DiffTest do
  use ExUnit.Case
  use Mneme, default_pattern: :last

  alias Mneme.Diff
  alias Owl.Tag, warn: false

  describe "format/2" do
    test "formats list insertions" do
      auto_assert {nil,
                   [
                     [
                       "[1, ",
                       %Tag{data: "[", sequences: [:green]},
                       "2_000",
                       %Tag{data: "]", sequences: [:green]},
                       "]"
                     ]
                   ]} <- format("[1, 2_000]", "[1, [2_000]]")

      auto_assert {nil, [["[", %Tag{data: ":foo", sequences: [:green]}, "]"]]} <-
                    format("[]", "[:foo]")
    end

    test "formats strings" do
      auto_assert {[["", %Tag{data: "\"foo\"", sequences: [:red]}, ""]],
                   [["", %Tag{data: "\"bar\"", sequences: [:green]}, ""]]} <-
                    format(~s("foo"), ~s("bar"))

      auto_assert {[
                     ["", %Tag{data: "\"\"\"", sequences: [:red]}, ""],
                     %Tag{data: "foo", sequences: [:red]},
                     %Tag{data: "bar", sequences: [:red]},
                     [%Tag{data: "\"\"\"", sequences: [:red]}, ""],
                     [[]]
                   ],
                   [
                     ["", %Tag{data: "\"\"\"", sequences: [:green]}, ""],
                     %Tag{data: "baz", sequences: [:green]},
                     [%Tag{data: "\"\"\"", sequences: [:green]}, ""],
                     [[]]
                   ]} <-
                    format(
                      """
                      \"""
                      foo
                      bar
                      \"""
                      """,
                      """
                      \"""
                      baz
                      \"""
                      """
                    )
    end

    test "formats integer insertions" do
      auto_assert {nil, [["[1, ", %Tag{data: "2_000", sequences: [:green]}, "]"]]} <-
                    format("[1]", "[1, 2_000]")
    end

    test "formats over multiple lines" do
      auto_assert {nil,
                   ["[", "  1,", ["  ", %Tag{data: "2_000", sequences: [:green]}, ""], ["]"]]} <-
                    format("[\n  1\n]", "[\n  1,\n  2_000\n]")
    end

    test "formats tuple to list" do
      auto_assert {[
                     [
                       "",
                       %Tag{data: "{", sequences: [:red]},
                       "1, 2",
                       %Tag{data: "}", sequences: [:red]},
                       ""
                     ]
                   ],
                   [
                     [
                       "",
                       %Tag{data: "[", sequences: [:green]},
                       "1, 2",
                       %Tag{data: "]", sequences: [:green]},
                       ""
                     ]
                   ]} <- format("{1, 2}", "[1, 2]")
    end

    test "formats map to kw" do
      auto_assert {[
                     [
                       "",
                       %Tag{data: "%{", sequences: [:red]},
                       "foo: 1",
                       %Tag{data: "}", sequences: [:red]},
                       ""
                     ]
                   ],
                   [
                     [
                       "",
                       %Tag{data: "[", sequences: [:green]},
                       "foo: 1",
                       %Tag{data: "]", sequences: [:green]},
                       ""
                     ]
                   ]} <- format("%{foo: 1}", "[foo: 1]")
    end

    test "formats map key insertion" do
      auto_assert {nil, [["%{foo: 1, ", %Tag{data: "bar: 2", sequences: [:green]}, "}"]]} <-
                    format("%{foo: 1}", "%{foo: 1, bar: 2}")

      auto_assert {nil,
                   [
                     [
                       "%{:foo => 1, ",
                       %Tag{data: "2 => :bar", sequences: [:green]},
                       ", :baz => 3}"
                     ]
                   ]} <- format("%{foo: 1, baz: 3}", "%{:foo => 1, 2 => :bar, :baz => 3}")
    end

    test "formats entire collections" do
      auto_assert {nil, [["[x, ", %Tag{data: "[y, z]", sequences: [:green]}, "]"]]} <-
                    format("[x]", "[x, [y, z]]")

      auto_assert {nil, [["[x, ", %Tag{data: "%{y: 1}", sequences: [:green]}, "]"]]} <-
                    format("[x]", "[x, %{y: 1}]")

      auto_assert {nil, [["[x, ", %Tag{data: "%{:y => 1}", sequences: [:green]}, "]"]]} <-
                    format("[x]", "[x, %{:y => 1}]")

      auto_assert {nil, [["[x, ", %Tag{data: "%MyStruct{foo: 1}", sequences: [:green]}, "]"]]} <-
                    format("[x]", "[x, %MyStruct{foo: 1}]")

      auto_assert {[
                     ["", %Tag{data: "[", sequences: [:red]}],
                     %Tag{data: "  foo: 1,", sequences: [:red]},
                     %Tag{data: "  bar: 2", sequences: [:red]},
                     [%Tag{data: "]", sequences: [:red]}, ""],
                     [[]]
                   ],
                   [
                     ["", %Tag{data: "%{", sequences: [:green]}],
                     %Tag{data: "  baz: 3,", sequences: [:green]},
                     %Tag{data: "  buzz: 4", sequences: [:green]},
                     [%Tag{data: "}", sequences: [:green]}, ""],
                     [[]]
                   ]} <-
                    format(
                      """
                      [
                        foo: 1,
                        bar: 2
                      ]
                      """,
                      """
                      %{
                        baz: 3,
                        buzz: 4
                      }
                      """
                    )
    end

    test "formats map to struct" do
      auto_assert {nil, [["%", %Tag{data: "MyStruct", sequences: [:green]}, "{foo: 1}"]]} <-
                    format("%{foo: 1}", "%MyStruct{foo: 1}")

      auto_assert {[["%", %Tag{data: "MyStruct", sequences: [:red]}, "{foo: 1}"]], nil} <-
                    format("%MyStruct{foo: 1}", "%{foo: 1}")

      auto_assert {[
                     "%{",
                     "  foo: 1,",
                     ["  ", %Tag{data: "bar:", sequences: [:red]}, " 2"],
                     ["}"],
                     [[]]
                   ],
                   [
                     ["%", %Tag{data: "MyStruct", sequences: [:green]}, "{"],
                     ["  foo: 1,"],
                     ["  ", %Tag{data: "baz:", sequences: [:green]}, " 2"],
                     ["}"],
                     [[]]
                   ]} <-
                    format(
                      """
                      %{
                        foo: 1,
                        bar: 2
                      }
                      """,
                      """
                      %MyStruct{
                        foo: 1,
                        baz: 2
                      }
                      """
                    )
    end

    test "formats calls without parens" do
      auto_assert {nil,
                   [
                     [
                       "auto_assert :foo ",
                       %Tag{data: "<-", sequences: [:green]},
                       " ",
                       %Tag{data: ":foo", sequences: [:green]},
                       ""
                     ]
                   ]} <- format("auto_assert :foo", "auto_assert :foo <- :foo")

      auto_assert {[
                     [
                       "",
                       %Tag{data: "auto_assert", sequences: [:red]},
                       " Function.identity(false)"
                     ]
                   ],
                   [
                     [
                       "",
                       %Tag{data: "auto_refute", sequences: [:green]},
                       " Function.identity(false)"
                     ]
                   ]} <-
                    format(
                      "auto_assert Function.identity(false)",
                      "auto_refute Function.identity(false)"
                    )
    end

    test "formats calls with parens" do
      auto_assert {nil,
                   [
                     [
                       "",
                       %Tag{data: "foo(", sequences: [:green]},
                       "x",
                       %Tag{data: ")", sequences: [:green]},
                       ""
                     ]
                   ]} <- format("x", "foo(x)")
    end

    test "formats pins" do
      auto_assert {nil,
                   [
                     [
                       "auto_assert ",
                       %Tag{data: "^me", sequences: [:green]},
                       " ",
                       %Tag{data: "<-", sequences: [:green]},
                       " me"
                     ]
                   ]} <- format("auto_assert me", "auto_assert ^me <- me")

      auto_assert {nil,
                   [
                     [
                       "",
                       %Tag{data: "^foo(me)", sequences: [:green]},
                       " ",
                       %Tag{data: "<-", sequences: [:green]},
                       " me"
                     ]
                   ]} <- format("me", "^foo(me) <- me")
    end

    defp format(left, right) do
      case Diff.compute(left, right) do
        {[], []} ->
          {nil, nil}

        {[], insertions} ->
          {nil, Diff.format_lines(right, insertions)}

        {deletions, []} ->
          {Diff.format_lines(left, deletions), nil}

        {deletions, insertions} ->
          {Diff.format_lines(left, deletions), Diff.format_lines(right, insertions)}
      end
    end
  end
end
