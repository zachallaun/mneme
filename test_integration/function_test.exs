# version: >= 1.14.4
defmodule Mneme.Integration.FunctionTest do
  use ExUnit.Case
  use Mneme

  test "functions" do
    # y
    auto_assert fun when is_function(fun, 1) <- &Function.identity/1

    fun = &Function.identity/1

    # y
    auto_assert ^fun <- fun

    # y
    auto_assert fun1 when is_function(fun1, 2) <- &Enum.map/2
  end
end
