defmodule Mneme.Server do
  @moduledoc false

  # Mneme.Server is an ExUnit.Formatter that replaces (and delegates to)
  # the default formatter so that it can capture and control terminal IO
  # and hook into test events.

  use GenServer

  alias Mneme.Patcher

  defstruct [
    :patch_state,
    :io_pid,
    :current,
    :waiting,
    active_tags: %{},
    queue: []
  ]

  @type t :: %__MODULE__{
          patch_state: any(),
          io_pid: pid(),
          current: %{module: module(), file: binary()},
          waiting: %{file: binary(), line: non_neg_integer(), arg: assertion_arg},
          active_tags: map(),
          queue: list()
        }

  @type assertion_arg :: {assertion, from :: pid()}
  @type assertion :: {type :: :new | :replace, value :: any(), context :: map()}

  @doc """
  Start a Mneme server.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Patcher a Mneme assertion, prompting the user.
  """
  def await_assertion(assertion) do
    GenServer.call(__MODULE__, {:patch_assertion, assertion}, :infinity)
  end

  def on_formatter_init(_opts) do
    {:ok, io_pid} = StringIO.open("")
    Process.group_leader(self(), io_pid)
    GenServer.call(__MODULE__, {:capture_formatter, io_pid}, :infinity)
  end

  def on_formatter_event(message) do
    GenServer.call(__MODULE__, {:formatter_event, message}, :infinity)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{patch_state: Patcher.init()}}
  end

  @impl true
  def handle_call({:patch_assertion, assertion}, from, %{current: nil} = state) do
    {:noreply, patch_assertion(state, {assertion, from})}
  end

  def handle_call({:patch_assertion, assertion}, from, state) do
    {_type, _value, context} = assertion

    case {context, state.current} do
      {%{module: module, file: file}, %{module: module, file: file}} ->
        {:noreply, patch_assertion(state, {assertion, from})}

      _ ->
        state = Map.update!(state, :queue, &(&1 ++ [{assertion, from}]))
        {:noreply, state}
    end
  end

  def handle_call({:capture_formatter, io_pid}, _from, state) do
    {:reply, :ok, state |> Map.put(:io_pid, io_pid)}
  end

  def handle_call({:formatter_event, {:suite_finished, _}}, _from, state) do
    flush_io(state)
    {:reply, :ok, Map.update!(state, :patch_state, &Patcher.finalize!/1)}
  end

  def handle_call({:formatter_event, {:module_finished, test_module}}, _from, state) do
    state =
      case {test_module, state.current} do
        {%{name: module, file: file}, %{module: module, file: file}} ->
          flush_io(state)
          %{state | current: nil}

        _ ->
          state
      end

    state =
      case state do
        %{current: nil, queue: [next | rest]} ->
          state
          |> Map.put(:queue, rest)
          |> patch_assertion(next)

        _ ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call({:formatter_event, {:test_started, test}}, _from, state) do
    %{tags: %{file: file, line: line} = tags} = test

    case Map.update!(state, :active_tags, &Map.put(&1, file, tags)) do
      %{waiting: %{file: ^file, line: ^line, arg: arg}} = state ->
        {:reply, :ok, state |> Map.put(:waiting, nil) |> patch_assertion(arg)}

      state ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:formatter_event, _msg}, _from, state) do
    {:reply, :ok, state}
  end

  defp patch_assertion(%{patch_state: patch_state} = state, {assertion, from}) do
    {_type, _value, context} = assertion
    state = %{state | current: context}
    patch_state = Patcher.load_file!(patch_state, context)
    test_line = Patcher.get_test_line!(patch_state, assertion)

    case state.active_tags[context.file] do
      %{line: ^test_line} = tags ->
        patch = Patcher.patch_assertion(patch_state, assertion, tags)

        {reply, state} =
          case Patcher.accept_patch?(patch_state, patch, tags) do
            {true, patch_state} ->
              {{:ok, patch.expr}, %{state | patch_state: Patcher.accept(patch_state, patch)}}

            {false, patch_state} ->
              {:error, %{state | patch_state: Patcher.reject(patch_state, patch)}}
          end

        GenServer.reply(from, reply)
        state

      _ ->
        %{state | waiting: %{file: context.file, line: test_line, arg: {assertion, from}}}
    end
  end

  defp flush_io(%{io_pid: io_pid} = state) do
    output = StringIO.flush(io_pid)
    if output != "", do: IO.write(output)
    state
  end
end
