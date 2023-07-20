defmodule Mneme.ExampleTest do
  use ExUnit.Case, async: true
  use Mneme

  defmodule MyStruct do
    @moduledoc false
    defstruct field: nil, list: [], map: %{}
  end

  test "1" do
    s1 = %MyStruct{}

    auto_assert ^s1 <- s1
  end

  test "2" do
    s2 = %MyStruct{field: 5}

    auto_assert %MyStruct{field: 5, list: [:foo, :buzz]} <-
                  %{
                    s2
                    | list: [:foo, :buzz],
                      map: %{ok: :cool}
                  }
  end

  test "3" do
    s3 = %MyStruct{field: self()}

    auto_assert ^s3 <- s3
  end

  @mneme target: :ex_unit
  test "4" do
    me = self()
    s4 = %MyStruct{field: me}

    assert %MyStruct{field: ^me} = s4
  end

  @mneme default_pattern: :last
  test "5" do
    auto_assert %{foo: :bar} <- %{foo: :bar}
  end
end
