defmodule Mneme.Watch.TestRunner do
  @moduledoc false

  use GenServer

  defstruct [:cli_args, :testing, saved_files: MapSet.new()]

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    Code.compiler_options(ignore_module_conflict: true)
    :ok = Mneme.Watch.ElixirFiles.watch!()
    state = struct(__MODULE__, Keyword.validate!(opts, [:cli_args]))

    {:ok, state, {:continue, :force_schedule_tests}}
  end

  @impl GenServer
  def handle_continue(:force_schedule_tests, state) do
    {:noreply, %{state | testing: {run_tests_async(state.cli_args), state.saved_files}}}
  end

  def handle_continue(:maybe_schedule_tests, %{testing: {%Task{}, _}} = state) do
    {:noreply, state}
  end

  def handle_continue(:maybe_schedule_tests, state) do
    if MapSet.size(state.saved_files) > 0 do
      IO.puts("\r")

      for file <- state.saved_files do
        Owl.IO.puts([Owl.Data.tag("reloading: ", :cyan), file])
      end

      IO.puts("")

      state = %{
        state
        | testing: {run_tests_async(state.cli_args), state.saved_files},
          saved_files: MapSet.new()
      }

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:files_changed, paths}, state) do
    case state do
      %{testing: {%Task{}, _}} ->
        Mneme.Server.skip_all()

      _ ->
        :ok
    end

    state = update_in(state.saved_files, &Enum.into(paths, &1))

    {:noreply, state, {:continue, :maybe_schedule_tests}}
  end

  def handle_info({ref, _}, %{testing: {%Task{ref: ref}, tested_files}} = state) do
    state = update_in(state.saved_files, &MapSet.difference(&1, tested_files))
    {:noreply, %{state | testing: nil}, {:continue, :maybe_schedule_tests}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp run_tests_async(cli_args) do
    Task.async(fn -> run_tests(cli_args) end)
  end

  defp run_tests(cli_args) do
    Code.unrequire_files(Code.required_files())
    recompile()
    Mix.Task.reenable(:test)
    Mix.Task.run(:test, cli_args)
  end

  defp recompile do
    IEx.Helpers.recompile()
  end
end
