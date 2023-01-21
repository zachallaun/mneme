defmodule Mneme.CodeTest do
  use ExUnit.Case
  import Mneme
  import Mneme.Code

  describe "mneme_to_exunit/1" do
    test "constructs an assert expression" do
      auto_assert {:assert, [],
                   [
                     {:=, [],
                      [
                        123,
                        {:var!, [{:context, Mneme.Code}, {:imports, [{1, Kernel}, {2, Kernel}]}],
                         [{:actual, [], Mneme.Code}]}
                      ]}
                   ]} <- mneme_to_exunit(quote(do: 123 <- 123))
    end
  end
end
