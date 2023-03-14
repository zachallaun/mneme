# Short demonstration of Mneme's interactive prompts.
# Download and run in your terminal with: elixir tour_mneme.exs

Mix.install([
  {:mneme, ">= 0.0.0"}
])

ExUnit.start(seed: 0)
Mneme.start()

defmodule ExampleTest do
  use ExUnit.Case
  use Mneme

  describe "Mneme generates patterns" do
    test "for simple data types" do
      auto_assert 123

      auto_assert "abc"

      auto_assert :abc
    end

    test "for lists" do
      auto_assert [1, 2, 3]
    end

    test "for maps" do
      # not what you expected? use j/k to cycle to a more complex value
      auto_assert %{first_name: "Jane", last_name: "Doe"}
    end

    test "using guards if needed" do
      auto_assert self()

      auto_assert make_ref()
    end

    test "using the value of any expression" do
      auto_assert drop_evens(1..10)

      auto_assert drop_evens([])

      auto_assert drop_evens([:a, :b, 2, :c])
    end

    test "using pinned variables if possible" do
      me = self()

      auto_assert self()
    end
  end

  defp drop_evens(enum) do
    even? = fn n -> is_integer(n) && Integer.mod(n, 2) == 0 end
    Enum.reject(enum, even?)
  end
end

ExUnit.run()
