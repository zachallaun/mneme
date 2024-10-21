defmodule Mneme.Integration.StructTest do
  use ExUnit.Case
  use Mneme

  defmodule User do
    @moduledoc false
    defstruct [:name]

    @doc false
    def new(fields \\ []), do: struct!(__MODULE__, fields)
  end

  test "defaults to a collapsed struct" do
    # y
    auto_assert %User{} <- User.new()
    # y
    auto_assert %User{} <- User.new(name: "Jane Doe")
    # k y
    auto_assert %User{name: "Jane Doe"} <- User.new(name: "Jane Doe")
  end

  test "generates a map when the struct is not defined" do
    # y
    auto_assert %{__struct__: Foo} <- %{__struct__: Foo}
  end

  test "structs as map keys do not generate empty pattern" do
    m = %{%User{name: "name"} => :foo}

    # y
    auto_assert ^m <- m
    # k y
    auto_assert %{%User{name: "name"} => :foo} <- m
    # k k y
    auto_assert ^m <- m
  end
end
