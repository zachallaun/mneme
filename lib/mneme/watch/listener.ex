defmodule Mneme.Watch.Listener do
  @moduledoc false

  use GenServer

  @doc """
  Start and listen for a file watcher.
  """
  def listen(cli_args) do
    :ok = Application.ensure_started(:file_system)

    children = [
      {__MODULE__, cli_args: cli_args}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    state = opts |> Keyword.validate!([:cli_args]) |> Map.new()
    file_system_opts = [dirs: [File.cwd!()], name: :mneme_file_system_watcher]

    case FileSystem.start_link(file_system_opts) do
      {:ok, _} ->
        FileSystem.subscribe(:mneme_file_system_watcher)
        {:ok, state, {:continue, :run_tests}}

      other ->
        other
    end
  end

  @impl GenServer
  def handle_continue(:run_tests, state) do
    run_tests_and_flush(state.cli_args)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    if watching?(path) do
      run_tests_and_flush(state.cli_args)
    end

    {:noreply, state}
  end

  defp watching?(path) do
    path = Path.relative_to_cwd(path)
    watching_directory?(path) and watching_extension?(path)
  end

  defp watching_directory?(path) do
    ignored = ~w(deps/ _build/ .lexical/ .elixir_ls/ .elixir-tools/)
    not String.starts_with?(path, ignored)
  end

  defp watching_extension?(path) do
    watching = ~w(.erl .ex .exs .eex .leex .heex .xrl .yrl .hrl)
    Path.extname(path) in watching
  end

  defp run_tests_and_flush(args) do
    command_args = ["test"] ++ args

    System.cmd("mix", command_args,
      env: [{"MIX_ENV", "test"}, {"MIX_MNEME_WATCH", "true"}],
      into: IO.stream(:stdio, :line)
    )

    flush()

    :ok
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
