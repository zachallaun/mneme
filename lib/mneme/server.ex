defmodule Mneme.Server do
  @moduledoc false

  # In order to control IO and make sure that async tests don't cause
  # screwiness, the server will handle all await_assertion calls from a
  # single module, only moving on to calls from other modules once a
  # :module_finished event is received (via a captured ExUnit formatter).
  #
  # We also configure Mneme using ExUnit attributes that are received
  # in the test tags with the :test_started message. In the event that
  # we receive an await_assertion prior to the :test_started (which is
  # possible becuase it's async), we delay until the test has started
  # and we have the appropriate options.

  use GenServer

  alias Mneme.Options
  alias Mneme.Patcher

  defstruct [
    :patch_state,
    :io_pid,
    :current_module,
    opts: %{},
    assertions: []
  ]

  @type t :: %__MODULE__{
          patch_state: any(),
          io_pid: pid(),
          current_module: module(),
          opts: %{{mod :: module(), test :: atom()} => map()},
          assertions: [assertion_arg]
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
    GenServer.call(__MODULE__, {:formatter, message}, :infinity)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{patch_state: Patcher.init()}}
  end

  @impl true
  def handle_call({:patch_assertion, assertion}, from, state) do
    state = Map.update!(state, :assertions, &(&1 ++ [{assertion, from}]))
    {:noreply, state, {:continue, :process_assertions}}
  end

  def handle_call({:capture_formatter, io_pid}, _from, state) do
    {:reply, :ok, state |> Map.put(:io_pid, io_pid)}
  end

  def handle_call({:formatter, {:test_started, test}}, _from, state) do
    %{module: module, name: test_name, tags: tags} = test
    state = put_in(state.opts[{module, test_name}], Options.options(tags))

    {:reply, :ok, state, {:continue, :process_assertions}}
  end

  def handle_call({:formatter, {:test_finished, _}}, _from, %{current_module: nil} = state) do
    {:reply, :ok, flush_io(state)}
  end

  def handle_call({:formatter, {:module_finished, test_module}}, _from, state) do
    state =
      if state.current_module in [nil, test_module.name] do
        flush_io(state)
        %{state | current_module: nil}
      else
        state
      end

    {:reply, :ok, state, {:continue, :process_assertions}}
  end

  def handle_call({:formatter, {:suite_finished, _}}, _from, state) do
    flush_io(state)
    {:reply, :ok, Map.update!(state, :patch_state, &Patcher.finalize!/1)}
  end

  def handle_call({:formatter, _msg}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_continue(:process_assertions, state) do
    case pop_assertion(state) do
      {next, state} -> {:noreply, patch_assertion(state, next)}
      nil -> {:noreply, state}
    end
  end

  defp patch_assertion(state, {assertion, from}) do
    {_type, _value, context} = assertion
    %{module: module, test: test} = context
    opts = state.opts[{module, test}]

    state =
      state
      |> Map.put(:current_module, module)
      |> Map.put(:patch_state, Patcher.load_file!(state.patch_state, context))

    {reply, patch_state} = Patcher.patch!(state.patch_state, assertion, opts)

    GenServer.reply(from, reply)

    %{state | patch_state: patch_state}
  end

  defp flush_io(%{io_pid: io_pid} = state) do
    output = StringIO.flush(io_pid)
    if output != "", do: IO.write(output)
    state
  end

  defp pop_assertion(state), do: pop_assertion(state, [])

  defp pop_assertion(%{assertions: []}, _acc), do: nil

  defp pop_assertion(%{assertions: [next | rest]} = state, acc) do
    {{_type, _value, context}, _from} = next
    %{module: module, test: test} = context

    if state.current_module in [nil, module] && state.opts[{module, test}] do
      {next, %{state | assertions: Enum.reverse(acc) ++ rest}}
    else
      pop_assertion(%{state | assertions: rest}, [next | acc])
    end
  end
end
