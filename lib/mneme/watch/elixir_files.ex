defmodule Mneme.Watch.ElixirFiles do
  @moduledoc false

  use GenServer

  defstruct [:subscriber, :dir, paths: [], timeout_ms: 200]

  @doc """
  Start a file system watcher linked to the current process and
  subscribe to events.

  The process will receive events of the form:

      {:files_changed [path1, path2, ...]}

  ## Options

    * `:timeout_ms` (default `200`) - amount of time to wait before
      emitting `:files_changed` events. Events received during this time
      are deduplicated.

    * `:dir` (default `[File.cwd!()]`) - directories to watch

  """
  @spec watch!([opt]) :: pid()
        when opt: {:timeout_ms, non_neg_integer()} | {:dir, [Path.t()]}
  def watch!(opts \\ []) do
    :ok = Application.ensure_started(:file_system)

    {:ok, pid} =
      opts
      |> Keyword.validate!(timeout_ms: 200, dir: File.cwd!())
      |> Keyword.put(:subscriber, self())
      |> start_link()

    pid
  end

  @doc false
  def simulate_file_event(pid, path) do
    send(pid, {:file_event, self(), {path, [:modified]}})
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    dir = Keyword.fetch!(opts, :dir)
    {:ok, file_system} = FileSystem.start_link(dirs: [dir])
    :ok = FileSystem.subscribe(file_system)

    {:ok, struct!(__MODULE__, opts)}
  end

  @impl GenServer
  def handle_info({:file_event, _pid, {full_path, _events}}, state) do
    {:noreply, maybe_add_path(state, full_path), state.timeout_ms}
  end

  def handle_info(:timeout, %{paths: []} = state) do
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    files_changed = {:files_changed, Enum.uniq(state.paths)}
    send(state.subscriber, files_changed)

    {:noreply, %{state | paths: []}}
  end

  defp maybe_add_path(%__MODULE__{} = state, full_path) do
    project = Mix.Project.config()
    relative_path = Path.relative_to(full_path, state.dir)

    if watching?(project, relative_path) do
      update_in(state.paths, &[full_path | &1])
    else
      state
    end
  end

  defp watching?(project, path) do
    watching_directory?(project, path) and watching_extension?(path)
  end

  defp watching_directory?(project, path) do
    elixirc_paths = project[:elixirc_paths] || ["lib"]
    erlc_paths = project[:erlc_paths] || ["src"]
    test_paths = project[:test_paths] || ["test"]

    watching =
      for path <- elixirc_paths ++ erlc_paths ++ test_paths do
        String.trim_trailing(path, "/") <> "/"
      end

    String.starts_with?(path, watching)
  end

  defp watching_extension?(path) do
    watching = ~w(.erl .ex .exs .eex .leex .heex .xrl .yrl .hrl)
    Path.extname(path) in watching
  end
end
