defmodule Mneme.Watch.ElixirFilesTest do
  use ExUnit.Case
  use Mneme
  use Patch

  alias Mneme.Watch.ElixirFiles

  describe "watch/1" do
    setup do
      patch(FileSystem, :start_link, {:ok, :file_system})
      patch(FileSystem, :subscribe, :ok)

      pid =
        start_supervised!({ElixirFiles, subscriber: self(), timeout_ms: 10, dirs: [File.cwd!()]})

      {:ok, pid: pid}
    end

    defp file_events(pid, paths) when is_list(paths) do
      for path <- paths do
        send(pid, {:file_event, self(), {path, [:modified]}})
      end
    end

    test "emits files in test/", %{pid: pid} do
      file_events(pid, ["test/ex1.exs", "test/ex2.exs"])

      auto_assert_receive {:files_changed, ["test/ex2.exs", "test/ex1.exs"]}
    end

    test "emits files in lib/", %{pid: pid} do
      file_events(pid, ["lib/ex1.ex", "lib/ex2.ex"])

      auto_assert_receive {:files_changed, ["lib/ex2.ex", "lib/ex1.ex"]}
    end

    test "emits files in src/", %{pid: pid} do
      file_events(pid, ["src/ex1.erl", "src/ex2.erl"])

      auto_assert_receive {:files_changed, ["src/ex2.erl", "src/ex1.erl"]}
    end

    test "deduplicates files", %{pid: pid} do
      file_events(pid, ["lib/ex.ex", "lib/ex.ex"])

      auto_assert_receive {:files_changed, ["lib/ex.ex"]}
    end

    test "batches events based on timeout", %{pid: pid} do
      # should be in first batch
      file_events(pid, ["lib/ex1.ex"])
      Process.sleep(5)
      file_events(pid, ["lib/ex2.ex"])

      # should be in second batch
      Process.sleep(15)
      file_events(pid, ["lib/ex1.ex", "lib/ex3.ex"])

      auto_assert_received {:files_changed, ["lib/ex2.ex", "lib/ex1.ex"]}
      auto_assert_receive {:files_changed, ["lib/ex3.ex", "lib/ex1.ex"]}
    end
  end
end
