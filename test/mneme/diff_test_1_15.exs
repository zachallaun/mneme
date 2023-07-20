# requires Elixir >= 1.15.0
defmodule Mneme.DiffTest_1_15 do
  @moduledoc false
  use ExUnit.Case, async: true
  use Mneme, default_pattern: :last, diff: :text

  import Mneme.DiffTestHelpers

  alias Owl.Tag, warn: false

  describe "multi-letter sigils" do
    test "proper formatting" do
      auto_assert {nil,
                   [
                     [
                       %Tag{data: "~", sequences: [:green]},
                       %Tag{data: "X", sequences: [:green]},
                       "\"foo\""
                     ]
                   ]} <- format(~S|"foo"|, ~S|~X"foo"|)

      auto_assert {[["~", %Tag{data: "X", sequences: [:red]}, "\"foo\""]],
                   [["~", %Tag{data: "XYZ", sequences: [:green]}, "\"foo\""]]} <-
                    format(~S|~X"foo"|, ~S|~XYZ"foo"|)

      auto_assert {[
                     [
                       "~",
                       %Tag{data: "FOOOO", sequences: [:red]},
                       "\"",
                       %Tag{data: "foooo", sequences: [:red]},
                       "\""
                     ]
                   ],
                   [
                     [
                       "~",
                       %Tag{data: "BAR", sequences: [:green]},
                       "\"",
                       %Tag{data: "bar", sequences: [:green]},
                       "\""
                     ]
                   ]} <- format(~S|~FOOOO"foooo"|, ~S|~BAR"bar"|)
    end
  end
end
