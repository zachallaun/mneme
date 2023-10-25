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
      auto_assert {[[]], [[%Tag{data: "123", sequences: [:green]}]]} <- format("", "123")
      auto_assert {[[%Tag{data: "123", sequences: [:red]}]], [[]]} <- format("123", "")
    end

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
                       "{:foo, ",
                       %Tag{data: "%", sequences: [:red]},
                       %Tag{data: "MyStruct", sequences: [:red]},
                       %Tag{data: "{", sequences: [:red]},
                       %Tag{data: "hmm:", sequences: [:red]},
                       " ",
                       %Tag{data: "[", sequences: [:red]},
                       %Tag{data: ":bar", sequences: [:red]},
                       ", {:some, :thing}",
                       %Tag{data: "]", sequences: [:red]},
                       %Tag{data: "}", sequences: [:red]},
                       "}"
                     ]
                   ],
                   [
                     [
                       "{:foo, ",
                       %Tag{data: "%{", sequences: [:green]},
                       %Tag{data: "cool:", sequences: [:green]},
                       " {:some, :thing}",
                       %Tag{data: "}", sequences: [:green]},
                       "}"
                     ]
                   ]} <-
                    format(
                      "{:foo, %MyStruct{hmm: [:bar, {:some, :thing}]}}",
                      "{:foo, %{cool: {:some, :thing}}}"
                    )
    end

    test "formats strings" do
      auto_assert {[[%Tag{data: "\"foo\"", sequences: [:red]}]],
                   [[%Tag{data: "\"bar\"", sequences: [:green]}]]} <-
                    format(~s("foo"), ~s("bar"))

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

      auto_assert {nil, [["[", %Tag{data: "\"\\\"foo\\\"\"", sequences: [:green]}, "]"]]} <-
                    format("[]", ~s(["\\\"foo\\\""]))

      auto_assert {nil,
                   [
                     [
                       "auto_assert_raise ",
                       %Tag{data: "ArgumentError", sequences: [:green]},
                       ","
                     ],
                     ["                  ", %Tag{data: "\"\"\"", sequences: [:green]}],
                     %Tag{data: "                  foo", sequences: [:green]},
                     %Tag{data: "                  bar", sequences: [:green]},
                     %Tag{data: "                  \\\#{baz}", sequences: [:green]},
                     [%Tag{data: "                  \"\"\"", sequences: [:green]}, ","],
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
                       %Tag{data: "\"", sequences: [:red]},
                       %Tag{data: "fooba", sequences: [:red]},
                       %Tag{data: "r", sequences: [:bright, :red, :underline]},
                       %Tag{data: "\"", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "\"", sequences: [:green]},
                       %Tag{data: "fooba", sequences: [:green]},
                       %Tag{data: "z", sequences: [:bright, :green, :underline]},
                       %Tag{data: "\"", sequences: [:green]}
                     ]
                   ]} <- format(~s("foobar"), ~s("foobaz"))

      auto_assert {[
                     [
                       %Tag{data: "\"", sequences: [:red]},
                       %Tag{data: "fo", sequences: [:red]},
                       %Tag{data: "o", sequences: [:bright, :red, :underline]},
                       %Tag{data: "ba", sequences: [:red]},
                       %Tag{data: "r", sequences: [:bright, :red, :underline]},
                       %Tag{data: "\"", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "\"", sequences: [:green]},
                       %Tag{data: "fo", sequences: [:green]},
                       %Tag{data: "a", sequences: [:bright, :green, :underline]},
                       %Tag{data: "ba", sequences: [:green]},
                       %Tag{data: "z", sequences: [:bright, :green, :underline]},
                       %Tag{data: "\"", sequences: [:green]}
                     ]
                   ]} <- format(~s("foobar"), ~s("foabaz"))

      auto_assert {[
                     [
                       %Tag{data: "\"", sequences: [:red]},
                       %Tag{data: "\\\"fo", sequences: [:red]},
                       %Tag{data: "o", sequences: [:bright, :red, :underline]},
                       %Tag{data: "\\\"", sequences: [:red]},
                       %Tag{data: "\"", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "\"", sequences: [:green]},
                       %Tag{data: "\\\"fo", sequences: [:green]},
                       %Tag{data: "a", sequences: [:bright, :green, :underline]},
                       %Tag{data: "\\\"", sequences: [:green]},
                       %Tag{data: "\"", sequences: [:green]}
                     ]
                   ]} <- format("\"\\\"foo\\\"\"", "\"\\\"foa\\\"\"")

      auto_assert {[
                     [
                       %Tag{data: "\"", sequences: [:red]},
                       %Tag{data: "f", sequences: [:red]},
                       %Tag{data: "oo", sequences: [:bright, :red, :underline]},
                       %Tag{data: " ", sequences: [:red]},
                       %Tag{data: "bar", sequences: [:red]},
                       %Tag{data: "\"", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "\"", sequences: [:green]},
                       %Tag{data: "f", sequences: [:green]},
                       %Tag{data: "a", sequences: [:bright, :green, :underline]},
                       %Tag{data: " ", sequences: [:green]},
                       %Tag{data: "o", sequences: [:bright, :green, :underline]},
                       %Tag{data: "bar", sequences: [:green]},
                       %Tag{data: " ", sequences: [:bright, :green, :underline]},
                       %Tag{data: "\"", sequences: [:green]}
                     ]
                   ]} <- format(~s("foo bar"), ~s("fa obar "))

      auto_assert {[
                     [%Tag{data: "\"\"\"", sequences: [:red]}],
                     [
                       %Tag{data: "f", sequences: [:bright, :red, :underline]},
                       %Tag{data: "o", sequences: [:red]},
                       %Tag{data: "o", sequences: [:bright, :red, :underline]}
                     ],
                     [
                       %Tag{data: "ba", sequences: [:red]},
                       %Tag{data: "r", sequences: [:bright, :red, :underline]}
                     ],
                     [%Tag{data: "\"\"\"", sequences: [:red]}]
                   ],
                   [
                     [%Tag{data: "\"\"\"", sequences: [:green]}],
                     [
                       %Tag{data: "s", sequences: [:bright, :green, :underline]},
                       %Tag{data: "o", sequences: [:green]},
                       %Tag{data: "a ", sequences: [:bright, :green, :underline]}
                     ],
                     [
                       %Tag{data: "ba", sequences: [:green]},
                       %Tag{data: "z", sequences: [:bright, :green, :underline]}
                     ],
                     [%Tag{data: "\"\"\"", sequences: [:green]}]
                   ]} <- format(~s("""\nfoo\nbar\n"""), ~s("""\nsoa \nbaz\n"""))

      auto_assert {[
                     [%Tag{data: "\"\"\"", sequences: [:red]}],
                     [
                       "  ",
                       %Tag{data: "f", sequences: [:bright, :red, :underline]},
                       %Tag{data: "o", sequences: [:red]},
                       %Tag{data: "o", sequences: [:bright, :red, :underline]}
                     ],
                     [
                       "  ",
                       %Tag{data: "ba", sequences: [:red]},
                       %Tag{data: "r", sequences: [:bright, :red, :underline]}
                     ],
                     ["  ", %Tag{data: "\"\"\"", sequences: [:red]}]
                   ],
                   [
                     [%Tag{data: "\"\"\"", sequences: [:green]}],
                     [
                       "  ",
                       %Tag{data: "s", sequences: [:bright, :green, :underline]},
                       %Tag{data: "o", sequences: [:green]},
                       %Tag{data: "a ", sequences: [:bright, :green, :underline]}
                     ],
                     [
                       "  ",
                       %Tag{data: "ba", sequences: [:green]},
                       %Tag{data: "z", sequences: [:bright, :green, :underline]}
                     ],
                     ["  ", %Tag{data: "\"\"\"", sequences: [:green]}]
                   ]} <- format(~s("""\n  foo\n  bar\n  """), ~s("""\n  soa \n  baz\n  """))
    end

    test "formats sigils using myers diff when they are similar" do
      auto_assert {[
                     [
                       "~D[",
                       %Tag{data: "200", sequences: [:red]},
                       %Tag{data: "0", sequences: [:bright, :red, :underline]},
                       %Tag{data: "-01-01", sequences: [:red]},
                       "]"
                     ]
                   ],
                   [
                     [
                       "~D[",
                       %Tag{data: "200", sequences: [:green]},
                       %Tag{data: "1", sequences: [:bright, :green, :underline]},
                       %Tag{data: "-01-01", sequences: [:green]},
                       "]"
                     ]
                   ]} <- format("~D[2000-01-01]", "~D[2001-01-01]")
    end

    test "formats charlists" do
      auto_assert {nil, [["[", %Tag{data: "~c(foo)", sequences: [:green]}, "]"]]} <-
                    format("[]", "[~c(foo)]")

      auto_assert {nil, [["[", %Tag{data: "'foo'", sequences: [:green]}, "]"]]} <-
                    format("[]", "['foo']")
    end

    test "formats strings to sigil charlists" do
      auto_assert {nil,
                   [
                     [
                       %Tag{data: "~", sequences: [:green]},
                       %Tag{data: "c", sequences: [:green]},
                       "\"foo\""
                     ]
                   ]} <- format(~S("foo"), ~S(~c"foo"))

      auto_assert {[
                     [
                       %Tag{data: "~", sequences: [:red]},
                       %Tag{data: "c", sequences: [:red]},
                       "\"foo\""
                     ]
                   ], nil} <- format(~S(~c"foo"), ~S("foo"))
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

      auto_assert {nil,
                   [
                     ["foo(", %Tag{data: "%{", sequences: [:green]}],
                     %Tag{data: "  bar: 1", sequences: [:green]},
                     [%Tag{data: "}", sequences: [:green]}, ")"],
                     []
                   ]} <-
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
      auto_assert {[
                     [
                       %Tag{data: "%{", sequences: [:red]},
                       "bar: 1",
                       %Tag{data: "}", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "%", sequences: [:green]},
                       %Tag{data: "MyStruct", sequences: [:green]},
                       %Tag{data: "{", sequences: [:green]},
                       "bar: 1",
                       %Tag{data: "}", sequences: [:green]}
                     ]
                   ]} <- format("%{bar: 1}", "%MyStruct{bar: 1}")

      auto_assert {[
                     [
                       %Tag{data: "%", sequences: [:red]},
                       %Tag{data: "MyStruct", sequences: [:red]},
                       %Tag{data: "{", sequences: [:red]},
                       "foo: 1",
                       %Tag{data: "}", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "%{", sequences: [:green]},
                       "foo: 1",
                       %Tag{data: "}", sequences: [:green]}
                     ]
                   ]} <- format("%MyStruct{foo: 1}", "%{foo: 1}")

      auto_assert {[
                     [%Tag{data: "%{", sequences: [:red]}],
                     ["  foo: 1,"],
                     ["  ", %Tag{data: "bar:", sequences: [:red]}, " 2"],
                     [%Tag{data: "}", sequences: [:red]}],
                     []
                   ],
                   [
                     [
                       %Tag{data: "%", sequences: [:green]},
                       %Tag{data: "MyStruct", sequences: [:green]},
                       %Tag{data: "{", sequences: [:green]}
                     ],
                     ["  foo: 1,"],
                     ["  ", %Tag{data: "baz:", sequences: [:green]}, " 2"],
                     [%Tag{data: "}", sequences: [:green]}],
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
      auto_assert {[[%Tag{data: "foo", sequences: [:red]}, ".bar()"]],
                   [[%Tag{data: "foo.()", sequences: [:green]}, ".bar()"]]} <-
                    format("foo.bar()", "foo.().bar()")

      auto_assert {[["foo.bar 1, 2, 3"]],
                   [
                     [
                       "foo.bar",
                       %Tag{data: ".", sequences: [:green]},
                       %Tag{data: "baz", sequences: [:green]},
                       " 1, 2, 3"
                     ]
                   ]} <- format("foo.bar 1, 2, 3", "foo.bar.baz 1, 2, 3")

      auto_assert {[[%Tag{data: "foo", sequences: [:red]}, ".baz(1, 2, 3)"]],
                   [[%Tag{data: "foo.bar", sequences: [:green]}, ".baz(1, 2, 3)"]]} <-
                    format("foo.baz(1, 2, 3)", "foo.bar.baz(1, 2, 3)")

      auto_assert {[
                     [
                       "foo.bar",
                       %Tag{data: "(", sequences: [:red]},
                       "1, 2, 3",
                       %Tag{data: ")", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       "foo.bar",
                       %Tag{data: ".", sequences: [:green]},
                       %Tag{data: "baz", sequences: [:green]},
                       %Tag{data: "(", sequences: [:green]},
                       "1, 2, 3",
                       %Tag{data: ")", sequences: [:green]}
                     ]
                   ]} <- format("foo.bar(1, 2, 3)", "foo.bar.baz(1, 2, 3)")

      auto_assert {[["foo.", %Tag{data: "bar", sequences: [:red]}, "(1, 2, 3)"]],
                   [["foo.", %Tag{data: "baz", sequences: [:green]}, "(1, 2, 3)"]]} <-
                    format("foo.bar(1, 2, 3)", "foo.baz(1, 2, 3)")

      auto_assert {[["foo.", %Tag{data: "bar", sequences: [:red]}, ".baz(1, 2, 3)"]],
                   [["foo.", %Tag{data: "buzz", sequences: [:green]}, ".baz(1, 2, 3)"]]} <-
                    format("foo.bar.baz(1, 2, 3)", "foo.buzz.baz(1, 2, 3)")

      auto_assert {nil, nil} <- format("foo.bar(1, 2, 3)", "foo.bar 1, 2, 3")

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

      auto_assert {[
                     [
                       %Tag{data: "1", sequences: [:red]},
                       " + ",
                       %Tag{data: "2", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "2", sequences: [:green]},
                       " + ",
                       %Tag{data: "1", sequences: [:green]}
                     ]
                   ]} <- format("1 + 2", "2 + 1")

      auto_assert {[
                     [
                       "1 ",
                       %Tag{data: "+", sequences: [:red]},
                       " ",
                       %Tag{data: "2", sequences: [:red]}
                     ]
                   ],
                   [
                     [
                       %Tag{data: "2", sequences: [:green]},
                       " ",
                       %Tag{data: "-", sequences: [:green]},
                       " 1"
                     ]
                   ]} <- format("1 + 2", "2 - 1")
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

      auto_assert {[
                     [
                       "auto_assert %My.Qualified.Struct{",
                       %Tag{data: "a: \"a\"", sequences: [:red]},
                       ", ",
                       %Tag{data: "b: \"b\"", sequences: [:red]},
                       ", ",
                       %Tag{data: "c: \"c\"", sequences: [:red]},
                       ", ",
                       %Tag{data: "d: \"d\"", sequences: [:red]},
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
                       %Tag{
                         data: "a: \"a\", b: \"b\", c: \"c\", d: \"d\", e: \"e\"",
                         sequences: [:red]
                       },
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
                       %Tag{data: "pid when is_pid(pid)", sequences: [:green]},
                       " ",
                       %Tag{data: "<-", sequences: [:green]},
                       " self()"
                     ]
                   ]} <-
                    format("auto_assert self()", "auto_assert pid when is_pid(pid) <- self()")
    end

    test "formats ex_unit targets" do
      auto_assert {[
                     [
                       %Tag{data: "auto_assert pid when is_pid(pid) <- self()", sequences: [:red]}
                     ],
                     []
                   ],
                   [
                     [%Tag{data: "assert pid = self()", sequences: [:green]}],
                     [%Tag{data: "assert is_pid(pid)", sequences: [:green]}],
                     []
                   ]} <-
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
      auto_assert {[[]], [[%Tag{data: "1..10", sequences: [:green]}]]} <- format("", "1..10")

      auto_assert {[[]], [[%Tag{data: "1..10//2", sequences: [:green]}]]} <-
                    format("", "1..10//2")

      auto_assert {[[%Tag{data: "1", sequences: [:red]}, "..10"]],
                   [[%Tag{data: "2", sequences: [:green]}, "..10"]]} <-
                    format("1..10", "2..10")

      auto_assert {[["1..10//", %Tag{data: "1", sequences: [:red]}]],
                   [["1..10//", %Tag{data: "2", sequences: [:green]}]]} <-
                    format("1..10//1", "1..10//2")

      auto_assert {[
                     [
                       %Tag{data: "[", sequences: [:red]},
                       "1, 10",
                       %Tag{data: "]", sequences: [:red]}
                     ]
                   ],
                   [["1", %Tag{data: "..", sequences: [:green]}, "10"]]} <-
                    format("[1, 10]", "1..10")

      auto_assert {[["1", %Tag{data: "..", sequences: [:red]}, "10"]],
                   [
                     [
                       "1",
                       %Tag{data: "..", sequences: [:green]},
                       "10",
                       %Tag{data: "//", sequences: [:green]},
                       %Tag{data: "2", sequences: [:green]}
                     ]
                   ]} <- format("1..10", "1..10//2")
    end

    test "formats anonymous functions" do
      auto_assert {nil,
                   [
                     [
                       "auto_assert_raise ",
                       %Tag{data: "ArgumentError", sequences: [:green]},
                       ", fn -> some_call() end"
                     ]
                   ]} <-
                    format(
                      "auto_assert_raise fn -> some_call() end",
                      "auto_assert_raise ArgumentError, fn -> some_call() end"
                    )

      auto_assert {nil,
                   [
                     [
                       "auto_assert_raise ",
                       %Tag{data: "ArgumentError", sequences: [:green]},
                       ", ",
                       %Tag{data: "\"some message\"", sequences: [:green]},
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
                       %Tag{data: " ArgumentError", sequences: [:red]},
                       ", fn -> ",
                       %Tag{data: ":bad", sequences: [:red]},
                       " end"
                     ]
                   ],
                   [
                     [
                       "auto_assert_raise ",
                       %Tag{data: "Some.", sequences: [:green]},
                       %Tag{data: "Other", sequences: [:green]},
                       %Tag{data: ".Exception", sequences: [:green]},
                       ", fn -> ",
                       %Tag{data: ":good", sequences: [:green]},
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
                       %Tag{data: "Some.Exception", sequences: [:green]},
                       ", ",
                       %Tag{data: "\"with a message\"", sequences: [:green]},
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
      auto_assert {nil,
                   [
                     [
                       %Tag{data: "[", sequences: [:green]},
                       "x",
                       %Tag{data: "]", sequences: [:green]}
                     ]
                   ]} <- format("x", "[x]")

      auto_assert {[
                     [%Tag{data: "{", sequences: [:red]}, "x", %Tag{data: "}", sequences: [:red]}]
                   ],
                   [
                     [
                       %Tag{data: "[", sequences: [:green]},
                       "x",
                       %Tag{data: "]", sequences: [:green]}
                     ]
                   ]} <- format("{x}", "[x]")

      auto_assert {[["{[x], ", %Tag{data: "y", sequences: [:red]}, "}"]],
                   [["{[x, ", %Tag{data: "y", sequences: [:green]}, "]}"]]} <-
                    format("{[x], y}", "{[x, y]}")

      auto_assert {[["{[x, ", %Tag{data: "y", sequences: [:red]}, "]}"]],
                   [["{[x], ", %Tag{data: "y", sequences: [:green]}, "}"]]} <-
                    format("{[x, y]}", "{[x], y}")

      auto_assert {nil, [["[foo, ", %Tag{data: "[new]", sequences: [:green]}, ", [bar]]"]]} <-
                    format("[foo, [bar]]", "[foo, [new], [bar]]")

      auto_assert {nil,
                   [
                     [
                       "foo(",
                       %Tag{data: "new(", sequences: [:green]},
                       "bar(123)",
                       %Tag{data: ")", sequences: [:green]},
                       ")"
                     ]
                   ]} <- format("foo(bar(123))", "foo(new(bar(123)))")

      auto_assert {nil,
                   [
                     [
                       "foo(",
                       %Tag{data: "bar(", sequences: [:green]},
                       "123",
                       %Tag{data: ")", sequences: [:green]},
                       ")"
                     ]
                   ]} <- format("foo(123)", "foo(bar(123))")
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
                       %Tag{data: "line:", sequences: [:red]},
                       " 1, ",
                       %Tag{data: "column:", sequences: [:red]},
                       " 1",
                       %Tag{data: "]", sequences: [:red]},
                       ", [{:var, ",
                       %Tag{data: "[", sequences: [:red]},
                       "line: 1, ",
                       %Tag{data: "column: 2", sequences: [:red]},
                       %Tag{data: "]", sequences: [:red]},
                       ", :x}]}"
                     ]
                   ],
                   [
                     [
                       "{:-, ",
                       %Tag{data: "%{", sequences: [:green]},
                       %Tag{data: "column:", sequences: [:green]},
                       " 1, ",
                       %Tag{data: "line:", sequences: [:green]},
                       " 1",
                       %Tag{data: "}", sequences: [:green]},
                       ", [{:var, ",
                       %Tag{data: "%{", sequences: [:green]},
                       %Tag{data: "column: 2", sequences: [:green]},
                       ", line: 1",
                       %Tag{data: "}", sequences: [:green]},
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
                     ["auto_assert {", %Tag{data: "nil", sequences: [:red]}, ","],
                     ["             ["],
                     ["               ["],
                     ["                 \"[1, \","],
                     [
                       "                 %Tag{data: ",
                       %Tag{data: "\"[\"", sequences: [:red]},
                       ", sequences: [:green]},"
                     ],
                     ["                 ", %Tag{data: "\"2_000\"", sequences: [:red]}, ","],
                     [
                       "                 ",
                       %Tag{data: "%Tag{data: \"]\", sequences: [:green]}", sequences: [:red]},
                       ","
                     ],
                     ["                 \"]\""],
                     ["               ]"],
                     ["             ]} <- format(\"[1, 2_000]\", \"[1, [3_000]]\")"],
                     []
                   ],
                   [
                     [
                       "auto_assert {",
                       %Tag{
                         data: "[[\"[1, \", %Tag{data: \"2_000\", sequences: [:red]}, \"]\"]]",
                         sequences: [:green]
                       },
                       ","
                     ],
                     [
                       "             [[\"[1, \", %Tag{data: ",
                       %Tag{data: "\"[3_000]\"", sequences: [:green]},
                       ", sequences: [:green]}, \"]\"]]} <-"
                     ],
                     ["              format(\"[1, 2_000]\", \"[1, [3_000]]\")"],
                     []
                   ]} <- format(left, right)
    end

    if Version.match?(System.version(), ">= 1.14.4") do
      test "elixir bug: escaped interpolation column count" do
        auto_assert {[["auto_assert ", %Tag{data: "res", sequences: [:red]}]],
                     [["auto_assert ", %Tag{data: "{:ok, \"\\\#{foo}\"}", sequences: [:green]}]]} <-
                      format(~S|auto_assert res|, ~S|auto_assert {:ok, "\#{foo}"}|)
      end
    end
  end
end
