defmodule Mneme.Watch do
  @moduledoc false

  use GenServer

  @doc """
  Runs `mix.test` with the given CLI arguments, restarting when files change.
  """
  @spec run([String.t()]) :: no_return()
  def run(args \\ []) do
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

    state = opts |> Keyword.validate!([:cli_args]) |> Map.new()
    file_system_opts = [dirs: [File.cwd!()], name: :mneme_file_system_watcher]

    case FileSystem.start_link(file_system_opts) do
      {:ok, _} ->
        FileSystem.subscribe(:mneme_file_system_watcher)
        {:ok, state, {:continue, :first_run}}

      other ->
        other
    end
  end

  @impl GenServer
  def handle_continue(:first_run, state) do
    Mix.Task.run(:test, state.cli_args)
    flush()

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    path = Path.relative_to_cwd(path)

    if watching?(path) do
      IO.puts("detected change: #{path}")
      run_tests(state.cli_args)
      flush()
    end

    {:noreply, state}
  end

  defp watching?(path) do
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

  defp run_tests(cli_args) do
    Code.unrequire_files(Code.required_files())
    IEx.Helpers.recompile()
    Mix.Task.reenable(:test)
    Mix.Task.run(:test, cli_args)
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
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