defmodule Mneme.DiffTest do
  use ExUnit.Case
  use Mneme, action: :accept, default_pattern: :last

  import Mneme.Diff

  describe "graph" do
    # @mneme_describe action: :prompt

    @mneme action: :prompt
    test "lazy" do
      auto_assert %{
                    graph: %{
                      num_edges: 12,
                      num_vertices: 11,
                      size_in_bytes: 36888,
                      type: :directed
                    },
                    result: [eq: :"[]", eq: 1, ins: :"[]", eq: 2]
                  } <- shortest_path!("[1, 2]", "[1, [2]]")

      auto_assert %{
                    graph: %{
                      num_edges: 29,
                      num_vertices: 20,
                      size_in_bytes: 84328,
                      type: :directed
                    },
                    result: [eq: :"[]", del: :"[]", eq: 1, ins: :"[]", eq: 2]
                  } <- shortest_path!("[[1], 2]", "[1, [2]]")

      auto_assert %{
                    graph: %{
                      num_edges: 23,
                      num_vertices: 19,
                      size_in_bytes: 98136,
                      type: :directed
                    },
                    result: [eq: :%{}, eq: :{}, ins: :{}, ins: :bar, ins: 2]
                  } <- shortest_path!("%{foo: 1}", "%{foo: 1, bar: 2}")

      auto_assert %{
                    graph: %{
                      num_edges: 19,
                      num_vertices: 15,
                      size_in_bytes: 77752,
                      type: :directed
                    },
                    result: [ins: :%, ins: :__aliases__, ins: :MyStruct, eq: :%{}]
                  } <- shortest_path!("%{foo: 1}", "%MyStruct{foo: 1}")

      auto_assert %{
                    graph: %{
                      num_edges: 14,
                      num_vertices: 13,
                      size_in_bytes: 59040,
                      type: :directed
                    },
                    result: [eq: :"[]", eq: 1, ins: :"[]", eq: 2, eq: 3]
                  } <- shortest_path!("[1, 2, 3]", "[1, [2, 3]]")

      auto_assert %{
                    graph: %{
                      num_edges: 21,
                      num_vertices: 19,
                      size_in_bytes: 65336,
                      type: :directed
                    },
                    result: [eq: :when, eq: :foo, ins: :is_reference, del: :is_pid, eq: :foo]
                  } <- shortest_path!("foo when is_pid(foo)", "foo when is_reference(foo)")

      auto_assert %{
                    graph: %{num_edges: 4, num_vertices: 5, size_in_bytes: 6176, type: :directed},
                    result: [ins: :"[]", eq: :x]
                  } <- shortest_path!("x", "[x]")

      auto_assert %{
                    graph: %{num_edges: 9, num_vertices: 9, size_in_bytes: 13992, type: :directed},
                    result: [ins: :"[]", del: :{}, eq: :x]
                  } <- shortest_path!("{x}", "[x]")

      auto_assert %{
                    graph: %{
                      num_edges: 30,
                      num_vertices: 25,
                      size_in_bytes: 226_200,
                      type: :directed
                    },
                    result: [eq: :"[]", ins: :"[]", eq: :{}, del: :"[]", eq: 2, eq: 3]
                  } <- shortest_path!("[{{1}}, [2, 3]]", "[[{{1}}, 2, 3]]")

      auto_assert %{
                    graph: %{
                      num_edges: 34,
                      num_vertices: 26,
                      size_in_bytes: 140_760,
                      type: :directed
                    },
                    result: [eq: :"[]", eq: 1, ins: :"[]", ins: 2, eq: :"[]"]
                  } <- shortest_path!("[1, [3]]", "[1, [2], [3]]", true)

      auto_assert %{
                    graph: %{
                      num_edges: 152,
                      num_vertices: 92,
                      size_in_bytes: 1_100_848,
                      type: :directed
                    },
                    result: [
                      ins: :%,
                      ins: :__aliases__,
                      ins: :MyStruct,
                      eq: :%{},
                      eq: :{},
                      eq: :foo,
                      ins: 2,
                      del: 1,
                      eq: :{},
                      ins: :baz,
                      del: :bar,
                      eq: :"[]"
                    ]
                  } <- shortest_path!("%{foo: 1, bar: [2]}", "%MyStruct{foo: 2, baz: [2]}")

      auto_assert %{
                    graph: %{
                      num_edges: 195,
                      num_vertices: 115,
                      size_in_bytes: 1_680_544,
                      type: :directed
                    },
                    result: [
                      ins: :%,
                      ins: :__aliases__,
                      ins: :MyStruct,
                      eq: :%{},
                      eq: :{},
                      eq: :foo,
                      ins: 2,
                      del: 1,
                      eq: :{},
                      del: :bar,
                      ins: :baz,
                      eq: :"[]",
                      eq: 2,
                      del: :"[]",
                      eq: 3
                    ],
                    times: [build_graph: 0, find_path: 1, total: 1]
                  } <-
                    shortest_path!(
                      "%{foo: 1, bar: [2, [3]]}",
                      "%MyStruct{foo: 2, baz: [2, 3]}"
                    )

      auto_assert %{
                    graph: %{
                      num_edges: 4829,
                      num_vertices: 2442,
                      size_in_bytes: 234_290_024,
                      type: :directed
                    },
                    result: [
                      eq: :%{},
                      eq: :{},
                      eq: :graph,
                      eq: :%{},
                      eq: :{},
                      eq: :num_edges,
                      ins: 195,
                      del: 152,
                      eq: :{},
                      eq: :num_vertices,
                      ins: 115,
                      del: 92,
                      eq: :{},
                      eq: :size_in_bytes,
                      ins: 1_680_544,
                      del: 1_100_848,
                      eq: :{},
                      eq: :{},
                      eq: :result,
                      eq: :"[]",
                      eq: :{},
                      eq: :{},
                      eq: :{},
                      eq: :{},
                      eq: :{},
                      eq: :{},
                      eq: :{},
                      eq: :{},
                      eq: :{},
                      ins: :{},
                      ins: :del,
                      ins: :bar,
                      eq: :{},
                      eq: :{},
                      ins: :eq,
                      del: :del,
                      ins: :"[]",
                      del: :bar,
                      eq: :{},
                      eq: :eq,
                      ins: 2,
                      ins: :{},
                      ins: :del,
                      eq: :"[]",
                      ins: :{},
                      ins: :eq,
                      ins: 3,
                      ins: :{},
                      ins: :times,
                      ins: :"[]",
                      ins: :{},
                      ins: :build_graph,
                      ins: 0,
                      ins: :{},
                      ins: :find_path,
                      ins: 1,
                      ins: :{},
                      ins: :total,
                      ins: 1
                    ],
                    times: [build_graph: 0, find_path: 43, total: 43]
                  } <-
                    shortest_path!(
                      """
                      %{
                        graph: %{
                          num_edges: 152,
                          num_vertices: 92,
                          size_in_bytes: 1_100_848,
                          type: :directed
                        },
                        result: [
                          ins: :%,
                          ins: :__aliases__,
                          ins: :MyStruct,
                          eq: :%{},
                          eq: :{},
                          eq: :foo,
                          ins: 2,
                          del: 1,
                          eq: :{},
                          ins: :baz,
                          del: :bar,
                          eq: :"[]"
                        ]
                      }
                      """,
                      """
                      %{
                        graph: %{
                          num_edges: 195,
                          num_vertices: 115,
                          size_in_bytes: 1_680_544,
                          type: :directed
                        },
                        result: [
                          ins: :%,
                          ins: :__aliases__,
                          ins: :MyStruct,
                          eq: :%{},
                          eq: :{},
                          eq: :foo,
                          ins: 2,
                          del: 1,
                          eq: :{},
                          del: :bar,
                          ins: :baz,
                          eq: :"[]",
                          eq: 2,
                          del: :"[]",
                          eq: 3
                        ],
                        times: [build_graph: 0, find_path: 1, total: 1]
                      }
                      """
                    )
    end
  end
end
