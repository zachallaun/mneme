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
    :waiting,
    :current_module,
    opts: %{},
    queue: []
  ]

  @type t :: %__MODULE__{
          patch_state: any(),
          io_pid: pid(),
          current_module: module(),
          waiting: %{module: module(), test: atom(), arg: assertion_arg},
          opts: %{{mod :: module(), test :: atom()} => map()},
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
  def handle_call({:patch_assertion, assertion}, from, %{current_module: nil} = state) do
    {:noreply, patch_assertion(state, {assertion, from})}
  end

  def handle_call({:patch_assertion, assertion}, from, state) do
    {_type, _value, context} = assertion

    case {context, state.current_module} do
      {%{module: module}, module} ->
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
      case {test_module, state.current_module} do
        {%{name: module}, module} ->
          flush_io(state)
          %{state | current_module: nil}

        _ ->
          state
      end

    state =
      case state do
        %{current_module: nil, queue: [next | rest]} ->
          state
          |> Map.put(:queue, rest)
          |> patch_assertion(next)

        _ ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call({:formatter_event, {:test_started, test}}, _from, state) do
    %{module: module, name: test_name, tags: tags} = test
    state = put_in(state.opts[{module, test_name}], Options.options(tags))

    case state do
      %{waiting: %{module: ^module, test: ^test_name, arg: arg}} = state ->
        {:reply, :ok, state |> Map.put(:waiting, nil) |> patch_assertion(arg)}

      state ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:formatter_event, _msg}, _from, state) do
    {:reply, :ok, state}
  end

  defp patch_assertion(state, {assertion, from}) do
    {_type, _value, context} = assertion
    %{module: module, test: test} = context

    state =
      state
      |> Map.put(:current_module, module)
      |> Map.put(:patch_state, Patcher.load_file!(state.patch_state, context))

    if opts = state.opts[{module, test}] do
      {reply, patch_state} = Patcher.patch!(state.patch_state, assertion, opts)

      GenServer.reply(from, reply)

      state
      |> Map.put(:patch_state, patch_state)
    else
      state
      |> Map.put(:waiting, %{
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
