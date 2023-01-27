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

    test "pins and guards" do
      ref = make_ref()
      auto_assert "ref when is_reference(ref)" <- to_pattern_string(ref)
      auto_assert "^my_ref" <- to_pattern_string(ref, binding: [my_ref: ref])

      self = self()
      auto_assert "pid when is_pid(pid)" <- to_pattern_string(self)
      auto_assert "^me" <- to_pattern_string(self, binding: [me: self])

      {:ok, port} = :gen_tcp.listen(0, [])

      try do
        auto_assert "port when is_port(port)" <- to_pattern_string(port)
        auto_assert "^my_port" <- to_pattern_string(port, binding: [my_port: port])
      after
        Port.close(port)
      end
    end
  end

  defp to_pattern_string(value, context \\ []) do
    value
    |> Serialize.to_pattern(context)
    |> Sourceror.to_string(@format_opts)
  end
end
