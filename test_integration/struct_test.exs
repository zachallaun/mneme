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
end
