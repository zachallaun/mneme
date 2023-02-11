defmodule Mneme.Integration.BasicTest do
  use ExUnit.Case
  use Mneme

  test "integers" do
    # a
    auto_assert 4 <- 2 + 2

    # a
    auto_assert 4 <- 2 + 1, 3 <- 2 + 1
  end

  test "strings" do
    # a
    auto_assert "foobar" <- "foo" <> "bar"

    # a
    auto_assert "foobar" <- "foo" <> "baz", "foobaz" <- "foo" <> "baz"
  end

  test "tuples" do
    # a
    auto_assert {1, 2, 3} <- {1, 2, 3}

    my_ref = make_ref()

    t = {1, my_ref}
    # a
    auto_assert ^t <- t
    # n a
    auto_assert {1, ^my_ref} <- t
    # n n a
    auto_assert {1, ref} when is_reference(ref) <- t

    t2 = {1, 2, my_ref}
    # a
    auto_assert ^t2 <- t2
    # n a
    auto_assert {1, 2, ^my_ref} <- t2
    # n n a
    auto_assert {1, 2, ref} when is_reference(ref) <- t2
  end

  test "lists" do
    # a
    auto_assert [1, 2, 3] <- [1, 2, 3]

    my_ref = make_ref()
    l = [my_ref]
    # a
    auto_assert ^l <- l
    # n a
    auto_assert [^my_ref] <- l
    # n n a
    auto_assert [ref] when is_reference(ref) <- l
  end

  test "maps" do
    # a
    auto_assert %{} <- Map.put(%{}, :foo, 1)
    # n a
    auto_assert %{foo: 1} <- Map.put(%{}, :foo, 1)
    # p a
    auto_assert %{} <- Map.put(%{}, :foo, 1)
    # p p a
    auto_assert %{} <- Map.put(%{}, :foo, 1)

    m = %{foo: 1}
    # a
    auto_assert ^m <- m
    # n a
    auto_assert %{} <- m
    # n n a
    auto_assert %{foo: 1} <- m

    my_ref = make_ref()
    m = %{ref: my_ref}
    # a
    auto_assert ^m <- m
    # n a
    auto_assert %{} <- m
    # n n a
    auto_assert %{ref: ^my_ref} <- m
    # n n n a
    auto_assert %{ref: ref} when is_reference(ref) <- m
  end
end
