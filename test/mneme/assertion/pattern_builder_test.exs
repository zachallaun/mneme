defmodule Mneme.Assertion.PatternBuilderTest do
  use ExUnit.Case, async: true
  use Mneme

  alias Mneme.Assertion.Pattern
  alias Mneme.Assertion.PatternBuilder

  {_formatter, opts} = Mix.Tasks.Format.formatter_for_file(__ENV__.file)
  @format_opts opts

  describe "patterns" do
    test "atoms" do
      auto_assert [":foo"] <- to_pattern_strings(:foo)
      auto_assert ["true"] <- to_pattern_strings(true)
    end

    test "literals" do
      auto_assert ["123"] <- to_pattern_strings(123)
      auto_assert ["123.5"] <- to_pattern_strings(123.5)
      auto_assert ["\"string\""] <- to_pattern_strings("string")
      auto_assert [":atom"] <- to_pattern_strings(:atom)
    end

    test "tuples" do
      auto_assert ["{1, \"string\", :atom}"] <- to_pattern_strings({1, "string", :atom})
      auto_assert ["{{:nested}, {\"tuples\"}}"] <- to_pattern_strings({{:nested}, {"tuples"}})
    end

    test "lists" do
      auto_assert ["[]"] <- to_pattern_strings([])
      auto_assert ["[1, 2, 3]"] <- to_pattern_strings([1, 2, 3])
      auto_assert ["[1, [:nested], 3]"] <- to_pattern_strings([1, [:nested], 3])
    end

    test "pins and guards" do
      ref = make_ref()
      auto_assert ["ref when is_reference(ref)"] <- to_pattern_strings(ref)

      auto_assert ["^my_ref", "ref when is_reference(ref)"] <-
                    to_pattern_strings(ref, binding: [my_ref: ref])

      self = self()
      auto_assert ["pid when is_pid(pid)"] <- to_pattern_strings(self)
      auto_assert ["^me", "pid when is_pid(pid)"] <- to_pattern_strings(self, binding: [me: self])

      {:ok, port} = :gen_tcp.listen(0, [])

      try do
        auto_assert ["port when is_port(port)"] <- to_pattern_strings(port)

        auto_assert ["^my_port", "port when is_port(port)"] <-
                      to_pattern_strings(port, binding: [my_port: port])
      after
        Port.close(port)
      end
    end

    test "maps" do
      auto_assert ["%{}"] <- to_pattern_strings(%{})

      auto_assert ["%{}", "%{bar: 2, foo: 1}"] <- to_pattern_strings(%{foo: 1, bar: 2})

      auto_assert ["%{}", "%{:foo => 1, \"bar\" => 2}"] <-
                    to_pattern_strings(%{:foo => 1, "bar" => 2})

      auto_assert ["%{}", "%{bar: ref, foo: pid} when is_reference(ref) and is_pid(pid)"] <-
                    to_pattern_strings(%{foo: self(), bar: make_ref()})

      auto_assert ["%{}", "%{bar: %{}, foo: [1, 2]}", "%{bar: %{baz: [3, 4]}, foo: [1, 2]}"] <-
                    to_pattern_strings(%{foo: [1, 2], bar: %{baz: [3, 4]}})
    end

    test "dates and times" do
      iso8601_date = "2023-01-01"
      iso8601_time = "12:00:00+0000"
      iso8601_datetime = iso8601_date <> "T" <> iso8601_time

      {:ok, datetime, 0} = DateTime.from_iso8601(iso8601_datetime)
      auto_assert ["~U[2023-01-01 12:00:00Z]"] <- to_pattern_strings(datetime)

      auto_assert ["^jan1", "~U[2023-01-01 12:00:00Z]"] <-
                    to_pattern_strings(datetime, binding: [jan1: datetime])

      naive_datetime = NaiveDateTime.from_iso8601!(iso8601_datetime)
      auto_assert ["~N[2023-01-01 12:00:00]"] <- to_pattern_strings(naive_datetime)

      auto_assert ["^jan1", "~N[2023-01-01 12:00:00]"] <-
                    to_pattern_strings(naive_datetime, binding: [jan1: naive_datetime])

      date = Date.from_iso8601!(iso8601_date)
      auto_assert ["~D[2023-01-01]"] <- to_pattern_strings(date)
      auto_assert ["^jan1", "~D[2023-01-01]"] <- to_pattern_strings(date, binding: [jan1: date])

      time = Time.from_iso8601!(iso8601_time)
      auto_assert ["~T[12:00:00]"] <- to_pattern_strings(time)
      auto_assert ["^noon", "~T[12:00:00]"] <- to_pattern_strings(time, binding: [noon: time])
    end

    test "URIs don't include deprecated :authority" do
      auto_assert ["%URI{}", "%URI{host: \"example.com\", port: 443, scheme: \"https\"}"] <-
                    to_pattern_strings(URI.parse("https://example.com"))
    end

    test "structs" do
      auto_assert ["%Version{}", "%Version{major: 1, minor: 1, patch: 1}"] <-
                    to_pattern_strings(Version.parse!("1.1.1"))

      auto_assert ["%URI{}"] <- to_pattern_strings(%URI{})
    end
  end

  defp to_pattern_strings(value, context \\ []) do
    context =
      context
      |> Map.new()
      |> Map.put_new(:line, 1)
      |> Map.put_new(:binding, [])
      |> Map.put_new(:original_pattern, nil)

    value
    |> PatternBuilder.to_patterns(context)
    |> Enum.map(fn
      %Pattern{guard: nil, expr: expr} -> expr
      %Pattern{guard: guard, expr: expr} -> {:when, [], [expr, guard]}
    end)
    |> Enum.map(&Sourceror.to_string(&1, @format_opts))
  end
end
