defmodule Mneme.Watch.TestRunner do
  @moduledoc false

  use GenServer

  alias Mneme.Watch

  defstruct [
    :cli_args,
    :testing,
    :system_restart_marker,
    paths: [],
    about_to_save: [],
    exit_on_success?: false
  ]

  @doc """
  Starts a test runner that reruns tests when files change.

  ## Options

    * `:cli_args` (required) - list of command-line arguments

    * `:watch` (default `[]`) - keyword options passed to
      `Mneme.Watch.ElixirFiles.watch!/1`

    * `:manifest_path` (default `Mix.Project.manifest_path/0`) - dir
      used to track state between runs.

    * `:name` (default `Mneme.Watch.TestRunner`) - registered name of
      the started process

  """
  def start_link(opts) do
    defaults = [
      cli_args: [],
      watch: [],
      manifest_path: Mix.Project.manifest_path(),
      name: __MODULE__
    ]

    {name, opts} =
      opts
      |> Keyword.validate!(defaults)
      |> Keyword.pop!(:name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Notify the test runner of files about to be saved so that they can
  be ignored in the next files changed event.
  """
  def notify_about_to_save(paths) when is_list(paths) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      test_runner -> GenServer.cast(test_runner, {:notify_about_to_save, paths})
    end
  end

  @impl GenServer
  def init(opts) do
    args = Keyword.fetch!(opts, :cli_args)
    watch_opts = Keyword.fetch!(opts, :watch)
    manifest_path = Keyword.fetch!(opts, :manifest_path)

    Code.compiler_options(ignore_module_conflict: true)
    :ok = Watch.ElixirFiles.watch!(watch_opts)

    {cli_args, exit_on_success?} =
      if "--exit-on-success" in args do
        {args -- ["--exit-on-success"], true}
      else
        {args, false}
      end

    state = %__MODULE__{
      cli_args: cli_args,
      exit_on_success?: exit_on_success?,
      system_restart_marker: Path.join(manifest_path, "mneme.watch.restart")
    }

    runner = self()
    ExUnit.after_suite(fn result -> send(runner, {:after_suite, result}) end)

    if check_system_restarted!(state.system_restart_marker) do
      {:ok, state}
    else
      {:ok, state, {:continue, :force_schedule_tests}}
    end
  end

  @impl GenServer
  def handle_continue(:force_schedule_tests, state) do
    {:noreply, %{state | testing: run_tests_async(state)}}
  end

  def handle_continue(:maybe_schedule_tests, %{testing: %Task{}} = state) do
    {:noreply, state}
  end

  def handle_continue(:maybe_schedule_tests, %{paths: []} = state) do
    {:noreply, state}
  end

  def handle_continue(:maybe_schedule_tests, state) do
    IO.write("\r\n")

    state.paths
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(fn path ->
      Owl.IO.puts([Owl.Data.tag("reloading: ", :cyan), path])
    end)

    IO.write("\n")

    state = %{state | testing: run_tests_async(state), paths: []}

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:files_changed, paths}, state) do
    relevant_paths = paths -- state.about_to_save

    state =
      state
      |> Map.put(:about_to_save, [])
      |> Map.update!(:paths, &(relevant_paths ++ &1))

    if state.testing do
      Mneme.Server.skip_all()
    end

    {:noreply, state, {:continue, :maybe_schedule_tests}}
  end

  def handle_info({ref, _}, %{testing: %Task{ref: ref}} = state) do
    {:noreply, %{state | testing: nil}, {:continue, :maybe_schedule_tests}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info({:after_suite, result}, state) do
    if state.exit_on_success? and result.failures == 0 do
      System.halt(0)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:notify_about_to_save, paths}, state) do
    {:noreply, put_in(state.about_to_save, paths)}
  end

  defp run_tests_async(%__MODULE__{} = state) do
    cli_args = state.cli_args
    system_restart_marker = state.system_restart_marker
    Task.async(fn -> run_tests(cli_args, system_restart_marker) end)
  end

  defp run_tests(cli_args, system_restart_marker) do
    Code.unrequire_files(Code.required_files())
    recompile()
    Mix.Task.reenable(:test)
    Mix.Task.run(:test, cli_args)
  catch
    :exit, _ ->
      write_system_restart_marker!(system_restart_marker)
      System.restart()
  end

  @dialyzer {:nowarn_function, recompile: 0}
  defp recompile do
    IEx.Helpers.recompile()
  end

  defp check_system_restarted!(system_restart_marker) do
    restarted? = File.exists?(system_restart_marker)
    _ = File.rm(system_restart_marker)
    restarted?
  end

  defp write_system_restart_marker!(system_restart_marker) do
    File.touch!(system_restart_marker)
  end
end
