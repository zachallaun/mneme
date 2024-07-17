defmodule Mix.Tasks.Mneme.Watch do
  @shortdoc "Re-runs tests on save, interrupting Mneme prompts"
  @moduledoc """
  TODO
  """

  use GenServer
  use Mix.Task

  defstruct [:cli_args, :testing, saved_files: MapSet.new()]

  @doc """
  Runs `mix.test` with the given CLI arguments, restarting when files change.
  """
  @impl Mix.Task
  @spec run([String.t()]) :: no_return()
  def run(args) do
    Mix.env(:test)
    ensure_os!()

    :ok = Application.ensure_started(:file_system)

    children = [
      {__MODULE__, cli_args: args}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)

    :timer.sleep(:infinity)
  end

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

  defp ensure_os! do
    case os_type() do
      :unix ->
        :ok

      unsupported ->
        error = "file watcher is unsupported on OS: #{inspect(unsupported)}"

        [:red, "error: ", :default_color, error]
        |> IO.ANSI.format()
        |> then(&IO.puts(:stderr, &1))

        System.halt(1)
    end
  end

  defp os_type do
    {os_type, _} = :os.type()
    os_type
  end
end
