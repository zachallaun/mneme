defmodule Mneme.DiffTest do
  use ExUnit.Case, async: true
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

    test "formats term reordering" do
      auto_assert {[["[:foo, ", %Tag{data: ":bar", sequences: [:red]}, ", :baz]"]],
                   [["[", %Tag{data: ":bar", sequences: [:green]}, ", :foo, :baz]"]]} <-
                    format("[:foo, :bar, :baz]", "[:bar, :foo, :baz]")
    end

    test "formats term renesting" do
      auto_assert {[["[[", %Tag{data: ":bar", sequences: [:red]}, "]]"]],
                   [["[[], ", %Tag{data: ":bar", sequences: [:green]}, "]"]]} <-
                    format("[[:bar]]", "[[], :bar]")

      auto_assert {[["[[:foo, ", %Tag{data: ":bar", sequences: [:red]}, "]]"]],
                   [["[[:foo], ", %Tag{data: ":bar", sequences: [:green]}, "]"]]} <-
                    format("[[:foo, :bar]]", "[[:foo], :bar]")

      auto_assert {[
                     [
                       "{:foo, %",
                       %Tag{data: "MyStruct", sequences: [:red]},
                       "{",
                       %Tag{data: "hmm:", sequences: [:red]},
                       " ",
                       %Tag{data: "[", sequences: [:red]},
                       %Tag{data: ":bar", sequences: [:red]},
                       ", {:some, :thing}",
                       %Tag{data: "]", sequences: [:red]},
                       "}}"
                     ]
                   ],
                   [["{:foo, %{", %Tag{data: "cool:", sequences: [:green]}, " {:some, :thing}}}"]]} <-
                    format(
                      "{:foo, %MyStruct{hmm: [:bar, {:some, :thing}]}}",
                      "{:foo, %{cool: {:some, :thing}}}"
                    )
    end

    test "formats strings" do
      auto_assert {[[%Tag{data: "\"foo\"", sequences: [:red]}]],
                   [[%Tag{data: "\"bar\"", sequences: [:green]}]]} <- format(~s("foo"), ~s("bar"))

      auto_assert {[
                     [%Tag{data: "\"\"\"", sequences: [:red]}],
                     %Tag{data: "foo", sequences: [:red]},
                     %Tag{data: "bar", sequences: [:red]},
                     [%Tag{data: "\"\"\"", sequences: [:red]}],
                     []
                   ],
                   [
                     [%Tag{data: "\"\"\"", sequences: [:green]}],
                     %Tag{data: "baz", sequences: [:green]},
                     [%Tag{data: "\"\"\"", sequences: [:green]}],
                     []
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

      auto_assert {[["[", %Tag{data: "\"foo\"", sequences: [:red]}, "]"]],
                   [["[", %Tag{data: "\"bar\"", sequences: [:green]}, "]"]]} <-
                    format(~s(["foo"]), ~s(["bar"]))
    end

    test "formats strings using myers diff when they are similar" do
      auto_assert {[["\"fooba", %Tag{data: "r", sequences: [:red]}, "\""]],
                   [["\"fooba", %Tag{data: "z", sequences: [:green]}, "\""]]} <-
                    format(~s("foobar"), ~s("foobaz"))

      auto_assert {[
                     [
                       "\"fo",
                       %Tag{data: "o", sequences: [:red]},
                       "ba",
                       %Tag{data: "r", sequences: [:red]},
                       "\""
                     ]
                   ],
                   [
                     [
                       "\"fo",
                       %Tag{data: "a", sequences: [:green]},
                       "ba",
                       %Tag{data: "z", sequences: [:green]},
                       "\""
                     ]
                   ]} <- format(~s("foobar"), ~s("foabaz"))

      auto_assert {[["\"f", %Tag{data: "oo", sequences: [:red]}, " bar\""]],
                   [
                     [
                       "\"f",
                       %Tag{data: "a", sequences: [:green]},
                       " ",
                       %Tag{data: "o", sequences: [:green]},
                       "bar",
                       %Tag{data: " ", sequences: [:green_background]},
                       "\""
                     ]
                   ]} <- format(~s("foo bar"), ~s("fa obar "))

      auto_assert {[
                     "\"\"\"",
                     [
                       %Tag{data: "f", sequences: [:red]},
                       "o",
                       %Tag{data: "o", sequences: [:red]}
                     ],
                     ["ba", %Tag{data: "r", sequences: [:red]}],
                     ["\"\"\""]
                   ],
                   [
                     "\"\"\"",
                     [
                       %Tag{data: "s", sequences: [:green]},
                       "o",
                       %Tag{data: "a", sequences: [:green]},
                       %Tag{data: " ", sequences: [:green_background]}
                     ],
                     ["ba", %Tag{data: "z", sequences: [:green]}],
                     ["\"\"\""]
                   ]} <- format(~s("""\nfoo\nbar\n"""), ~s("""\nsoa \nbaz\n"""))

      auto_assert {[
                     "\"\"\"",
                     [
                       "  ",
                       %Tag{data: "f", sequences: [:red]},
                       "o",
                       %Tag{data: "o", sequences: [:red]}
                     ],
                     ["  ba", %Tag{data: "r", sequences: [:red]}],
                     ["  \"\"\""]
                   ],
                   [
                     "\"\"\"",
                     [
                       "  ",
                       %Tag{data: "s", sequences: [:green]},
                       "o",
                       %Tag{data: "a", sequences: [:green]},
                       %Tag{data: " ", sequences: [:green_background]}
                     ],
                     ["  ba", %Tag{data: "z", sequences: [:green]}],
                     ["  \"\"\""]
                   ]} <- format(~s("""\n  foo\n  bar\n  """), ~s("""\n  soa \n  baz\n  """))
    end

    test "formats charlists" do
      auto_assert {nil, [["[", %Tag{data: "~c(foo)", sequences: [:green]}, "]"]]} <-
                    format("[]", "[~c(foo)]")

      auto_assert {nil, [["[", %Tag{data: "'foo'", sequences: [:green]}, "]"]]} <-
                    format("[]", "['foo']")
    end

    test "formats integer insertions" do
      auto_assert {nil, [["[1, ", %Tag{data: "2_000", sequences: [:green]}, "]"]]} <-
                    format("[1]", "[1, 2_000]")
    end

    test "formats over multiple lines" do
      auto_assert {nil, ["[", "  1,", ["  ", %Tag{data: "2_000", sequences: [:green]}], ["]"]]} <-
                    format("[\n  1\n]", "[\n  1,\n  2_000\n]")
    end

    test "formats tuple to list" do
      auto_assert {[
                     [
                       %Tag{data: "{", sequences: [:red]},
                       "1, 2",
                       %Tag{data: "}", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "[", sequences: [:green]},
                       "1, 2",
                       %Tag{data: "]", sequences: [:green]}
                     ]
                   ]} <- format("{1, 2}", "[1, 2]")
    end

    test "formats map to kw" do
      auto_assert {[
                     [
                       %Tag{data: "%{", sequences: [:red]},
                       "foo: 1",
                       %Tag{data: "}", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "[", sequences: [:green]},
                       "foo: 1",
                       %Tag{data: "]", sequences: [:green]}
                     ]
                   ]} <- format("%{foo: 1}", "[foo: 1]")
    end

    test "formats map key insertion" do
      auto_assert {nil,
                   [
                     [
                       "%{:foo => 1, ",
                       %Tag{data: "2 => :bar", sequences: [:green]},
                       ", :baz => 3}"
                     ]
                   ]} <- format("%{foo: 1, baz: 3}", "%{:foo => 1, 2 => :bar, :baz => 3}")

      auto_assert {nil, [["%{foo: 1, ", %Tag{data: "bar: 2", sequences: [:green]}, "}"]]} <-
                    format("%{foo: 1}", "%{foo: 1, bar: 2}")
    end

    test "formats entire collections" do
      auto_assert {nil,
                   [
                     [
                       "[a, ",
                       %Tag{data: "[y, z]", sequences: [:green]},
                       ", ",
                       %Tag{data: "[:foo, :bar]", sequences: [:green]},
                       ", ",
                       %Tag{data: "[:baz]", sequences: [:green]},
                       "]"
                     ]
                   ]} <- format("[a]", "[a, [y, z], [:foo, :bar], [:baz]]")

      auto_assert {nil, [["[x, ", %Tag{data: "%{y: 1}", sequences: [:green]}, "]"]]} <-
                    format("[x]", "[x, %{y: 1}]")

      auto_assert {nil, [["[x, ", %Tag{data: "%{:y => 1}", sequences: [:green]}, "]"]]} <-
                    format("[x]", "[x, %{:y => 1}]")

      auto_assert {nil, [["[x, ", %Tag{data: "%MyStruct{foo: 1}", sequences: [:green]}, "]"]]} <-
                    format("[x]", "[x, %MyStruct{foo: 1}]")

      auto_assert {[
                     [%Tag{data: "[", sequences: [:red]}],
                     %Tag{data: "  foo: 1,", sequences: [:red]},
                     %Tag{data: "  bar: 2", sequences: [:red]},
                     [%Tag{data: "]", sequences: [:red]}],
                     []
                   ],
                   [
                     [%Tag{data: "%{", sequences: [:green]}],
                     %Tag{data: "  baz: 3,", sequences: [:green]},
                     %Tag{data: "  buzz: 4", sequences: [:green]},
                     [%Tag{data: "}", sequences: [:green]}],
                     []
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
      auto_assert {nil, [["%", %Tag{data: "MyStruct", sequences: [:green]}, "{bar: 1}"]]} <-
                    format("%{bar: 1}", "%MyStruct{bar: 1}")

      auto_assert {[["%", %Tag{data: "MyStruct", sequences: [:red]}, "{foo: 1}"]], nil} <-
                    format("%MyStruct{foo: 1}", "%{foo: 1}")

      auto_assert {[
                     "%{",
                     "  foo: 1,",
                     ["  ", %Tag{data: "bar:", sequences: [:red]}, " 2"],
                     ["}"],
                     []
                   ],
                   [
                     ["%", %Tag{data: "MyStruct", sequences: [:green]}, "{"],
                     ["  foo: 1,"],
                     ["  ", %Tag{data: "baz:", sequences: [:green]}, " 2"],
                     ["}"],
                     []
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

    test "formats aliases" do
      auto_assert {[["Foo.", %Tag{data: "Bar.", sequences: [:red]}, "Baz"]],
                   [["Foo.", %Tag{data: "Buzz.", sequences: [:green]}, "Baz"]]} <-
                    format("Foo.Bar.Baz", "Foo.Buzz.Baz")

      auto_assert {nil, [["Foo.Bar", %Tag{data: ".Baz", sequences: [:green]}]]} <-
                    format("Foo.Bar", "Foo.Bar.Baz")

      auto_assert {nil, [[%Tag{data: "Foo.", sequences: [:green]}, "Bar.Baz"]]} <-
                    format("Bar.Baz", "Foo.Bar.Baz")
    end

    test "formats calls without parens" do
      auto_assert {nil,
                   [
                     [
                       "auto_assert :foo ",
                       %Tag{data: "<-", sequences: [:green]},
                       " ",
                       %Tag{data: ":foo", sequences: [:green]}
                     ]
                   ]} <- format("auto_assert :foo", "auto_assert :foo <- :foo")

      auto_assert {[[%Tag{data: "auto_assert", sequences: [:red]}, " Function.identity(false)"]],
                   [[%Tag{data: "auto_refute", sequences: [:green]}, " Function.identity(false)"]]} <-
                    format(
                      "auto_assert Function.identity(false)",
                      "auto_refute Function.identity(false)"
                    )
    end

    test "formats calls with parens" do
      auto_assert {nil,
                   [
                     [
                       %Tag{data: "foo(", sequences: [:green]},
                       "x",
                       %Tag{data: ")", sequences: [:green]}
                     ]
                   ]} <- format("x", "foo(x)")
    end

    test "formats qualified calls" do
      auto_assert {[["foo.", %Tag{data: "bar", sequences: [:red]}, "(1, 2, 3)"]],
                   [["foo.", %Tag{data: "baz", sequences: [:green]}, "(1, 2, 3)"]]} <-
                    format("foo.bar(1, 2, 3)", "foo.baz(1, 2, 3)")

      auto_assert {nil,
                   [
                     [
                       "foo.bar",
                       %Tag{data: ".", sequences: [:green]},
                       %Tag{data: "baz", sequences: [:green]},
                       "(1, 2, 3)"
                     ]
                   ]} <- format("foo.bar(1, 2, 3)", "foo.bar.baz(1, 2, 3)")

      auto_assert {[["foo.", %Tag{data: "bar", sequences: [:red]}, ".baz(1, 2, 3)"]],
                   [["foo.", %Tag{data: "buzz", sequences: [:green]}, ".baz(1, 2, 3)"]]} <-
                    format("foo.bar.baz(1, 2, 3)", "foo.buzz.baz(1, 2, 3)")

      auto_assert {nil,
                   [
                     [
                       "foo",
                       %Tag{data: ".", sequences: [:green]},
                       %Tag{data: "bar", sequences: [:green]},
                       ".baz(1, 2, 3)"
                     ]
                   ]} <- format("foo.baz(1, 2, 3)", "foo.bar.baz(1, 2, 3)")

      auto_assert {nil,
                   [
                     [
                       "foo.bar",
                       %Tag{data: ".", sequences: [:green]},
                       %Tag{data: "baz", sequences: [:green]},
                       " 1, 2, 3"
                     ]
                   ]} <- format("foo.bar 1, 2, 3", "foo.bar.baz 1, 2, 3")

      auto_assert {nil, nil} <- format("foo.bar(1, 2, 3)", "foo.bar 1, 2, 3")

      auto_assert {nil, [["foo", %Tag{data: ".()", sequences: [:green]}, ".bar()"]]} <-
                    format("foo.bar()", "foo.().bar()")

      auto_assert {[["Foo", %Tag{data: ".Bar", sequences: [:red]}, ".baz()"]],
                   [["Foo", %Tag{data: ".Buzz", sequences: [:green]}, ".baz()"]]} <-
                    format("Foo.Bar.baz()", "Foo.Buzz.baz()")
    end

    test "formats unary operators" do
      auto_assert {nil, [[%Tag{data: "-", sequences: [:green]}, "x"]]} <- format("x", "-x")
    end

    test "formats binary operators" do
      auto_assert {[["x ", %Tag{data: "+", sequences: [:red]}, " y"]],
                   [["x ", %Tag{data: "-", sequences: [:green]}, " y"]]} <-
                    format("x + y", "x - y")
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
                       %Tag{data: "^foo(me)", sequences: [:green]},
                       " ",
                       %Tag{data: "<-", sequences: [:green]},
                       " me"
                     ]
                   ]} <- format("me", "^foo(me) <- me")
    end

    test "formats structs" do
      auto_assert {nil, [["%MyStruct{", %Tag{data: "foo: 1", sequences: [:green]}, "}"]]} <-
                    format("%MyStruct{}", "%MyStruct{foo: 1}")

      auto_assert {nil,
                   [
                     [
                       "auto_assert ",
                       %Tag{
                         data: "{:ok, %User{email: \"user@example.org\"}}",
                         sequences: [:green]
                       },
                       " ",
                       %Tag{data: "<-", sequences: [:green]},
                       " create(User, email: \"user@example.org\")"
                     ]
                   ]} <-
                    format(
                      "auto_assert create(User, email: \"user@example.org\")",
                      "auto_assert {:ok, %User{email: \"user@example.org\"}} <- create(User, email: \"user@example.org\")"
                    )
    end

    test "formats guards" do
      auto_assert {nil,
                   [
                     [
                       "auto_assert ",
                       %Tag{data: "pid when is_pid(pid)", sequences: [:green]},
                       " ",
                       %Tag{data: "<-", sequences: [:green]},
                       " self()"
                     ]
                   ]} <-
                    format("auto_assert self()", "auto_assert pid when is_pid(pid) <- self()")
    end

    # TODO: This could possibly be improved.
    test "regression: unnecessary novel nodes" do
      auto_assert {[
                     [
                       "{",
                       %Tag{data: "[", sequences: [:red]},
                       %Tag{data: "line: 1", sequences: [:red]},
                       ", column: 1",
                       %Tag{data: "]", sequences: [:red]},
                       ", ",
                       %Tag{data: "[", sequences: [:red]},
                       "line: 1, column: 2",
                       %Tag{data: "]", sequences: [:red]},
                       "}"
                     ]
                   ],
                   [
                     [
                       "{",
                       %Tag{data: "%{", sequences: [:green]},
                       "column: 1, line: 1",
                       %Tag{data: "}", sequences: [:green]},
                       ", ",
                       %Tag{data: "%{", sequences: [:green]},
                       "column: 2, ",
                       %Tag{data: "line: 1", sequences: [:green]},
                       %Tag{data: "}", sequences: [:green]},
                       "}"
                     ]
                   ]} <-
                    format(
                      "{[line: 1, column: 1], [line: 1, column: 2]}",
                      "{%{column: 1, line: 1}, %{column: 2, line: 1}}"
                    )

      auto_assert {[
                     [
                       "{:-, ",
                       %Tag{data: "[", sequences: [:red]},
                       %Tag{data: "line: 1", sequences: [:red]},
                       ", column: 1",
                       %Tag{data: "]", sequences: [:red]},
                       ", [{:var, ",
                       %Tag{data: "[", sequences: [:red]},
                       "line: 1, column: 2",
                       %Tag{data: "]", sequences: [:red]},
                       ", :x}]}"
                     ]
                   ],
                   [
                     [
                       "{:-, ",
                       %Tag{data: "%{", sequences: [:green]},
                       "column: 1, line: 1",
                       %Tag{data: "}", sequences: [:green]},
                       ", [{:var, ",
                       %Tag{data: "%{", sequences: [:green]},
                       "column: 2, ",
                       %Tag{data: "line: 1", sequences: [:green]},
                       %Tag{data: "}", sequences: [:green]},
                       ", :x}]}"
                     ]
                   ]} <-
                    format(
                      "{:-, [line: 1, column: 1], [{:var, [line: 1, column: 2], :x}]}",
                      "{:-, %{column: 1, line: 1}, [{:var, %{column: 2, line: 1}, :x}]}"
                    )
    end

    def dbg_format(left, right) do
      {left, right} = format(left, right)

      Owl.IO.puts([
        "\n",
        Owl.Data.unlines(left || []),
        "\n\n",
        Owl.Data.unlines(right || []),
        "\n"
      ])

      {left, right}
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
