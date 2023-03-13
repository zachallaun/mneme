defmodule Mneme.Diff.SyntaxNodeTest do
  use ExUnit.Case, async: true
  use Mneme

  import Mneme.Diff.SyntaxNode

  alias Mneme.Diff.SyntaxNode, warn: false
  alias Mneme.Diff.AST

  @left "auto_assert some_call(1, 2, 3)" |> AST.parse_string!() |> root()

  # @right "auto_assert :foo <- some_call(1, 2, 3)" |> AST.parse_string!() |> root()

  describe "root/1" do
    test "creates a syntax node with a stable id and hash" do
      auto_assert %SyntaxNode{
                    branch?: true,
                    hash: 111_851_456,
                    id: {4, 111_851_456},
                    null?: false,
                    terminal?: false,
                    zipper:
                      {{:auto_assert, %{},
                        [{:some_call, %{}, [{:int, %{}, 1}, {:int, %{}, 2}, {:int, %{}, 3}]}]},
                       nil}
                  } <- @left
    end
  end

  describe "traversal" do
    test "null nodes are terminals when their predecessor has no nodes to skip to" do
      auto_assert %SyntaxNode{null?: true, terminal?: true} <- @left |> next_sibling()

      auto_assert %SyntaxNode{
                    null?: true,
                    terminal?: true
                  } <-
                    @left
                    |> next_child()
                    |> next_child()
                    |> next_sibling()
                    |> next_sibling()
                    |> next_sibling()
    end

    test "traversing past null nodes" do
      left = auto_assert %SyntaxNode{null?: false} <- @left |> next_child()
      left = auto_assert %SyntaxNode{null?: true} <- left |> next_sibling()
      auto_assert %SyntaxNode{null?: false} <- left |> next()
    end

    test "next/1 returns a terminal node when traversal is complete" do
      left =
        auto_assert %SyntaxNode{
                      null?: false,
                      terminal?: false,
                      zipper: {{:int, %{}, 3}, %{}}
                    } <- @left |> next() |> next() |> next() |> next()

      auto_assert %SyntaxNode{
                    null?: true,
                    terminal?: true
                  } <- left |> next()
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
