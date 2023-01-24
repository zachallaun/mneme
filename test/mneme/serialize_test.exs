defmodule Mneme.SerializeTest do
  use ExUnit.Case
  import Mneme
  alias Mneme.Serialize

  @format_opts Rewrite.DotFormatter.opts()

  describe "to_pattern/2" do
    test "literals" do
      auto_assert "123" <- to_pattern_string(123)
      auto_assert "123.5" <- to_pattern_string(123.5)
      auto_assert "\"string\"" <- to_pattern_string("string")
      auto_assert ":atom" <- to_pattern_string(:atom)
    end

    test "tuples" do
      auto_assert "{1, \"string\", :atom}" <- to_pattern_string({1, "string", :atom})
      auto_assert "{{:nested}, {\"tuples\"}}" <- to_pattern_string({{:nested}, {"tuples"}})
    end

    test "lists" do
      auto_assert "[1, 2, 3]" <- to_pattern_string([1, 2, 3])
      auto_assert "[1, [:nested], 3]" <- to_pattern_string([1, [:nested], 3])
    end

    test "references" do
      auto_assert "ref when is_reference(ref)" <- to_pattern_string(make_ref())

      ref = make_ref()
      auto_assert "^my_ref" <- to_pattern_string(ref, binding: [my_ref: ref])
    end
  end

  defp to_pattern_string(value, context \\ []) do
    value
    |> Serialize.to_pattern(context)
    |> Sourceror.to_string(@format_opts)
  end
end
