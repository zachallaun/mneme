defmodule Mneme.Watch.TestRunner do
  @moduledoc false

  use GenServer

  defstruct [:cli_args, :testing, paths: [], about_to_save: []]

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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
    Code.compiler_options(ignore_module_conflict: true)
    :ok = Mneme.Watch.ElixirFiles.watch!()
    state = struct(__MODULE__, Keyword.validate!(opts, [:cli_args]))

    if check_system_restarted!() do
      {:ok, state}
    else
      {:ok, state, {:continue, :force_schedule_tests}}
    end
  end

  @impl GenServer
  def handle_continue(:force_schedule_tests, state) do
    {:noreply, %{state | testing: run_tests_async(state.cli_args)}}
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

    state = %{state | testing: run_tests_async(state.cli_args), paths: []}

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

  @impl GenServer
  def handle_cast({:notify_about_to_save, paths}, state) do
    {:noreply, put_in(state.about_to_save, paths)}
  end

  defp run_tests_async(cli_args) do
    Task.async(fn -> run_tests(cli_args) end)
  end

  defp run_tests(cli_args) do
    Code.unrequire_files(Code.required_files())
    recompile()
    Mix.Task.reenable(:test)
    Mix.Task.run(:test, cli_args)
  catch
    :exit, _ ->
      write_system_restart_marker!()
      System.restart()
  end

  @dialyzer {:nowarn_function, recompile: 0}
  defp recompile do
    IEx.Helpers.recompile()
  end

  defp check_system_restarted! do
    restarted? = File.exists?(system_restart_marker())
    _ = File.rm(system_restart_marker())
    restarted?
  end

  defp write_system_restart_marker! do
    File.touch!(system_restart_marker())
  end

  defp system_restart_marker do
    Path.join([Mix.Project.manifest_path(), "mneme.watch.restart"])
  end
end
