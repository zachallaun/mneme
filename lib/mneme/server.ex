defmodule Mneme.Server do
  @moduledoc false

  # Mneme.Server is an ExUnit.Formatter that replaces (and delegates to)
  # the default formatter so that it can capture and control terminal IO
  # and hook into test events.

  use GenServer

  alias Mneme.Options
  alias Mneme.Patcher

  defstruct [
    :patch_state,
    :io_pid,
    :current,
    :waiting,
    current_opts: %{},
    queue: []
  ]

  @type t :: %__MODULE__{
          patch_state: any(),
          io_pid: pid(),
          current: %{module: module(), file: binary()},
          waiting: %{file: binary(), line: non_neg_integer(), arg: assertion_arg},
          current_opts: %{binary() => %{file: binary(), line: non_neg_integer(), opts: map()}},
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
    %{module: module, name: test_name, tags: %{file: file} = tags} = test

    current_opts_for_file = %{
      module: test.module,
      test: test_name,
      file: file,
      opts: Options.options(tags)
    }

    state = Map.update!(state, :current_opts, &Map.put(&1, file, current_opts_for_file))

    case state do
      %{waiting: %{file: ^file, module: ^module, test: ^test_name, arg: arg}} = state ->
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
    %{module: module, file: file, test: test} = context
    state = %{state | current: context}

    patch_state = Patcher.load_file!(patch_state, context)

    case state.current_opts[context.file] do
      %{module: ^module, file: ^file, test: ^test, opts: opts} ->
        {reply, patch_state} = Patcher.patch!(patch_state, assertion, opts)

        GenServer.reply(from, reply)
        %{state | patch_state: patch_state}

      _ ->
        state
        |> Map.put(:waiting, %{
          file: context.file,
          module: module,
          test: test,
          arg: {assertion, from}
        })
    end
  end

  defp flush_io(%{io_pid: io_pid} = state) do
    output = StringIO.flush(io_pid)
    if output != "", do: IO.write(output)
    state
  end
end
