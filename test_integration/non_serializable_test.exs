defmodule Mneme.Integration.NonSerializableTest do
  use ExUnit.Case
  use Mneme

  test "pinned" do
    my_ref = make_ref()

    # y
    auto_assert ^my_ref <- Function.identity(my_ref)

    # y
    auto_assert [^my_ref] <- [my_ref]
  end

  test "guard" do
    # y
    auto_assert ref when is_reference(ref) <- make_ref()

    # y
    auto_assert [ref] when is_reference(ref) <- [make_ref()]

    # y
    auto_assert pid when is_pid(pid) <- self()
  end

  test "shrink and expand" do
    my_ref = make_ref()

    # y
    auto_assert ^my_ref <- my_ref

    # k y
    auto_assert ref when is_reference(ref) <- my_ref
  end

  test "non-serializable datetime" do
    tzdb = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(TimeZoneInfo.TimeZoneDatabase)

    dt =
      ~N[2024-01-01 00:00:00]
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.shift_zone!("Pacific/Honolulu")

    # k k y
    auto_assert %DateTime{
                  day: 31,
                  hour: 14,
                  minute: 0,
                  month: 12,
                  second: 0,
                  std_offset: 0,
                  time_zone: "Pacific/Honolulu",
                  utc_offset: -36_000,
                  year: 2023,
                  zone_abbr: "HST"
                } <- dt
  end
end
