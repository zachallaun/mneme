defmodule Mneme.Diff.SyntaxNodeTest do
  use ExUnit.Case, async: true
  use Mneme, default_pattern: :last

  import Mneme.Diff.SyntaxNode

  alias Mneme.Diff.AST

  @ast AST.parse_string!("auto_assert :foo <- some_call(1, 2, 3)")

  describe "root/1" do
    test "creates a syntax node with a stable id and hash" do
      syntax_node = root(@ast)

      auto_assert %Mneme.Diff.SyntaxNode{
                    branch?: true,
                    hash: 58_636_623,
                    id: {6, 58_636_623},
                    zipper:
                      {{:auto_assert,
                        %{__hash__: 58_636_623, __id__: {6, 58_636_623}, column: 1, line: 1},
                        [
                          {:<-,
                           %{
                             __hash__: 132_891_219,
                             __id__: {5, 132_891_219},
                             column: 18,
                             line: 1
                           },
                           [
                             {:atom,
                              %{
                                __hash__: 77_465_098,
                                __id__: {0, 77_465_098},
                                column: 13,
                                line: 1
                              }, :foo},
                             {:some_call,
                              %{
                                __hash__: 62_835_811,
                                __id__: {4, 62_835_811},
                                closing: %{column: 38, line: 1},
                                column: 21,
                                line: 1
                              },
                              [
                                {:int,
                                 %{
                                   __hash__: 90_011_654,
                                   __id__: {1, 90_011_654},
                                   column: 31,
                                   line: 1,
                                   token: "1"
                                 }, 1},
                                {:int,
                                 %{
                                   __hash__: 36_330_407,
                                   __id__: {2, 36_330_407},
                                   column: 34,
                                   line: 1,
                                   token: "2"
                                 }, 2},
                                {:int,
                                 %{
                                   __hash__: 57_057_258,
                                   __id__: {3, 57_057_258},
                                   column: 37,
                                   line: 1,
                                   token: "3"
                                 }, 3}
                              ]}
                           ]}
                        ]}, nil}
                  } <- syntax_node
    end
  end

  describe "next/1" do
    test "walks descendants of a syntax node" do
      root = root(@ast)

      auto_assert {:<-, %{__hash__: 132_891_219, __id__: {5, 132_891_219}, column: 18, line: 1},
                   [
                     {:atom,
                      %{__hash__: 77_465_098, __id__: {0, 77_465_098}, column: 13, line: 1},
                      :foo},
                     {:some_call,
                      %{
                        __hash__: 62_835_811,
                        __id__: {4, 62_835_811},
                        closing: %{column: 38, line: 1},
                        column: 21,
                        line: 1
                      },
                      [
                        {:int,
                         %{
                           __hash__: 90_011_654,
                           __id__: {1, 90_011_654},
                           column: 31,
                           line: 1,
                           token: "1"
                         }, 1},
                        {:int,
                         %{
                           __hash__: 36_330_407,
                           __id__: {2, 36_330_407},
                           column: 34,
                           line: 1,
                           token: "2"
                         }, 2},
                        {:int,
                         %{
                           __hash__: 57_057_258,
                           __id__: {3, 57_057_258},
                           column: 37,
                           line: 1,
                           token: "3"
                         }, 3}
                      ]}
                   ]} <- root |> next() |> ast()

      auto_assert {:atom, %{__hash__: 77_465_098, __id__: {0, 77_465_098}, column: 13, line: 1},
                   :foo} <- root |> next() |> next() |> ast()

      auto_assert {:some_call,
                   %{
                     __hash__: 62_835_811,
                     __id__: {4, 62_835_811},
                     closing: %{column: 38, line: 1},
                     column: 21,
                     line: 1
                   },
                   [
                     {:int,
                      %{
                        __hash__: 90_011_654,
                        __id__: {1, 90_011_654},
                        column: 31,
                        line: 1,
                        token: "1"
                      }, 1},
                     {:int,
                      %{
                        __hash__: 36_330_407,
                        __id__: {2, 36_330_407},
                        column: 34,
                        line: 1,
                        token: "2"
                      }, 2},
                     {:int,
                      %{
                        __hash__: 57_057_258,
                        __id__: {3, 57_057_258},
                        column: 37,
                        line: 1,
                        token: "3"
                      }, 3}
                   ]} <- root |> next() |> next() |> next() |> ast()
    end
  end

  describe "skip/1" do
    test "skips the current node, moving to the next sibling" do
      root = root(@ast)

      assert root |> skip() |> terminal?()

      auto_assert {:some_call,
                   %{
                     __hash__: 62_835_811,
                     __id__: {4, 62_835_811},
                     closing: %{column: 38, line: 1},
                     column: 21,
                     line: 1
                   },
                   [
                     {:int,
                      %{
                        __hash__: 90_011_654,
                        __id__: {1, 90_011_654},
                        column: 31,
                        line: 1,
                        token: "1"
                      }, 1},
                     {:int,
                      %{
                        __hash__: 36_330_407,
                        __id__: {2, 36_330_407},
                        column: 34,
                        line: 1,
                        token: "2"
                      }, 2},
                     {:int,
                      %{
                        __hash__: 57_057_258,
                        __id__: {3, 57_057_258},
                        column: 37,
                        line: 1,
                        token: "3"
                      }, 3}
                   ]} <- root |> next() |> next() |> skip() |> ast()

      assert root |> next() |> next() |> skip() |> skip() |> terminal?()
    end
  end

  describe "parent/1" do
    test "returns the parent syntax node if not at the root" do
      root = root(@ast)

      refute parent(root)
      assert parent(next(root)).id == root.id
    end
  end

  describe "terminal?/1" do
    test "returns true at the end of the ast" do
      last_node = Enum.reduce(1..6, root(@ast), fn _, node -> next(node) end)

      assert last_node
      assert last_node |> next() |> terminal?()
    end
  end

  describe "similar?/2" do
    test "compares syntax nodes based on content, not location in ast" do
      node1 = "1" |> AST.parse_string!() |> root()
      node2 = "[1]" |> AST.parse_string!() |> root() |> next()

      assert similar?(node1, node2)
    end
  end
end
