defmodule Mneme.Integration.BasicTest do
  use ExUnit.Case
  use Mneme

  test "integers" do
    # y
    auto_assert 4 <- 2 + 2

    # y
    auto_assert 4 <- 2 + 1, 3 <- 2 + 1
  end

  test "strings" do
    # y
    auto_assert "foobar" <- "foo" <> "bar"

    # y
    auto_assert "foobar" <- "foo" <> "baz", "foobaz" <- "foo" <> "baz"
  end

  test "tuples" do
    # y
    auto_assert {1, 2, 3} <- {1, 2, 3}

    my_ref = make_ref()

    t = {1, my_ref}
    # y
    auto_assert ^t <- t
    # e y
    auto_assert {1, ^my_ref} <- t
    # e e y
    auto_assert {1, ref} when is_reference(ref) <- t

    t2 = {1, 2, my_ref}
    # y
    auto_assert ^t2 <- t2
    # e y
    auto_assert {1, 2, ^my_ref} <- t2
    # e e y
    auto_assert {1, 2, ref} when is_reference(ref) <- t2
  end

  test "lists" do
    # y
    auto_assert [1, 2, 3] <- [1, 2, 3]

    my_ref = make_ref()
    l = [my_ref]
    # y
    auto_assert ^l <- l
    # e y
    auto_assert [^my_ref] <- l
    # e e y
    auto_assert [ref] when is_reference(ref) <- l
  end

  test "maps" do
    # y
    auto_assert %{foo: 1} <- Map.put(%{}, :foo, 1)
    # e y
    auto_assert %{foo: 1} <- Map.put(%{}, :foo, 1)
    # s y
    auto_assert %{} <- Map.put(%{}, :foo, 1)
    # s s y
    auto_assert %{} <- Map.put(%{}, :foo, 1)

    m = %{foo: 1}
    # y
    auto_assert ^m <- m
    # e y
    auto_assert %{foo: 1} <- m
    # s y
    auto_assert %{} <- m

    my_ref = make_ref()
    m = %{ref: my_ref}
    # y
    auto_assert ^m <- m
    # s y
    auto_assert %{} <- m
    # e y
    auto_assert %{ref: ^my_ref} <- m
    # e e y
    auto_assert %{ref: ref} when is_reference(ref) <- m
  end
end
