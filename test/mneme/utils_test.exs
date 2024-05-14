defmodule Mneme.UtilsTest do
  use ExUnit.Case
  use Mneme
  use ExUnitProperties

  import Mneme.Utils

  doctest Mneme.Utils

  describe "strip_ignorable/1" do
    property "always returns a substring of the given binary" do
      check all string <- StreamData.binary() do
        assert substring = strip_ignorable(string)
        assert string =~ substring
      end
    end

    test "returns empty ignorable strings when there is nothing to ignore" do
      auto_assert "foo bar baz" <- strip_ignorable("foo bar baz")
    end

    test "ignores whitespace at the beginning and end" do
      auto_assert "foo" <- strip_ignorable("\n foo")
      auto_assert "foo" <- strip_ignorable("foo \n ")
      auto_assert "foo" <- strip_ignorable("  \t\r\n foo \n ")
    end

    test "ignores timestamps" do
      auto_assert "[info] foo" <- strip_ignorable("10:10:10.123 [info] foo")
    end

    test "ignores dates" do
      auto_assert "foo" <- strip_ignorable("2024-05-13 foo")
      auto_assert "foo" <- strip_ignorable("2024/05/13 foo")
    end

    test "ignores terminal escape sequences" do
      auto_assert "foo" <- strip_ignorable("\e[33m\nfoo\n\e[0m")
    end

    test "ignores combinations of ignorables" do
      auto_assert "[info] foo" <- strip_ignorable("2024-05-13 10:10:10.123 [info] foo\n")
    end
  end
end
