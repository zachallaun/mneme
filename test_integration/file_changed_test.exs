# exit:2
defmodule Mneme.Integration.FileChangedTest do
  use ExUnit.Case
  use Mneme

  test "shouldn't update if the file contents change after read" do
    # y
    auto_assert "foo" <> "bar"

    File.write!(__ENV__.file, "#", [:append])
  end
end
