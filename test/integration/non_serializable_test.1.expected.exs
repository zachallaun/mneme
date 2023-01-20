defmodule MnemeIntegration.NonSerializableTest do
  use ExUnit.Case
  import Mneme

  test "pinned reference" do
    my_ref = make_ref()

    auto_assert ^my_ref = Function.identity(my_ref)
  end
end
