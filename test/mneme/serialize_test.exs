defmodule Mneme.SerializeTest do
  use ExUnit.Case
  import Mneme
  alias Mneme.Serialize

  @format_opts Rewrite.DotFormatter.opts()

  describe "to_pattern/2" do
    test "atoms" do
      auto_assert ":foo" <- to_pattern_string(:foo)
      auto_assert "true" <- to_pattern_string(true)
    end

    test "literals" do
      auto_assert "123" <- to_pattern_string(123)
      auto_assert "123.5" <- to_pattern_string(123.5)
      auto_assert "\"string\"" <- to_pattern_string("string")
      auto_assert ":atom" <- to_pattern_string(:atom)
    end

    test "tuples" do
      auto_assert "{1, \"string\", :atom}" <- to_pattern_string({1, "string", :atom})
      auto_assert "{{:nested}, {\"tuples\"}}" <- to_pattern_string({{:nested}, {"tuples"}})

      auto_assert {:two, :elements} <- Serialize.to_pattern({:two, :elements})

      auto_assert {:{}, [], [:more, :than, :two, :elements]} <-
                    Serialize.to_pattern({:more, :than, :two, :elements})
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

    test "maps" do
      auto_assert "%{bar: 2, foo: 1}" <- to_pattern_string(%{foo: 1, bar: 2})
      auto_assert "%{:foo => 1, \"bar\" => 2}" <- to_pattern_string(%{:foo => 1, "bar" => 2})

      auto_assert "%{bar: ref, foo: pid} when is_reference(ref) and is_pid(pid)" <-
                    to_pattern_string(%{foo: self(), bar: make_ref()})

      auto_assert "%{bar: %{baz: [3, 4]}, foo: [1, 2]}" <-
                    to_pattern_string(%{foo: [1, 2], bar: %{baz: [3, 4]}})
    end

    test "dates and times" do
      iso8601_date = "2023-01-01"
      iso8601_time = "12:00:00+0000"
      iso8601_datetime = iso8601_date <> "T" <> iso8601_time

      {:ok, datetime, 0} = DateTime.from_iso8601(iso8601_datetime)
      auto_assert "~U[2023-01-01 12:00:00Z]" <- to_pattern_string(datetime)
      auto_assert "^jan1" <- to_pattern_string(datetime, binding: [jan1: datetime])

      naive_datetime = NaiveDateTime.from_iso8601!(iso8601_datetime)
      auto_assert "~N[2023-01-01 12:00:00]" <- to_pattern_string(naive_datetime)
      auto_assert "^jan1" <- to_pattern_string(naive_datetime, binding: [jan1: naive_datetime])

      date = Date.from_iso8601!(iso8601_date)
      auto_assert "~D[2023-01-01]" <- to_pattern_string(date)
      auto_assert "^jan1" <- to_pattern_string(date, binding: [jan1: date])

      time = Time.from_iso8601!(iso8601_time)
      auto_assert "~T[12:00:00]" <- to_pattern_string(time)
      auto_assert "^noon" <- to_pattern_string(time, binding: [noon: time])
    end

    test "URIs don't include deprecated :authority" do
      auto_assert "%URI{host: \"example.com\", port: 443, scheme: \"https\"}" <-
                    to_pattern_string(URI.parse("https://example.com"))
    end

    test "structs" do
      auto_assert "%Version{major: 1, minor: 1, patch: 1}" <-
                    to_pattern_string(Version.parse!("1.1.1"))
    end
  end

  defp to_pattern_string(value, context \\ []) do
    value
    |> Serialize.to_pattern(context)
    |> Sourceror.to_string(@format_opts)
  end
end
