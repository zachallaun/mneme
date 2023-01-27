defmodule Mneme.Server do
  @moduledoc false

  # Mneme.Server is an ExUnit.Formatter that replaces (and delegates to)
  # the default formatter so that it can capture and control terminal IO
  # and hook into test events.

  use GenServer

  alias Mneme.Patch

  defstruct [
    :patch_state,
    :io_pid,
    :formatter,
    :current,
    queue: []
  ]

  @doc """
  Start a Mneme server.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Patch a Mneme assertion, prompting the user.
  """
  def await_assertion(assertion) do
    GenServer.call(__MODULE__, {:patch_assertion, assertion}, :infinity)
  end

  @doc """
  Delegate call for ExUnit.Formatter init.
  """
  def formatter_init(opts) do
    formatter = Keyword.fetch!(opts, :default_formatter)
    {:ok, formatter_config} = formatter.init(opts)
    {:ok, io_pid} = StringIO.open("")
    Process.group_leader(self(), io_pid)

    :ok = GenServer.call(__MODULE__, {:capture_formatter, formatter, io_pid})

    {:ok, formatter_config}
  end

  @doc """
  Delegate call for ExUnit.Formatter handle_cast.
  """
  def formatter_handle_cast(message, config) do
    config = GenServer.call(__MODULE__, {:formatter_cast, message, config})
    {:noreply, config}
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{patch_state: Patch.init()}}
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

  def handle_call({:capture_formatter, formatter, io_pid}, _from, state) do
    {:reply, :ok,
     state
     |> Map.put(:formatter, formatter)
     |> Map.put(:io_pid, io_pid)}
  end

  def handle_call({:formatter_cast, {:suite_finished, _} = msg, config}, _from, state) do
    config = formatter_cast(state, msg, config)
    {:reply, config, Map.update!(state, :patch_state, &Patch.finalize!/1)}
  end

  def handle_call({:formatter_cast, {:module_finished, test_module} = msg, config}, _from, state) do
    config = formatter_cast(state, msg, config)

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

    {:reply, config, state}
  end

  def handle_call({:formatter_cast, msg, config}, _from, state) do
    config = formatter_cast(state, msg, config)
    {:reply, config, state}
  end

  defp patch_assertion(%{patch_state: patch_state} = state, {assertion, from}) do
    {_type, _value, context} = assertion
    patch_state = Patch.load_file!(patch_state, context)
    {patch, patch_state} = Patch.patch_assertion(patch_state, assertion)

    {reply, state} =
      case Patch.accept_patch?(patch_state, patch) do
        {true, patch_state} ->
          {{:ok, patch.expr}, %{state | patch_state: Patch.accept(patch_state, patch)}}

        {false, patch_state} ->
          {:error, %{state | patch_state: Patch.reject(patch_state, patch)}}
      end

    GenServer.reply(from, reply)
    %{state | current: context}
  end

  defp formatter_cast(%{formatter: formatter}, message, config) do
    {:noreply, config} = formatter.handle_cast(message, config)
    config
  end

  defp flush_io(%{io_pid: io_pid} = state) do
    output = StringIO.flush(io_pid)
    if output != "", do: IO.write(output)
    state
  end
end
