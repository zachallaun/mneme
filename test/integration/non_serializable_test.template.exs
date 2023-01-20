defmodule MnemeIntegration.NonSerializableTest do
  use ExUnit.Case
  import Mneme

  test "pinned reference" do
    my_ref = make_ref()

    auto_assert Function.identity(my_ref)
  end
end
