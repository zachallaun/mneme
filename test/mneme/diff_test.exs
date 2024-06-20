defmodule Mneme.DiffTest do
  use ExUnit.Case, async: true
  use Mneme, default_pattern: :last

  import Mneme.DiffTestHelpers

  alias Owl.Tag, warn: false

  if Version.match?(System.version(), ">= 1.15.0") do
    Code.require_file("diff_test_1_15.exs", __DIR__)
  end

  describe "format/2" do
    test "formats insertions/deletions from nothing" do
      auto_assert {[[]], [[{"123", :green}]]} <- format("", "123")
      auto_assert {[[{"123", :red}]], [[]]} <- format("123", "")
    end

    test "formats list insertions" do
      auto_assert {nil, [["[1, ", {"[", :green}, "2_000", {"]", :green}, "]"]]} <-
                    format("[1, 2_000]", "[1, [2_000]]")

      auto_assert {nil, [["[", {":foo", :green}, "]"]]} <- format("[]", "[:foo]")
    end

    test "formats term reordering" do
      auto_assert {[["[:foo, ", {":bar", :red}, ", :baz]"]],
                   [["[", {":bar", :green}, ", :foo, :baz]"]]} <-
                    format("[:foo, :bar, :baz]", "[:bar, :foo, :baz]")
    end

    test "formats term renesting" do
      auto_assert {[["[[", {":bar", :red}, "]]"]], [["[[], ", {":bar", :green}, "]"]]} <-
                    format("[[:bar]]", "[[], :bar]")

      auto_assert {[["[[:foo, ", {":bar", :red}, "]]"]], [["[[:foo], ", {":bar", :green}, "]"]]} <-
                    format("[[:foo, :bar]]", "[[:foo], :bar]")

      auto_assert {[
                     [
                       "{:foo, ",
                       {"%", :red},
                       {"MyStruct", :red},
                       {"{", :red},
                       {"hmm:", :red},
                       " ",
                       {"[", :red},
                       {":bar", :red},
                       ", {:some, :thing}",
                       {"]", :red},
                       {"}", :red},
                       "}"
                     ]
                   ],
                   [
                     [
                       "{:foo, ",
                       {"%{", :green},
                       {"cool:", :green},
                       " {:some, :thing}",
                       {"}", :green},
                       "}"
                     ]
                   ]} <-
                    format(
                      "{:foo, %MyStruct{hmm: [:bar, {:some, :thing}]}}",
                      "{:foo, %{cool: {:some, :thing}}}"
                    )
    end

    test "formats strings" do
      auto_assert {[[{"\"foo\"", :red}]], [[{"\"bar\"", :green}]]} <- format(~s("foo"), ~s("bar"))

      auto_assert {[[{"\"\"\"", :red}], {"foo", :red}, {"bar", :red}, [{"\"\"\"", :red}], []],
                   [[{"\"\"\"", :green}], {"baz", :green}, [{"\"\"\"", :green}], []]} <-
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

      auto_assert {[["[", {"\"foo\"", :red}, "]"]], [["[", {"\"bar\"", :green}, "]"]]} <-
                    format(~s(["foo"]), ~s(["bar"]))

      auto_assert {nil, [["[", {"\"\\\"foo\\\"\"", :green}, "]"]]} <-
                    format("[]", ~s(["\\\"foo\\\""]))

      auto_assert {nil,
                   [
                     ["auto_assert_raise ", {"ArgumentError", :green}, ","],
                     ["                  ", {"\"\"\"", :green}],
                     {"                  foo", :green},
                     {"                  bar", :green},
                     {"                  \\\#{baz}", :green},
                     [{"                  \"\"\"", :green}, ","],
                     ["                  fn ->"],
                     ["                    error!(\"\"\""],
                     ["                    foo"],
                     ["                    bar"],
                     ["                    \\\#{baz}"],
                     ["                    \"\"\")"],
                     ["                  end"],
                     []
                   ]} <-
                    format(
                      """
                      auto_assert_raise fn ->
                        error!(\"""
                        foo
                        bar
                        \\\#{baz}
                        \""")
                      end
                      """,
                      """
                      auto_assert_raise ArgumentError,
                                        \"""
                                        foo
                                        bar
                                        \\\#{baz}
                                        \""",
                                        fn ->
                                          error!(\"""
                                          foo
                                          bar
                                          \\\#{baz}
                                          \""")
                                        end
                      """
                    )
    end

    test "formats strings using myers diff when they are similar" do
      auto_assert {[
                     [
                       {"\"", :red},
                       {"fooba", :red},
                       {"r", [:bright, :red, :underline]},
                       {"\"", :red}
                     ]
                   ],
                   [
                     [
                       {"\"", :green},
                       {"fooba", :green},
                       {"z", [:bright, :green, :underline]},
                       {"\"", :green}
                     ]
                   ]} <- format(~s("foobar"), ~s("foobaz"))

      auto_assert {[
                     [
                       {"\"", :red},
                       {"fo", :red},
                       {"o", [:bright, :red, :underline]},
                       {"ba", :red},
                       {"r", [:bright, :red, :underline]},
                       {"\"", :red}
                     ]
                   ],
                   [
                     [
                       {"\"", :green},
                       {"fo", :green},
                       {"a", [:bright, :green, :underline]},
                       {"ba", :green},
                       {"z", [:bright, :green, :underline]},
                       {"\"", :green}
                     ]
                   ]} <- format(~s("foobar"), ~s("foabaz"))

      auto_assert {[
                     [
                       {"\"", :red},
                       {"\\\"fo", :red},
                       {"o", [:bright, :red, :underline]},
                       {"\\\"", :red},
                       {"\"", :red}
                     ]
                   ],
                   [
                     [
                       {"\"", :green},
                       {"\\\"fo", :green},
                       {"a", [:bright, :green, :underline]},
                       {"\\\"", :green},
                       {"\"", :green}
                     ]
                   ]} <- format("\"\\\"foo\\\"\"", "\"\\\"foa\\\"\"")

      auto_assert {[
                     [
                       {"\"", :red},
                       {"f", :red},
                       {"oo", [:bright, :red, :underline]},
                       {" ", :red},
                       {"bar", :red},
                       {"\"", :red}
                     ]
                   ],
                   [
                     [
                       {"\"", :green},
                       {"f", :green},
                       {"a", [:bright, :green, :underline]},
                       {" ", :green},
                       {"o", [:bright, :green, :underline]},
                       {"bar", :green},
                       {" ", [:bright, :green, :underline]},
                       {"\"", :green}
                     ]
                   ]} <- format(~s("foo bar"), ~s("fa obar "))

      auto_assert {[
                     [{"\"\"\"", :red}],
                     [
                       {"f", [:bright, :red, :underline]},
                       {"o", :red},
                       {"o", [:bright, :red, :underline]}
                     ],
                     [{"ba", :red}, {"r", [:bright, :red, :underline]}],
                     [{"\"\"\"", :red}]
                   ],
                   [
                     [{"\"\"\"", :green}],
                     [
                       {"s", [:bright, :green, :underline]},
                       {"o", :green},
                       {"a ", [:bright, :green, :underline]}
                     ],
                     [{"ba", :green}, {"z", [:bright, :green, :underline]}],
                     [{"\"\"\"", :green}]
                   ]} <- format(~s("""\nfoo\nbar\n"""), ~s("""\nsoa \nbaz\n"""))

      auto_assert {[
                     [{"\"\"\"", :red}],
                     [
                       "  ",
                       {"f", [:bright, :red, :underline]},
                       {"o", :red},
                       {"o", [:bright, :red, :underline]}
                     ],
                     ["  ", {"ba", :red}, {"r", [:bright, :red, :underline]}],
                     ["  ", {"\"\"\"", :red}]
                   ],
                   [
                     [{"\"\"\"", :green}],
                     [
                       "  ",
                       {"s", [:bright, :green, :underline]},
                       {"o", :green},
                       {"a ", [:bright, :green, :underline]}
                     ],
                     ["  ", {"ba", :green}, {"z", [:bright, :green, :underline]}],
                     ["  ", {"\"\"\"", :green}]
                   ]} <- format(~s("""\n  foo\n  bar\n  """), ~s("""\n  soa \n  baz\n  """))
    end

    test "formats sigils using myers diff when they are similar" do
      auto_assert {[
                     [
                       "~D[",
                       {"200", :red},
                       {"0", [:bright, :red, :underline]},
                       {"-01-01", :red},
                       "]"
                     ]
                   ],
                   [
                     [
                       "~D[",
                       {"200", :green},
                       {"1", [:bright, :green, :underline]},
                       {"-01-01", :green},
                       "]"
                     ]
                   ]} <- format("~D[2000-01-01]", "~D[2001-01-01]")
    end

    test "formats charlists" do
      auto_assert {nil, [["[", {"~c(foo)", :green}, "]"]]} <- format("[]", "[~c(foo)]")

      auto_assert {nil, [["[", {"'foo'", :green}, "]"]]} <- format("[]", "['foo']")
    end

    test "formats strings to sigil charlists" do
      auto_assert {nil, [[{"~", :green}, {"c", :green}, "\"foo\""]]} <-
                    format(~S("foo"), ~S(~c"foo"))

      auto_assert {[[{"~", :red}, {"c", :red}, "\"foo\""]], nil} <- format(~S(~c"foo"), ~S("foo"))
    end

    test "formats integer insertions" do
      auto_assert {nil, [["[1, ", {"2_000", :green}, "]"]]} <- format("[1]", "[1, 2_000]")
    end

    test "formats over multiple lines" do
      auto_assert {nil, ["[", "  1,", ["  ", {"2_000", :green}], ["]"]]} <-
                    format("[\n  1\n]", "[\n  1,\n  2_000\n]")
    end

    test "formats tuple to list" do
      auto_assert {[[{"{", :red}, "1, 2", {"}", :red}]], [[{"[", :green}, "1, 2", {"]", :green}]]} <-
                    format("{1, 2}", "[1, 2]")
    end

    test "formats map to kw" do
      auto_assert {[[{"%{", :red}, "foo: 1", {"}", :red}]],
                   [[{"[", :green}, "foo: 1", {"]", :green}]]} <- format("%{foo: 1}", "[foo: 1]")
    end

    test "formats map key insertion" do
      auto_assert {nil, [["%{:foo => 1, ", {"2 => :bar", :green}, ", :baz => 3}"]]} <-
                    format("%{foo: 1, baz: 3}", "%{:foo => 1, 2 => :bar, :baz => 3}")

      auto_assert {nil, [["%{foo: 1, ", {"bar: 2", :green}, "}"]]} <-
                    format("%{foo: 1}", "%{foo: 1, bar: 2}")

      auto_assert {nil,
                   [["foo(", {"%{", :green}], {"  bar: 1", :green}, [{"}", :green}, ")"], []]} <-
                    format(
                      """
                      foo()
                      """,
                      """
                      foo(%{
                        bar: 1
                      })
                      """
                    )
    end

    test "formats entire collections" do
      auto_assert {nil,
                   [
                     [
                       "[a, ",
                       {"[y, z]", :green},
                       ", ",
                       {"[:foo, :bar]", :green},
                       ", ",
                       {"[:baz]", :green},
                       "]"
                     ]
                   ]} <- format("[a]", "[a, [y, z], [:foo, :bar], [:baz]]")

      auto_assert {nil, [["[x, ", {"%{y: 1}", :green}, "]"]]} <- format("[x]", "[x, %{y: 1}]")

      auto_assert {nil, [["[x, ", {"%{:y => 1}", :green}, "]"]]} <-
                    format("[x]", "[x, %{:y => 1}]")

      auto_assert {nil, [["[x, ", {"%MyStruct{foo: 1}", :green}, "]"]]} <-
                    format("[x]", "[x, %MyStruct{foo: 1}]")

      auto_assert {[[{"[", :red}], {"  foo: 1,", :red}, {"  bar: 2", :red}, [{"]", :red}], []],
                   [
                     [{"%{", :green}],
                     {"  baz: 3,", :green},
                     {"  buzz: 4", :green},
                     [{"}", :green}],
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
      auto_assert {[[{"%{", :red}, "bar: 1", {"}", :red}]],
                   [[{"%", :green}, {"MyStruct", :green}, {"{", :green}, "bar: 1", {"}", :green}]]} <-
                    format("%{bar: 1}", "%MyStruct{bar: 1}")

      auto_assert {[[{"%", :red}, {"MyStruct", :red}, {"{", :red}, "foo: 1", {"}", :red}]],
                   [[{"%{", :green}, "foo: 1", {"}", :green}]]} <-
                    format("%MyStruct{foo: 1}", "%{foo: 1}")

      auto_assert {[
                     [{"%{", :red}],
                     ["  foo: 1,"],
                     ["  ", {"bar:", :red}, " 2"],
                     [{"}", :red}],
                     []
                   ],
                   [
                     [{"%", :green}, {"MyStruct", :green}, {"{", :green}],
                     ["  foo: 1,"],
                     ["  ", {"baz:", :green}, " 2"],
                     [{"}", :green}],
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
      auto_assert {[["Foo.", {"Bar.", :red}, "Baz"]], [["Foo.", {"Buzz.", :green}, "Baz"]]} <-
                    format("Foo.Bar.Baz", "Foo.Buzz.Baz")

      auto_assert {nil, [["Foo.Bar", {".Baz", :green}]]} <- format("Foo.Bar", "Foo.Bar.Baz")

      auto_assert {nil, [[{"Foo.", :green}, "Bar.Baz"]]} <- format("Bar.Baz", "Foo.Bar.Baz")
    end

    test "formats calls without parens" do
      auto_assert {nil, [["auto_assert :foo ", {"<-", :green}, " ", {":foo", :green}]]} <-
                    format("auto_assert :foo", "auto_assert :foo <- :foo")

      auto_assert {[[{"auto_assert", :red}, " Function.identity(false)"]],
                   [[{"auto_refute", :green}, " Function.identity(false)"]]} <-
                    format(
                      "auto_assert Function.identity(false)",
                      "auto_refute Function.identity(false)"
                    )
    end

    test "formats calls with parens" do
      auto_assert {nil, [[{"foo(", :green}, "x", {")", :green}]]} <- format("x", "foo(x)")
    end

    test "formats qualified calls" do
      auto_assert {[[{"foo", :red}, ".bar()"]], [[{"foo.()", :green}, ".bar()"]]} <-
                    format("foo.bar()", "foo.().bar()")

      auto_assert {[["foo.bar 1, 2, 3"]],
                   [["foo.bar", {".", :green}, {"baz", :green}, " 1, 2, 3"]]} <-
                    format("foo.bar 1, 2, 3", "foo.bar.baz 1, 2, 3")

      auto_assert {[[{"foo", :red}, ".baz(1, 2, 3)"]], [[{"foo.bar", :green}, ".baz(1, 2, 3)"]]} <-
                    format("foo.baz(1, 2, 3)", "foo.bar.baz(1, 2, 3)")

      auto_assert {[["foo.bar", {"(", :red}, "1, 2, 3", {")", :red}]],
                   [
                     [
                       "foo.bar",
                       {".", :green},
                       {"baz", :green},
                       {"(", :green},
                       "1, 2, 3",
                       {")", :green}
                     ]
                   ]} <- format("foo.bar(1, 2, 3)", "foo.bar.baz(1, 2, 3)")

      auto_assert {[["foo.", {"bar", :red}, "(1, 2, 3)"]],
                   [["foo.", {"baz", :green}, "(1, 2, 3)"]]} <-
                    format("foo.bar(1, 2, 3)", "foo.baz(1, 2, 3)")

      auto_assert {[["foo.", {"bar", :red}, ".baz(1, 2, 3)"]],
                   [["foo.", {"buzz", :green}, ".baz(1, 2, 3)"]]} <-
                    format("foo.bar.baz(1, 2, 3)", "foo.buzz.baz(1, 2, 3)")

      auto_assert {nil, nil} <- format("foo.bar(1, 2, 3)", "foo.bar 1, 2, 3")

      auto_assert {[["Foo", {".Bar", :red}, ".baz()"]], [["Foo", {".Buzz", :green}, ".baz()"]]} <-
                    format("Foo.Bar.baz()", "Foo.Buzz.baz()")
    end

    test "formats unary operators" do
      auto_assert {nil, [[{"-", :green}, "x"]]} <- format("x", "-x")
    end

    test "formats binary operators" do
      auto_assert {[["x ", {"+", :red}, " y"]], [["x ", {"-", :green}, " y"]]} <-
                    format("x + y", "x - y")

      auto_assert {[[{"1", :red}, " + ", {"2", :red}]], [[{"2", :green}, " + ", {"1", :green}]]} <-
                    format("1 + 2", "2 + 1")

      auto_assert {[["1 ", {"+", :red}, " ", {"2", :red}]],
                   [[{"2", :green}, " ", {"-", :green}, " 1"]]} <- format("1 + 2", "2 - 1")
    end

    test "formats pins" do
      auto_assert {nil, [["auto_assert ", {"^me", :green}, " ", {"<-", :green}, " me"]]} <-
                    format("auto_assert me", "auto_assert ^me <- me")

      auto_assert {nil, [[{"^foo(me)", :green}, " ", {"<-", :green}, " me"]]} <-
                    format("me", "^foo(me) <- me")
    end

    test "formats structs" do
      auto_assert {nil, [["%MyStruct{", {"foo: 1", :green}, "}"]]} <-
                    format("%MyStruct{}", "%MyStruct{foo: 1}")

      auto_assert {nil,
                   [
                     [
                       "auto_assert ",
                       {"{:ok, %User{email: \"user@example.org\"}}", :green},
                       " ",
                       {"<-", :green},
                       " create(User, email: \"user@example.org\")"
                     ]
                   ]} <-
                    format(
                      "auto_assert create(User, email: \"user@example.org\")",
                      "auto_assert {:ok, %User{email: \"user@example.org\"}} <- create(User, email: \"user@example.org\")"
                    )

      auto_assert {[
                     [
                       "auto_assert %My.Qualified.Struct{",
                       {"a: \"a\"", :red},
                       ", ",
                       {"b: \"b\"", :red},
                       ", ",
                       {"c: \"c\"", :red},
                       ", ",
                       {"d: \"d\"", :red},
                       "} <- some_call()"
                     ],
                     []
                   ],
                   nil} <-
                    format(
                      """
                      auto_assert %My.Qualified.Struct{a: "a", b: "b", c: "c", d: "d"} <- some_call()
                      """,
                      """
                      auto_assert %My.Qualified.Struct{} <- some_call()
                      """
                    )

      auto_assert {[
                     [
                       "auto_assert %My.Qualified.Struct{",
                       {"a: \"a\", b: \"b\", c: \"c\", d: \"d\", e: \"e\"", :red},
                       "} <- some_call()"
                     ],
                     []
                   ],
                   ["auto_assert %My.Qualified.Struct{} <- some_call()", []]} <-
                    format(
                      """
                      auto_assert %My.Qualified.Struct{a: "a", b: "b", c: "c", d: "d", e: "e"} <- some_call()
                      """,
                      """
                      auto_assert %My.Qualified.Struct{} <- some_call()
                      """
                    )
    end

    test "formats guards" do
      auto_assert {nil,
                   [
                     [
                       "auto_assert ",
                       {"pid when is_pid(pid)", :green},
                       " ",
                       {"<-", :green},
                       " self()"
                     ]
                   ]} <-
                    format("auto_assert self()", "auto_assert pid when is_pid(pid) <- self()")
    end

    test "formats ex_unit targets" do
      auto_assert {[[{"auto_assert pid when is_pid(pid) <- self()", :red}], []],
                   [[{"assert pid = self()", :green}], [{"assert is_pid(pid)", :green}], []]} <-
                    format(
                      """
                      auto_assert pid when is_pid(pid) <- self()
                      """,
                      """
                      assert pid = self()
                      assert is_pid(pid)
                      """
                    )
    end

    test "formats ranges" do
      auto_assert {[[]], [[{"1..10", :green}]]} <- format("", "1..10")

      auto_assert {[[]], [[{"1..10//2", :green}]]} <- format("", "1..10//2")

      auto_assert {[[{"1", :red}, "..10"]], [[{"2", :green}, "..10"]]} <- format("1..10", "2..10")

      auto_assert {[["1..10//", {"1", :red}]], [["1..10//", {"2", :green}]]} <-
                    format("1..10//1", "1..10//2")

      auto_assert {[[{"[", :red}, "1, 10", {"]", :red}]], [["1", {"..", :green}, "10"]]} <-
                    format("[1, 10]", "1..10")

      auto_assert {[["1", {"..", :red}, "10"]],
                   [["1", {"..", :green}, "10", {"//", :green}, {"2", :green}]]} <-
                    format("1..10", "1..10//2")
    end

    test "formats anonymous functions" do
      auto_assert {nil,
                   [["auto_assert_raise ", {"ArgumentError", :green}, ", fn -> some_call() end"]]} <-
                    format(
                      "auto_assert_raise fn -> some_call() end",
                      "auto_assert_raise ArgumentError, fn -> some_call() end"
                    )

      auto_assert {nil,
                   [
                     [
                       "auto_assert_raise ",
                       {"ArgumentError", :green},
                       ", ",
                       {"\"some message\"", :green},
                       ", fn -> some_call() end"
                     ]
                   ]} <-
                    format(
                      "auto_assert_raise fn -> some_call() end",
                      "auto_assert_raise ArgumentError, \"some message\", fn -> some_call() end"
                    )

      auto_assert {[
                     [
                       "auto_assert_raise",
                       {" ArgumentError", :red},
                       ", fn -> ",
                       {":bad", :red},
                       " end"
                     ]
                   ],
                   [
                     [
                       "auto_assert_raise ",
                       {"Some.", :green},
                       {"Other", :green},
                       {".Exception", :green},
                       ", fn -> ",
                       {":good", :green},
                       " end"
                     ]
                   ]} <-
                    format(
                      "auto_assert_raise ArgumentError, fn -> :bad end",
                      "auto_assert_raise Some.Other.Exception, fn -> :good end"
                    )
    end

    test "formats captured functiosn" do
      auto_assert {nil,
                   [
                     [
                       "auto_assert_raise ",
                       {"Some.Exception", :green},
                       ", ",
                       {"\"with a message\"", :green},
                       ", &foo/0"
                     ]
                   ]} <-
                    format(
                      "auto_assert_raise &foo/0",
                      "auto_assert_raise Some.Exception, \"with a message\", &foo/0"
                    )
    end

    # https://difftastic.wilfred.me.uk/tricky_cases.html
    test "tricky cases h/t difftastic" do
      auto_assert {nil, [[{"[", :green}, "x", {"]", :green}]]} <- format("x", "[x]")

      auto_assert {[[{"{", :red}, "x", {"}", :red}]], [[{"[", :green}, "x", {"]", :green}]]} <-
                    format("{x}", "[x]")

      auto_assert {[["{[x], ", {"y", :red}, "}"]], [["{[x, ", {"y", :green}, "]}"]]} <-
                    format("{[x], y}", "{[x, y]}")

      auto_assert {[["{[x, ", {"y", :red}, "]}"]], [["{[x], ", {"y", :green}, "}"]]} <-
                    format("{[x, y]}", "{[x], y}")

      auto_assert {nil, [["[foo, ", {"[new]", :green}, ", [bar]]"]]} <-
                    format("[foo, [bar]]", "[foo, [new], [bar]]")

      auto_assert {nil, [["foo(", {"new(", :green}, "bar(123)", {")", :green}, ")"]]} <-
                    format("foo(bar(123))", "foo(new(bar(123)))")

      auto_assert {nil, [["foo(", {"bar(", :green}, "123", {")", :green}, ")"]]} <-
                    format("foo(123)", "foo(bar(123))")
    end

    # TODO: This could possibly be improved.
    test "regression: unnecessary novel nodes" do
      auto_assert {[
                     [
                       "{",
                       {"[", :red},
                       {"line: 1", :red},
                       ", column: 1",
                       {"]", :red},
                       ", ",
                       {"[", :red},
                       "line: 1, column: 2",
                       {"]", :red},
                       "}"
                     ]
                   ],
                   [
                     [
                       "{",
                       {"%{", :green},
                       "column: 1, line: 1",
                       {"}", :green},
                       ", ",
                       {"%{", :green},
                       "column: 2, ",
                       {"line: 1", :green},
                       {"}", :green},
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
                       {"[", :red},
                       {"line:", :red},
                       " 1, ",
                       {"column:", :red},
                       " 1",
                       {"]", :red},
                       ", [{:var, ",
                       {"[", :red},
                       "line: 1, ",
                       {"column: 2", :red},
                       {"]", :red},
                       ", :x}]}"
                     ]
                   ],
                   [
                     [
                       "{:-, ",
                       {"%{", :green},
                       {"column:", :green},
                       " 1, ",
                       {"line:", :green},
                       " 1",
                       {"}", :green},
                       ", [{:var, ",
                       {"%{", :green},
                       {"column: 2", :green},
                       ", line: 1",
                       {"}", :green},
                       ", :x}]}"
                     ]
                   ]} <-
                    format(
                      "{:-, [line: 1, column: 1], [{:var, [line: 1, column: 2], :x}]}",
                      "{:-, %{column: 1, line: 1}, [{:var, %{column: 2, line: 1}, :x}]}"
                    )
    end

    test "regression: issues with minimization" do
      left = """
      auto_assert {nil,
                   [
                     [
                       "[1, ",
                       %Tag{data: "[", sequences: [:green]},
                       "2_000",
                       %Tag{data: "]", sequences: [:green]},
                       "]"
                     ]
                   ]} <- format("[1, 2_000]", "[1, [3_000]]")
      """

      right = """
      auto_assert {[["[1, ", %Tag{data: "2_000", sequences: [:red]}, "]"]],
                   [["[1, ", %Tag{data: "[3_000]", sequences: [:green]}, "]"]]} <-
                    format("[1, 2_000]", "[1, [3_000]]")
      """

      auto_assert {[
                     ["auto_assert {", {"nil", :red}, ","],
                     ["             ["],
                     ["               ["],
                     ["                 \"[1, \","],
                     ["                 %Tag{data: ", {"\"[\"", :red}, ", sequences: [:green]},"],
                     ["                 ", {"\"2_000\"", :red}, ","],
                     ["                 ", {"%Tag{data: \"]\", sequences: [:green]}", :red}, ","],
                     ["                 \"]\""],
                     ["               ]"],
                     ["             ]} <- format(\"[1, 2_000]\", \"[1, [3_000]]\")"],
                     []
                   ],
                   [
                     [
                       "auto_assert {",
                       {"[[\"[1, \", %Tag{data: \"2_000\", sequences: [:red]}, \"]\"]]", :green},
                       ","
                     ],
                     [
                       "             [[\"[1, \", %Tag{data: ",
                       {"\"[3_000]\"", :green},
                       ", sequences: [:green]}, \"]\"]]} <-"
                     ],
                     ["              format(\"[1, 2_000]\", \"[1, [3_000]]\")"],
                     []
                   ]} <- format(left, right)
    end

    if Version.match?(System.version(), ">= 1.14.4") do
      test "elixir bug: escaped interpolation column count" do
        auto_assert {[["auto_assert ", {"res", :red}]],
                     [["auto_assert ", {"{:ok, \"\\\#{foo}\"}", :green}]]} <-
                      format(~S|auto_assert res|, ~S|auto_assert {:ok, "\#{foo}"}|)
      end
    end
  end
end
