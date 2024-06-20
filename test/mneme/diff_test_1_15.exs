# requires Elixir >= 1.15.0
defmodule Mneme.DiffTest_1_15 do
  @moduledoc false
  use ExUnit.Case, async: true
  use Mneme, default_pattern: :last, diff: :text

  import Mneme.DiffTestHelpers

  alias Owl.Tag, warn: false

  describe "multi-letter sigils" do
    test "proper formatting" do
      auto_assert {nil, [[{"~", :green}, {"X", :green}, "\"foo\""]]} <-
                    format(~S|"foo"|, ~S|~X"foo"|)

      auto_assert {[["~", {"X", :red}, "\"foo\""]], [["~", {"XYZ", :green}, "\"foo\""]]} <-
                    format(~S|~X"foo"|, ~S|~XYZ"foo"|)

      auto_assert {[["~", {"FOOOO", :red}, "\"", {"foooo", :red}, "\""]],
                   [["~", {"BAR", :green}, "\"", {"bar", :green}, "\""]]} <-
                    format(~S|~FOOOO"foooo"|, ~S|~BAR"bar"|)
    end
  end
end
