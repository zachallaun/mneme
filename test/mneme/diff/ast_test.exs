defmodule Mneme.Diff.ASTTest do
  use ExUnit.Case
  use Mneme

  import Mneme.Diff.AST2

  # Notes:
  #
  # * Key-value pairs should always be in raw, 2-element tuples. We can
  #   differentiate between keyword syntax and map `=>` syntax by looking
  #   for the `format: :keyword` metadata in the first element. Need to
  #   confirm, but I think that the only 2-element tuples in the AST
  #   should be kw syntax in collections/calls or `=>` pairs in maps.
  #
  # * Lists that are "invisible" in the syntax appear as `[]` literals
  #   instead of `{:"[]", _meta, _args}` nodes. Examples include last-
  #   element kw-args in calls and collections or in sigil nodes. These
  #   lists should still be walked when traversing but should not be
  #   considered for matching. (I think...?)

  describe "parse_string!/1 enriched ASTs" do
    test "numbers" do
      auto_assert {:int, [token: "1", line: 1, column: 1], 1} <- parse_string!("1")
      auto_assert {:int, [token: "1_000", line: 1, column: 1], 1000} <- parse_string!("1_000")
      auto_assert {:int, [token: "?a", line: 1, column: 1], 97} <- parse_string!("?a")
      auto_assert {:float, [token: "1.0", line: 1, column: 1], 1.0} <- parse_string!("1.0")

      auto_assert {:float, [token: "1_000.0", line: 1, column: 1], 1000.0} <-
                    parse_string!("1_000.0")

      auto_assert {:float, [token: "1_000.4e4", line: 1, column: 1], 10_004_000.0} <-
                    parse_string!("1_000.4e4")

      # note that negative numbers parse as a call using the unary `-`
      auto_assert {:-, [line: 1, column: 1], [{:int, [token: "1", line: 1, column: 2], 1}]} <-
                    parse_string!("-1")
    end

    test "atoms literals" do
      auto_assert {:atom, [line: 1, column: 1], :foo} <- parse_string!(":foo")

      auto_assert {:atom, [delimiter: "\"", line: 1, column: 1], :"foo-bar"} <-
                    parse_string!(~s(:"foo-bar"))

      # booleans are atoms with special-case formatting handled by Macro.inspect_atom/2
      auto_assert {:atom, [line: 1, column: 1], true} <- parse_string!("true")
    end

    test "string literals" do
      auto_assert {:string, [delimiter: "\"", line: 1, column: 1], "foo"} <-
                    parse_string!(~s("foo"))

      auto_assert {:string, [delimiter: "\"\"\"", indentation: 0, line: 1, column: 1],
                   """
                   foo
                   bar
                   """} <- parse_string!(~s("""\nfoo\nbar\n"""))

      auto_assert {:string, [delimiter: "\"\"\"", indentation: 2, line: 1, column: 1],
                   """
                   foo
                   bar
                   """} <- parse_string!(~s("""\n  foo\n  bar\n  """))
    end

    test "binary literals" do
      auto_assert {:<<>>, [closing: [line: 1, column: 13], line: 1, column: 1],
                   [
                     {:int, [token: "?a", line: 1, column: 3], 97},
                     {:int, [token: "?b", line: 1, column: 7], 98},
                     {:int, [token: "?c", line: 1, column: 11], 99}
                   ]} <- parse_string!("<<?a, ?b, ?c>>")

      auto_assert {:<<>>, [closing: [line: 1, column: 10], line: 1, column: 1],
                   [
                     {:int, [token: "0", line: 1, column: 3], 0},
                     {:int, [token: "1", line: 1, column: 6], 1},
                     {:var, [line: 1, column: 9], :x}
                   ]} <- parse_string!("<<0, 1, x>>")

      auto_assert {:<<>>, [closing: [line: 1, column: 40], line: 1, column: 1],
                   [
                     {:int, [token: "0", line: 1, column: 3], 0},
                     {:"::", [line: 1, column: 10],
                      [
                        {:var, [line: 1, column: 6], :head},
                        {:-, [line: 1, column: 18],
                         [
                           {:var, [line: 1, column: 12], :binary},
                           {:size, [closing: [line: 1, column: 25], line: 1, column: 19],
                            [{:int, [token: "4", line: 1, column: 24], 4}]}
                         ]}
                      ]},
                     {:"::", [line: 1, column: 32],
                      [
                        {:var, [line: 1, column: 28], :rest},
                        {:var, [line: 1, column: 34], :binary}
                      ]}
                   ]} <- parse_string!("<<0, head::binary-size(4), rest::binary>>")
    end

    test "charlist literals" do
      auto_assert {:charlist, [delimiter: "'", line: 1, column: 1], "foo"} <-
                    parse_string!("'foo'")

      auto_assert {:charlist, [delimiter: "'''", indentation: 0, line: 1, column: 1],
                   """
                   foo
                   bar
                   """} <- parse_string!(~s('''\nfoo\nbar\n'''))
    end

    test "tuples" do
      auto_assert {:{}, [closing: [line: 1, column: 2], line: 1, column: 1], []} <-
                    parse_string!("{}")

      auto_assert {:{}, [closing: [line: 1, column: 9], line: 1, column: 1],
                   [
                     {:int, [token: "1", line: 1, column: 2], 1},
                     {:int, [token: "2", line: 1, column: 5], 2},
                     {:int, [token: "3", line: 1, column: 8], 3}
                   ]} <- parse_string!("{1, 2, 3}")

      auto_assert {:{}, [closing: [line: 1, column: 14], line: 1, column: 1],
                   [
                     {:int, [token: "1", line: 1, column: 2], 1},
                     {:int, [token: "2", line: 1, column: 5], 2},
                     [
                       {{:atom, [format: :keyword, line: 1, column: 8], :foo},
                        {:int, [token: "3", line: 1, column: 13], 3}}
                     ]
                   ]} <- parse_string!("{1, 2, foo: 3}")
    end

    test "lists" do
      auto_assert {:"[]", [closing: [line: 1, column: 2], line: 1, column: 1], []} <-
                    parse_string!("[]")

      auto_assert {:"[]", [closing: [line: 1, column: 9], line: 1, column: 1],
                   [
                     {:int, [token: "1", line: 1, column: 2], 1},
                     {:int, [token: "2", line: 1, column: 5], 2},
                     {:int, [token: "3", line: 1, column: 8], 3}
                   ]} <- parse_string!("[1, 2, 3]")

      auto_assert {:"[]", [closing: [line: 1, column: 14], line: 1, column: 1],
                   [
                     {:int, [token: "1", line: 1, column: 2], 1},
                     {:int, [token: "2", line: 1, column: 5], 2},
                     {{:atom, [format: :keyword, line: 1, column: 8], :foo},
                      {:int, [token: "3", line: 1, column: 13], 3}}
                   ]} <- parse_string!("[1, 2, foo: 3]")

      auto_assert {:"[]", [closing: [line: 1, column: 16], line: 1, column: 1],
                   [
                     {{:atom, [format: :keyword, line: 1, column: 2], :foo},
                      {:int, [token: "1", line: 1, column: 7], 1}},
                     {{:atom, [format: :keyword, line: 1, column: 10], :bar},
                      {:int, [token: "2", line: 1, column: 15], 2}}
                   ]} <- parse_string!("[foo: 1, bar: 2]")

      auto_assert {:"[]", [closing: [line: 1, column: 22], line: 1, column: 1],
                   [
                     {:{}, [closing: [line: 1, column: 10], line: 1, column: 2],
                      [
                        {:atom, [line: 1, column: 3], :foo},
                        {:int, [token: "1", line: 1, column: 9], 1}
                      ]},
                     {:{}, [closing: [line: 1, column: 21], line: 1, column: 13],
                      [
                        {:atom, [line: 1, column: 14], :bar},
                        {:int, [token: "2", line: 1, column: 20], 2}
                      ]}
                   ]} <- parse_string!("[{:foo, 1}, {:bar, 2}]")
    end

    test "maps" do
      auto_assert {:%{}, [closing: [line: 1, column: 3], line: 1, column: 2], []} <-
                    parse_string!("%{}")

      auto_assert {:%{}, [closing: [line: 1, column: 12], line: 1, column: 2],
                   [
                     {{:atom, [line: 1, column: 3], :foo},
                      {:int, [token: "1", line: 1, column: 11], 1}}
                   ]} <- parse_string!("%{:foo => 1}")

      auto_assert {:%{}, [closing: [line: 1, column: 9], line: 1, column: 2],
                   [
                     {{:atom, [format: :keyword, line: 1, column: 3], :foo},
                      {:int, [token: "1", line: 1, column: 8], 1}}
                   ]} <- parse_string!("%{foo: 1}")
    end

    # TODO: Test with multi-character sigils which will come in a later
    # version of Elixir:
    # https://groups.google.com/g/elixir-lang-core/c/cocMcghahs4
    test "sigils" do
      auto_assert {:"~", [delimiter: "(", line: 1, column: 1],
                   [
                     {:string, [line: 1, column: 2], "s"},
                     [{:string, [line: 1, column: 4], "foo"}],
                     [117]
                   ]} <- parse_string!("~s(foo)u")

      auto_assert {:"~", [delimiter: "(", line: 1, column: 1],
                   [
                     {:string, [line: 1, column: 2], "s"},
                     [{:string, [line: 1, column: 4], "foo"}],
                     []
                   ]} <- parse_string!("~s(foo)")

      auto_assert {:"~", [indentation: 0, delimiter: "\"\"\"", line: 1, column: 1],
                   [
                     {:string, [line: 1, column: 2], "s"},
                     [
                       {:string, [line: 2, column: 1],
                        """
                        foo
                        bar
                        """}
                     ],
                     []
                   ]} <- parse_string!(~s(~s"""\nfoo\nbar\n"""))
    end

    test "vars" do
      auto_assert {:var, [line: 1, column: 1], :foo} <- parse_string!("foo")

      auto_assert {:"[]", [closing: [line: 1, column: 10], line: 1, column: 1],
                   [{:var, [line: 1, column: 2], :foo}, {:var, [line: 1, column: 7], :bar}]} <-
                    parse_string!("[foo, bar]")
    end

    test "aliases" do
      auto_assert {:__aliases__, [last: [line: 1, column: 1], line: 1, column: 1],
                   [{:var, [line: 1, column: 1], :Foo}]} <- parse_string!("Foo")

      auto_assert {:__aliases__, [last: [line: 1, column: 5], line: 1, column: 1],
                   [{:var, [line: 1, column: 1], :Foo}, {:var, [line: 1, column: 5], :Bar}]} <-
                    parse_string!("Foo.Bar")

      auto_assert {:__aliases__, [last: [line: 1, column: 9], line: 1, column: 1],
                   [
                     {:var, [line: 1, column: 1], :Foo},
                     {:var, [line: 1, column: 5], :Bar},
                     {:var, [line: 1, column: 9], :Baz}
                   ]} <- parse_string!("Foo.Bar.Baz")

      auto_assert {:__aliases__, [last: [line: 2, column: 3], line: 1, column: 1],
                   [{:var, [line: 1, column: 1], :Foo}, {:var, [line: 2, column: 3], :Bar}]} <-
                    parse_string!("Foo.\n  Bar")
    end

    test "unqualified calls" do
      auto_assert {:is_pid, [closing: [line: 1, column: 8], line: 1, column: 1], []} <-
                    parse_string!("is_pid()")

      # Calls with parens have a `:closing` meta
      auto_assert {:is_pid, [closing: [line: 1, column: 9], line: 1, column: 1],
                   [{:int, [token: "1", line: 1, column: 8], 1}]} <- parse_string!("is_pid(1)")

      # Calls without parens do not have a `:closing` meta
      auto_assert {:is_pid, [line: 1, column: 1], [{:int, [token: "1", line: 1, column: 8], 1}]} <-
                    parse_string!("is_pid 1")

      auto_assert {:is_pid, [closing: [line: 1, column: 19], line: 1, column: 1],
                   [
                     {:int, [token: "1", line: 1, column: 8], 1},
                     [
                       {{:atom, [format: :keyword, line: 1, column: 11], :foo},
                        {:var, [line: 1, column: 16], :bar}}
                     ]
                   ]} <- parse_string!("is_pid(1, foo: bar)")

      auto_assert {:is_pid, [closing: [line: 1, column: 24], line: 1, column: 1],
                   [
                     {:int, [token: "1", line: 1, column: 8], 1},
                     {:"[]", [closing: [line: 1, column: 23], line: 1, column: 11],
                      [
                        {:{}, [closing: [line: 1, column: 22], line: 1, column: 12],
                         [
                           {:atom, [line: 1, column: 13], :foo},
                           {:var, [line: 1, column: 19], :bar}
                         ]}
                      ]}
                   ]} <- parse_string!("is_pid(1, [{:foo, bar}])")

      auto_assert {:is_pid, [line: 1, column: 1],
                   [
                     {:int, [token: "1", line: 1, column: 8], 1},
                     [
                       {{:atom, [format: :keyword, line: 1, column: 11], :foo},
                        {:var, [line: 1, column: 16], :bar}}
                     ]
                   ]} <- parse_string!("is_pid 1, foo: bar")
    end

    test "qualified calls" do
      # anonymous fn syntax has a single arg
      auto_assert {{:., [line: 1, column: 4], [{:var, [line: 1, column: 1], :foo}]},
                   [closing: [line: 1, column: 6], line: 1, column: 4],
                   []} <- parse_string!("foo.()")

      # usual chaining has 2 args
      auto_assert {{:., [line: 1, column: 4],
                    [{:var, [line: 1, column: 1], :foo}, {:var, [line: 1, column: 5], :bar}]},
                   [closing: [line: 1, column: 9], line: 1, column: 5],
                   []} <- parse_string!("foo.bar()")

      auto_assert {{:., [line: 1, column: 4],
                    [
                      {:__aliases__, [last: [line: 1, column: 1], line: 1, column: 1],
                       [{:var, [line: 1, column: 1], :Foo}]},
                      {:var, [line: 1, column: 5], :bar}
                    ]}, [closing: [line: 1, column: 9], line: 1, column: 5],
                   []} <- parse_string!("Foo.bar()")

      # rightmost . is on the outside and has meta about parens, e.g. `:closing`
      # note that `{:., [], []}` is always at the head of a call, e.g. `{{:., [], []}, [], []}`
      auto_assert {{:., [line: 1, column: 8],
                    [
                      {{:., [line: 1, column: 4],
                        [{:var, [line: 1, column: 1], :foo}, {:var, [line: 1, column: 5], :bar}]},
                       [no_parens: true, line: 1, column: 5], []},
                      {:var, [line: 1, column: 9], :baz}
                    ]}, [closing: [line: 1, column: 13], line: 1, column: 9],
                   []} <- parse_string!("foo.bar.baz()")

      # example without parens, no `:closing` meta
      auto_assert {{:., [line: 1, column: 8],
                    [
                      {{:., [line: 1, column: 4],
                        [{:var, [line: 1, column: 1], :foo}, {:var, [line: 1, column: 5], :bar}]},
                       [no_parens: true, line: 1, column: 5], []},
                      {:var, [line: 1, column: 9], :baz}
                    ]}, [line: 1, column: 9],
                   [{:int, [token: "1", line: 1, column: 13], 1}]} <-
                    parse_string!("foo.bar.baz 1")

      # inner calls have `:closing` meta
      auto_assert {{:., [line: 1, column: 10],
                    [
                      {{:., [line: 1, column: 4],
                        [{:var, [line: 1, column: 1], :foo}, {:var, [line: 1, column: 5], :bar}]},
                       [closing: [line: 1, column: 9], line: 1, column: 5], []},
                      {:var, [line: 1, column: 11], :baz}
                    ]}, [closing: [line: 1, column: 15], line: 1, column: 11],
                   []} <- parse_string!("foo.bar().baz()")

      # the inner `:.` tuple has a single arg and its call has closing meta, indicating
      # a `foo.()`
      auto_assert {{:., [line: 1, column: 7],
                    [
                      {{:., [line: 1, column: 4], [{:var, [line: 1, column: 1], :foo}]},
                       [closing: [line: 1, column: 6], line: 1, column: 4], []},
                      {:var, [line: 1, column: 8], :bar}
                    ]}, [closing: [line: 1, column: 12], line: 1, column: 8],
                   []} <- parse_string!("foo.().bar()")
    end

    test "unary operators" do
      auto_assert {:-, [line: 1, column: 1], [{:var, [line: 1, column: 2], :x}]} <-
                    parse_string!("-x")

      auto_assert {:-, [line: 1, column: 1], [{:int, [token: "1", line: 1, column: 2], 1}]} <-
                    parse_string!("-1")

      auto_assert {:^, [line: 1, column: 1], [{:var, [line: 1, column: 2], :foo}]} <-
                    parse_string!("^foo")
    end

    # note: includes `|>`
    test "binary operators" do
      auto_assert {:+, [line: 1, column: 3],
                   [{:var, [line: 1, column: 1], :x}, {:var, [line: 1, column: 5], :y}]} <-
                    parse_string!("x + y")

      auto_assert {:when, [line: 1, column: 5],
                   [
                     {:var, [line: 1, column: 1], :pid},
                     {:is_pid, [closing: [line: 1, column: 20], line: 1, column: 10],
                      [{:var, [line: 1, column: 17], :pid}]}
                   ]} <- parse_string!("pid when is_pid(pid)")

      auto_assert {:<-, [line: 1, column: 22],
                   [
                     {:when, [line: 1, column: 5],
                      [
                        {:var, [line: 1, column: 1], :pid},
                        {:is_pid, [closing: [line: 1, column: 20], line: 1, column: 10],
                         [{:var, [line: 1, column: 17], :pid}]}
                      ]},
                     {:self, [closing: [line: 1, column: 30], line: 1, column: 25], []}
                   ]} <- parse_string!("pid when is_pid(pid) <- self()")

      auto_assert {:|>, [line: 1, column: 14],
                   [
                     {:|>, [line: 1, column: 5],
                      [
                        {:var, [line: 1, column: 1], :foo},
                        {:bar, [closing: [line: 1, column: 12], line: 1, column: 8], []}
                      ]},
                     {:baz, [closing: [line: 1, column: 21], line: 1, column: 17], []}
                   ]} <- parse_string!("foo |> bar() |> baz()")
    end
  end
end
