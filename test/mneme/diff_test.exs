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
    end

    test "formats map to struct" do
      auto_assert {nil, [["%", %Tag{data: "MyStruct", sequences: [:green]}, "{foo: 1}"]]} <-
                    format("%{foo: 1}", "%MyStruct{foo: 1}")

      auto_assert {[["%", %Tag{data: "MyStruct", sequences: [:red]}, "{foo: 1}"]], nil} <-
                    format("%MyStruct{foo: 1}", "%{foo: 1}")
    end

    test "formats calls" do
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

    test "formats pins" do
      auto_assert format("me", "^me <- me")
    end

    test "hmm" do
      auto_assert {[
                     %Graph.Edge{
                       label: %Mneme.Diff.Edge{
                         depth_difference: 0,
                         kind: :branch,
                         side: :right,
                         type: :novel
                       },
                       v1: %Mneme.Diff.Vertex{
                         id: 38_144_310,
                         left:
                           {{:var, [line: 1, column: 1, __hash__: 69_345_172, __id__: 59_972_372],
                             :me}, nil},
                         left_branch?: false,
                         right:
                           {{:<-, [line: 1, column: 5, __hash__: 114_825_407, __id__: 31_662_927],
                             [
                               {:^,
                                [line: 1, column: 1, __hash__: 97_995_621, __id__: 35_560_687],
                                [
                                  {:var,
                                   [line: 1, column: 2, __hash__: 69_345_172, __id__: 59_972_372],
                                   :me}
                                ]},
                               {:var,
                                [line: 1, column: 8, __hash__: 69_345_172, __id__: 33_030_443],
                                :me}
                             ]}, nil},
                         right_branch?: true
                       },
                       v2: %Mneme.Diff.Vertex{
                         id: 123_829_293,
                         left:
                           {{:var, [line: 1, column: 1, __hash__: 69_345_172, __id__: 59_972_372],
                             :me}, nil},
                         left_branch?: false,
                         right:
                           {{:^, [line: 1, column: 1, __hash__: 97_995_621, __id__: 35_560_687],
                             [
                               {:var,
                                [line: 1, column: 2, __hash__: 69_345_172, __id__: 59_972_372],
                                :me}
                             ]},
                            %{
                              l: nil,
                              ptree:
                                {{:<-,
                                  [line: 1, column: 5, __hash__: 114_825_407, __id__: 31_662_927],
                                  [
                                    {:^,
                                     [
                                       line: 1,
                                       column: 1,
                                       __hash__: 97_995_621,
                                       __id__: 35_560_687
                                     ],
                                     [
                                       {:var,
                                        [
                                          line: 1,
                                          column: 2,
                                          __hash__: 69_345_172,
                                          __id__: 59_972_372
                                        ], :me}
                                     ]},
                                    {:var,
                                     [
                                       line: 1,
                                       column: 8,
                                       __hash__: 69_345_172,
                                       __id__: 33_030_443
                                     ], :me}
                                  ]}, nil},
                              r: [
                                {:var,
                                 [line: 1, column: 8, __hash__: 69_345_172, __id__: 33_030_443],
                                 :me}
                              ]
                            }},
                         right_branch?: true
                       },
                       weight: 300
                     },
                     %Graph.Edge{
                       label: %Mneme.Diff.Edge{
                         depth_difference: 0,
                         kind: :branch,
                         side: :right,
                         type: :novel
                       },
                       v1: %Mneme.Diff.Vertex{
                         id: 123_829_293,
                         left:
                           {{:var, [line: 1, column: 1, __hash__: 69_345_172, __id__: 59_972_372],
                             :me}, nil},
                         left_branch?: false,
                         right:
                           {{:^, [line: 1, column: 1, __hash__: 97_995_621, __id__: 35_560_687],
                             [
                               {:var,
                                [line: 1, column: 2, __hash__: 69_345_172, __id__: 59_972_372],
                                :me}
                             ]},
                            %{
                              l: nil,
                              ptree:
                                {{:<-,
                                  [line: 1, column: 5, __hash__: 114_825_407, __id__: 31_662_927],
                                  [
                                    {:^,
                                     [
                                       line: 1,
                                       column: 1,
                                       __hash__: 97_995_621,
                                       __id__: 35_560_687
                                     ],
                                     [
                                       {:var,
                                        [
                                          line: 1,
                                          column: 2,
                                          __hash__: 69_345_172,
                                          __id__: 59_972_372
                                        ], :me}
                                     ]},
                                    {:var,
                                     [
                                       line: 1,
                                       column: 8,
                                       __hash__: 69_345_172,
                                       __id__: 33_030_443
                                     ], :me}
                                  ]}, nil},
                              r: [
                                {:var,
                                 [line: 1, column: 8, __hash__: 69_345_172, __id__: 33_030_443],
                                 :me}
                              ]
                            }},
                         right_branch?: true
                       },
                       v2: %Mneme.Diff.Vertex{
                         id: 71_470_566,
                         left:
                           {{:var, [line: 1, column: 1, __hash__: 69_345_172, __id__: 59_972_372],
                             :me}, nil},
                         left_branch?: false,
                         right:
                           {{:var, [line: 1, column: 2, __hash__: 69_345_172, __id__: 59_972_372],
                             :me},
                            %{
                              l: nil,
                              ptree:
                                {{:^,
                                  [line: 1, column: 1, __hash__: 97_995_621, __id__: 35_560_687],
                                  [
                                    {:var,
                                     [
                                       line: 1,
                                       column: 2,
                                       __hash__: 69_345_172,
                                       __id__: 59_972_372
                                     ], :me}
                                  ]},
                                 %{
                                   l: nil,
                                   ptree:
                                     {{:<-,
                                       [
                                         line: 1,
                                         column: 5,
                                         __hash__: 114_825_407,
                                         __id__: 31_662_927
                                       ],
                                       [
                                         {:^,
                                          [
                                            line: 1,
                                            column: 1,
                                            __hash__: 97_995_621,
                                            __id__: 35_560_687
                                          ],
                                          [
                                            {:var,
                                             [
                                               line: 1,
                                               column: 2,
                                               __hash__: 69_345_172,
                                               __id__: 59_972_372
                                             ], :me}
                                          ]},
                                         {:var,
                                          [
                                            line: 1,
                                            column: 8,
                                            __hash__: 69_345_172,
                                            __id__: 33_030_443
                                          ], :me}
                                       ]}, nil},
                                   r: [
                                     {:var,
                                      [
                                        line: 1,
                                        column: 8,
                                        __hash__: 69_345_172,
                                        __id__: 33_030_443
                                      ], :me}
                                   ]
                                 }},
                              r: nil
                            }},
                         right_branch?: false
                       },
                       weight: 300
                     },
                     %Graph.Edge{
                       label: %Mneme.Diff.Edge{depth_difference: 2, kind: :leaf, type: :unchanged},
                       v1: %Mneme.Diff.Vertex{
                         id: 71_470_566,
                         left:
                           {{:var, [line: 1, column: 1, __hash__: 69_345_172, __id__: 59_972_372],
                             :me}, nil},
                         left_branch?: false,
                         right:
                           {{:var, [line: 1, column: 2, __hash__: 69_345_172, __id__: 59_972_372],
                             :me},
                            %{
                              l: nil,
                              ptree:
                                {{:^,
                                  [line: 1, column: 1, __hash__: 97_995_621, __id__: 35_560_687],
                                  [
                                    {:var,
                                     [
                                       line: 1,
                                       column: 2,
                                       __hash__: 69_345_172,
                                       __id__: 59_972_372
                                     ], :me}
                                  ]},
                                 %{
                                   l: nil,
                                   ptree:
                                     {{:<-,
                                       [
                                         line: 1,
                                         column: 5,
                                         __hash__: 114_825_407,
                                         __id__: 31_662_927
                                       ],
                                       [
                                         {:^,
                                          [
                                            line: 1,
                                            column: 1,
                                            __hash__: 97_995_621,
                                            __id__: 35_560_687
                                          ],
                                          [
                                            {:var,
                                             [
                                               line: 1,
                                               column: 2,
                                               __hash__: 69_345_172,
                                               __id__: 59_972_372
                                             ], :me}
                                          ]},
                                         {:var,
                                          [
                                            line: 1,
                                            column: 8,
                                            __hash__: 69_345_172,
                                            __id__: 33_030_443
                                          ], :me}
                                       ]}, nil},
                                   r: [
                                     {:var,
                                      [
                                        line: 1,
                                        column: 8,
                                        __hash__: 69_345_172,
                                        __id__: 33_030_443
                                      ], :me}
                                   ]
                                 }},
                              r: nil
                            }},
                         right_branch?: false
                       },
                       v2: %Mneme.Diff.Vertex{
                         id: 74_505_484,
                         left_branch?: false,
                         right:
                           {{:var, [line: 1, column: 8, __hash__: 69_345_172, __id__: 33_030_443],
                             :me},
                            %{
                              l: [
                                {:^,
                                 [line: 1, column: 1, __hash__: 97_995_621, __id__: 35_560_687],
                                 [
                                   {:var,
                                    [
                                      line: 1,
                                      column: 2,
                                      __hash__: 69_345_172,
                                      __id__: 59_972_372
                                    ], :me}
                                 ]}
                              ],
                              ptree:
                                {{:<-,
                                  [line: 1, column: 5, __hash__: 114_825_407, __id__: 31_662_927],
                                  [
                                    {:^,
                                     [
                                       line: 1,
                                       column: 1,
                                       __hash__: 97_995_621,
                                       __id__: 35_560_687
                                     ],
                                     [
                                       {:var,
                                        [
                                          line: 1,
                                          column: 2,
                                          __hash__: 69_345_172,
                                          __id__: 59_972_372
                                        ], :me}
                                     ]},
                                    {:var,
                                     [
                                       line: 1,
                                       column: 8,
                                       __hash__: 69_345_172,
                                       __id__: 33_030_443
                                     ], :me}
                                  ]}, nil},
                              r: []
                            }},
                         right_branch?: false
                       },
                       weight: 3
                     },
                     %Graph.Edge{
                       label: %Mneme.Diff.Edge{
                         depth_difference: 0,
                         kind: :leaf,
                         side: :right,
                         type: :novel
                       },
                       v1: %Mneme.Diff.Vertex{
                         id: 74_505_484,
                         left_branch?: false,
                         right:
                           {{:var, [line: 1, column: 8, __hash__: 69_345_172, __id__: 33_030_443],
                             :me},
                            %{
                              l: [
                                {:^,
                                 [line: 1, column: 1, __hash__: 97_995_621, __id__: 35_560_687],
                                 [
                                   {:var,
                                    [
                                      line: 1,
                                      column: 2,
                                      __hash__: 69_345_172,
                                      __id__: 59_972_372
                                    ], :me}
                                 ]}
                              ],
                              ptree:
                                {{:<-,
                                  [line: 1, column: 5, __hash__: 114_825_407, __id__: 31_662_927],
                                  [
                                    {:^,
                                     [
                                       line: 1,
                                       column: 1,
                                       __hash__: 97_995_621,
                                       __id__: 35_560_687
                                     ],
                                     [
                                       {:var,
                                        [
                                          line: 1,
                                          column: 2,
                                          __hash__: 69_345_172,
                                          __id__: 59_972_372
                                        ], :me}
                                     ]},
                                    {:var,
                                     [
                                       line: 1,
                                       column: 8,
                                       __hash__: 69_345_172,
                                       __id__: 33_030_443
                                     ], :me}
                                  ]}, nil},
                              r: []
                            }},
                         right_branch?: false
                       },
                       v2: %Mneme.Diff.Vertex{
                         id: 5_242_045,
                         left_branch?: false,
                         right_branch?: false
                       },
                       weight: 300
                     }
                   ],
                   graph: %{num_edges: 9, num_vertices: 8, size_in_bytes: 16208, type: :directed},
                   time_ms: 3} <- Diff.compute_shortest_path!("me", "^me <- me")
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

  describe "compute/2" do
    @describetag skip: true
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
