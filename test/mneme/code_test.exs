defmodule Mneme.CodeTest do
  use ExUnit.Case
  import Mneme
  import Mneme.Code

  describe "mneme_to_exunit/1" do
    test "builds an assertion" do
      auto_assert {:assert, [],
                   [
                     {:=, [],
                      [
                        123,
                        {:var!, [{:context, Mneme.Code}, {:imports, [{1, Kernel}, {2, Kernel}]}],
                         [{:actual, [], Mneme.Code}]}
                      ]}
                   ]} <- mneme_to_exunit(quote(do: auto_assert(123 <- 123)))
    end

    test "builds multiple assertions if guards are used" do
      auto_assert {:__block__, [],
                   [
                     {:assert, [],
                      [
                        {:=, [],
                         [
                           {:foo, [], Mneme.CodeTest},
                           {:var!,
                            [{:context, Mneme.Code}, {:imports, [{1, Kernel}, {2, Kernel}]}],
                            [{:actual, [], Mneme.Code}]}
                         ]}
                      ]},
                     {:assert, [],
                      [
                        {:is_integer, [{:context, Mneme.CodeTest}, {:imports, [{1, Kernel}]}],
                         [{:foo, [], Mneme.CodeTest}]}
                      ]}
                   ]} <- mneme_to_exunit(quote(do: auto_assert(foo when is_integer(foo) <- 123)))
    end
  end
end
