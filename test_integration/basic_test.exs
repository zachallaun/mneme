defmodule Mneme.Integration.BasicTest do
  use ExUnit.Case
  use Mneme

  @mneme action: :reject
  test "auto_assert/1 raises if no pattern is present and update is rejected" do
    assert_raise Mneme.AssertionError, "No pattern present", fn ->
      # ignore
      auto_assert :foo
    end
  end

  @mneme action: :reject
  test "auto_assert/1 raises if the match fails and update is rejected" do
    error =
      assert_raise ExUnit.AssertionError, fn ->
        # ignore
        auto_assert :foo <- :bar
      end

    assert %{left: :foo, right: :bar, message: "match (=) failed"} = error
  end

  describe "patterns" do
    test "integers" do
      # y
      auto_assert 4 <- 2 + 2

      # y
      auto_assert 4 <- 2 + 1, 3 <- 2 + 1
    end

    test "strings/binaries" do
      # y
      auto_assert "foobar" <- "foo" <> "bar"

      # y
      auto_assert "foobar" <- "foo" <> "baz", "foobaz" <- "foo" <> "baz"

      # y
      auto_assert <<0>> <- <<0>>

      # k y
      auto_assert """
                  foo
                  \\
                  bar
                  """ <- """
                  foo
                  \\
                  bar
                  """
    end

    test "tuples" do
      # y
      auto_assert {1, 2, 3} <- {1, 2, 3}

      my_ref = make_ref()

      t = {1, my_ref}
      # y
      auto_assert ^t <- t
      # k y
      auto_assert {1, ^my_ref} <- t
      # k k y
      auto_assert {1, ref} when is_reference(ref) <- t

      t2 = {1, 2, my_ref}
      # y
      auto_assert ^t2 <- t2
      # k y
      auto_assert {1, 2, ^my_ref} <- t2
      # k k y
      auto_assert {1, 2, ref} when is_reference(ref) <- t2
    end

    test "lists" do
      # y
      auto_assert [1, 2, 3] <- [1, 2, 3]

      # y
      auto_assert [8, 9, 10] <- [8, 9, 10]

      my_ref = make_ref()
      l = [my_ref]
      # y
      auto_assert ^l <- l
      # k y
      auto_assert [^my_ref] <- l
      # k k y
      auto_assert [ref] when is_reference(ref) <- l
    end

    test "maps" do
      # y
      auto_assert %{} <- Map.put(%{}, :foo, 1)
      # k y
      auto_assert %{foo: 1} <- Map.put(%{}, :foo, 1)

      m = %{foo: 1}
      # y
      auto_assert ^m <- m
      # k y
      auto_assert %{} <- m
      # k k y
      auto_assert %{foo: 1} <- m

      my_ref = make_ref()
      m = %{ref: my_ref}
      # y
      auto_assert ^m <- m
      # k y
      auto_assert %{} <- m
      # k k y
      auto_assert %{ref: ^my_ref} <- m
      # k k k y
      auto_assert %{ref: ref} when is_reference(ref) <- m
    end

    test "sigils" do
      # y
      auto_assert "foo" <- ~s(foo)

      # y
      auto_assert "foo" <- ~S(foo)

      # y
      auto_assert [102, 111, 111] <- ~c(foo)
      # k y
      auto_assert 'foo' <- ~c(foo)

      # y
      auto_assert [102, 111, 111] <- ~C(foo)
      # k y
      auto_assert 'foo' <- ~c(foo)
      # NOTE: Formatter bug in Elixir is causing this whitespace to collapse.
      # y
      auto_assert ~r/abc/ <- ~r/abc/
      # y
      auto_assert ~r/abc/mu <- ~r/abc/mu
      # y
      auto_assert ~r/a#\{b\}c/ <- ~R/a#\{b\}c/
    end

    test "falsy values" do
      # y
      auto_assert false <- false

      # y
      auto_assert nil <- nil

      falsy = false
      # y
      auto_assert false <- falsy
    end

    test "ranges" do
      # y
      auto_assert 1..10 <- Range.new(1, 10)
      # y
      auto_assert 1..10//2 <- Range.new(1, 10, 2)
    end
  end
end
