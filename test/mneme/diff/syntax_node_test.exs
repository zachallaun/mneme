defmodule Mneme.Diff.SyntaxNodeTest do
  use ExUnit.Case, async: true
  use Mneme

  import Mneme.Diff.SyntaxNode

  alias Mneme.Diff.SyntaxNode, warn: false

  @left root!("auto_assert some_call(1, 2, 3)")
  @right root!("auto_assert :foo <- some_call(1, 2, 3)")

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

  describe "coordinated traversal" do
    test "using next_child/1, next_sibling/1 and pop/2" do
      left = @left |> next_child(:pop_both)
      right = @right |> next_child(:pop_both)

      auto_assert %SyntaxNode{
                    parent: {:pop_both, %SyntaxNode{}},
                    terminal?: false,
                    zipper:
                      {{:some_call, %{}, [{:int, %{}, 1}, {:int, %{}, 2}, {:int, %{}, 3}]}, %{}}
                  } <- left

      auto_assert %SyntaxNode{
                    parent: {:pop_both, %SyntaxNode{}},
                    terminal?: false,
                    zipper:
                      {{:<-, %{},
                        [
                          {:atom, %{}, :foo},
                          {:some_call, %{}, [{:int, %{}, 1}, {:int, %{}, 2}, {:int, %{}, 3}]}
                        ]}, %{}}
                  } <- right

      left = left |> next_child() |> next_sibling() |> next_sibling() |> next_sibling()
      right = right |> next_child() |> next_sibling()

      auto_assert %SyntaxNode{
                    null?: true,
                    parent: {:pop_either, %SyntaxNode{}},
                    terminal?: true
                  } <- left

      auto_assert %SyntaxNode{
                    parent: {:pop_either, %SyntaxNode{}},
                    terminal?: false,
                    zipper:
                      {{:some_call, %{}, [{:int, %{}, 1}, {:int, %{}, 2}, {:int, %{}, 3}]}, %{}}
                  } <- right

      right = right |> next_child() |> next_sibling() |> next_sibling() |> next_sibling()

      auto_assert {%SyntaxNode{
                     null?: true,
                     terminal?: true
                   },
                   %SyntaxNode{
                     null?: true,
                     terminal?: true
                   }} <- pop(left, right)
    end
  end

  describe "similar?/2" do
    test "compares syntax nodes based on content, not location in ast" do
      node1 = root!("1")
      node2 = root!("[1]") |> next_child()

      assert similar?(node1, node2)
    end
  end

  describe "similar_branch?/1" do
    test "compares syntax nodes based on branch" do
      assert similar_branch?(root!("foo.bar"), root!("baz.buzz"))
      assert similar_branch?(root!("foo(1)"), root!("foo(1, 2, 3)"))
      assert similar_branch?(root!("[1, 2]"), root!("[3, 4, 5]"))

      refute similar_branch?(root!("foo"), root!("foo"))
      refute similar_branch?(root!("[1, 2]"), root!("{1, 2}"))
    end
  end
end
