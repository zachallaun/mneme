defmodule Mneme.Watch.TestRunnerTest do
  use ExUnit.Case
  use Mneme

  import Mox

  alias Mneme.Watch.TestRunner

  setup_all do
    defmock(MockTestRunner, for: TestRunner)
    Application.put_env(:mneme, :watch_test_runner, MockTestRunner)
    :ok
  end

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    tmp_dir =
      Path.join([File.cwd!(), "tmp", "tmp-" <> inspect(__MODULE__)])

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    manifest_path = Path.join([tmp_dir, "manifests"])
    lib_path = Path.join([tmp_dir, "lib"])
    ex_file = Path.join(lib_path, "example.ex")

    File.mkdir!(manifest_path)
    File.mkdir!(lib_path)
    File.write!(ex_file, ":ok")

    opts = [
      cli_args: ["--arg"],
      watch: [timeout_ms: 0, dir: tmp_dir],
      manifest_path: manifest_path,
      name: __MODULE__.TestRunner
    ]

    [runner_opts: opts, lib_path: lib_path, ex_file: ex_file]
  end

  defp expect_initial_run(mock, opts, after_suite_results \\ %{failures: 0}) do
    parent = self()
    ref = make_ref()

    mock
    |> expect(:compiler_options, fn _ -> %{} end)
    |> expect(:after_suite, fn cb -> cb.(after_suite_results) end)
    |> expect(:run_tests, fn _, _ ->
      send(parent, {ref, :run_tests})
      :ok
    end)

    start_supervised!({TestRunner, opts})

    assert_receive {^ref, :run_tests}
  end

  test "starts with valid opts", %{runner_opts: opts} do
    expect_initial_run(MockTestRunner, opts)

    auto_assert pid when is_pid(pid) <- GenServer.whereis(opts[:name])
  end

  test "halts system after successful tests with --exit-on-success", %{runner_opts: opts} do
    opts = Keyword.put(opts, :cli_args, ["--exit-on-success"])

    expect_initial_run(MockTestRunner, opts, %{failures: 0})

    auto_assert pid when is_pid(pid) <- GenServer.whereis(opts[:name])
  end

  test "does not halt after unsuccessful tests with --exit-on-success", %{runner_opts: opts} do
    opts = Keyword.put(opts, :cli_args, ["--exit-on-success"])

    expect_initial_run(MockTestRunner, opts, %{failures: 1})

    auto_assert pid when is_pid(pid) <- GenServer.whereis(opts[:name])
  end

  test "reruns tests when existing file changes", %{runner_opts: opts, ex_file: file} do
    expect_initial_run(MockTestRunner, opts)

    parent = self()
    ref = make_ref()

    MockTestRunner
    |> expect(:io_write, fn message ->
      assert message =~ "reloading"
      assert message =~ file
    end)
    |> expect(:run_tests, fn _, _ ->
      send(parent, {ref, :run_tests})
      :ok
    end)

    dbg(file)
    dbg(File.read!(file))
    File.write!(file, ":updated")
    dbg(File.read!(file))

    assert_receive {^ref, :run_tests}, 5000
  end

  test "reruns tests when new file added", %{runner_opts: opts, lib_path: lib_path} do
    expect_initial_run(MockTestRunner, opts)

    file = Path.join([lib_path, "new_file.ex"])
    parent = self()
    ref = make_ref()

    MockTestRunner
    |> expect(:io_write, fn message ->
      assert message =~ "reloading"
      assert message =~ file
    end)
    |> expect(:run_tests, fn _, _ ->
      send(parent, {ref, :run_tests})
      :ok
    end)

    File.write!(file, ":new")

    assert_receive {^ref, :run_tests}, 5000
  end
end
