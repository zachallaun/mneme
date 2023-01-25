defmodule Mneme.Server do
  @moduledoc false
  use GenServer

  alias Mneme.Patch

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def after_suite(_results) do
    GenServer.call(__MODULE__, :after_suite)
  end

  def await_assertion(assertion) do
    GenServer.call(__MODULE__, {:assertion, assertion})
  end

  def capture_io do
    {:ok, io_pid} = StringIO.open("")
    Process.group_leader(self(), io_pid)
    GenServer.call(__MODULE__, {:capture_io, io_pid})
  end

  def flush_io do
    GenServer.call(__MODULE__, :flush_io)
  end

  @impl true
  def init(_arg) do
    {:ok, %{io_pid: nil, patch: Patch.init()}}
  end

  @impl true
  def handle_call(
        {:assertion, {_type, _value, context} = assertion},
        _from,
        %{patch: patch_state} = state
      ) do
    patch_state = Patch.load_file!(patch_state, context)
    {patch, patch_state} = Patch.patch_assertion(patch_state, assertion)

    case Patch.accept_patch?(patch_state, patch) do
      {true, patch_state} ->
        patch_state = Patch.accept(patch_state, patch)
        {:reply, {:ok, patch.expr}, %{state | patch: patch_state}}

      {false, patch_state} ->
        patch_state = Patch.reject(patch_state, patch)
        {:reply, :error, %{state | patch: patch_state}}
    end
  end

  def handle_call(:after_suite, _from, %{patch: patch_state} = state) do
    patch_state = Patch.finalize!(patch_state)
    {:reply, :ok, %{state | patch: patch_state}}
  end

  def handle_call({:capture_io, io_pid}, _from, %{io_pid: nil} = state) do
    {:reply, :ok, %{state | io_pid: io_pid}}
  end

  def handle_call(:flush_io, _from, %{io_pid: io_pid} = state) when is_pid(io_pid) do
    contents = StringIO.flush(io_pid)
    if contents != "", do: IO.write(contents)

    {:reply, :ok, state}
  end
end
