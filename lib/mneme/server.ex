defmodule Mneme.Server do
  @moduledoc false

  # Other than being the interface between a test and the Patcher, the
  # server is primarily responsible for managing IO. Because tests can
  # run asynchronously, we have to carefully control output so that test
  # results are not written to the terminal while we're prompting the
  # user for input.
  #
  # To do this, we replace ExUnit's default formatter with our own (see
  # Mneme.ExUnitFormatter) that delegates to ExUnit's formatter and
  # allows us to capture the formatter output. It additionall notifies
  # this server of test events so that we can flush IO at the right time.
  #
  # Mneme options are additionally received via test tags, which we get
  # via the formatter. It's possible that an auto-assertion runs before
  # the formatter notifies us that the test has started (via a
  # :test_started event), in which case we need to delay the assertion
  # until we have the test's tags.

  use GenServer

  alias Mneme.Assertion
  alias Mneme.Options
  alias Mneme.Patcher

  defstruct [
    :patch_state,
    :io_pid,
    :current_module,
    opts: %{},
    to_register: [],
    to_patch: [],
    skipped: 0
  ]

  @type t :: %__MODULE__{
          patch_state: any(),
          io_pid: pid(),
          current_module: module(),
          opts: %{{mod :: module(), test :: atom()} => map()},
          to_register: [{any(), from :: pid()}],
          to_patch: [{any(), from :: pid()}],
          skipped: pos_integer()
        }

  @doc """
  Start a Mneme server.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new assertion.
  """
  def register_assertion(assertion) do
    GenServer.call(__MODULE__, {:register_assertion, assertion}, :infinity)
  end

  @doc """
  Await the result of an assertion patch.
  """
  def patch_assertion(assertion) do
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
  def handle_call({:register_assertion, assertion}, from, state) do
    state =
      case assertion.stage do
        :new -> Map.update!(state, :to_patch, &[{assertion, from} | &1])
        :update -> Map.update!(state, :to_register, &[{assertion, from} | &1])
      end

    {:noreply, state, {:continue, :process_next}}
  end

  def handle_call({:patch_assertion, assertion}, from, state) do
    state = Map.update!(state, :to_patch, &[{assertion, from} | &1])
    {:noreply, state, {:continue, :process_next}}
  end

  def handle_call({:capture_formatter, io_pid}, _from, state) do
    {:reply, :ok, state |> Map.put(:io_pid, io_pid)}
  end

  def handle_call({:formatter, {:test_started, test}}, _from, state) do
    %{module: module, name: test_name, tags: tags} = test
    state = put_in(state.opts[{module, test_name}], Options.options(tags))

    {:reply, :ok, state, {:continue, :process_next}}
  end

  def handle_call(
        {:formatter, {:module_finished, %{name: mod}}},
        _from,
        %{current_module: mod} = state
      ) do
    {:reply, :ok, state |> flush_io() |> Map.put(:current_module, nil),
     {:continue, :process_next}}
  end

  def handle_call({:formatter, {:suite_finished, _}}, _from, %{skipped: skipped} = state) do
    case Patcher.finalize!(state.patch_state) do
      :ok -> :ok
      {:error, {:not_saved, files}} -> ensure_exit_with_error!(:not_saved, files)
    end

    if skipped > 0 do
      ensure_exit_with_error!(:skipped, skipped)
    end

    {:reply, :ok, flush_io(state)}
  end

  def handle_call({:formatter, _msg}, _from, %{current_module: nil} = state) do
    {:reply, :ok, flush_io(state)}
  end

  def handle_call({:formatter, _msg}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_continue(:process_next, state) do
    case pop_to_register(state) do
      {next, state} ->
        {:noreply, do_register_assertion(state, next), {:continue, :process_next}}

      nil ->
        case pop_to_patch(state) do
          {next, state} -> {:noreply, do_patch_assertion(state, next)}
          nil -> {:noreply, state}
        end
    end
  end

  defp do_patch_assertion(state, {assertion, from}) do
    %Assertion{context: %{module: module, test: test}} = assertion
    opts = state.opts[{module, test}]

    {reply, patch_state} = Patcher.patch!(state.patch_state, assertion, opts)
    GenServer.reply(from, reply)

    state =
      case reply do
        {:error, :skip} -> Map.update!(state, :skipped, &(&1 + 1))
        _ -> state
      end

    %{state | patch_state: patch_state, current_module: module}
  end

  defp do_register_assertion(state, {assertion, from}) do
    %Assertion{context: %{module: module, test: test}} = assertion
    opts = state.opts[{module, test}]

    case opts.target do
      :mneme ->
        GenServer.reply(from, {:ok, assertion})
        state

      :ex_unit ->
        %{state | to_patch: [{assertion, from} | state.to_patch]}
    end
  end

  defp flush_io(%{io_pid: io_pid} = state) do
    output = StringIO.flush(io_pid)
    if output != "", do: IO.write(output)
    state
  end

  defp pop_to_register(state), do: pop_to_register(state, [])

  defp pop_to_register(%{to_register: []}, _acc), do: nil

  defp pop_to_register(%{to_register: [next | rest]} = state, acc) do
    {%Assertion{context: %{module: module, test: test}}, _from} = next

    if state.opts[{module, test}] do
      {next, %{state | to_register: acc ++ rest}}
    else
      pop_to_register(%{state | to_register: rest}, [next | acc])
    end
  end

  defp pop_to_patch(state), do: pop_to_patch(state, [])

  defp pop_to_patch(%{to_patch: []}, _acc), do: nil

  defp pop_to_patch(%{to_patch: [next | rest]} = state, acc) do
    {%Assertion{context: %{module: module, test: test}}, _from} = next

    if current_module?(state, module) && state.opts[{module, test}] do
      {next, %{state | to_patch: acc ++ rest}}
    else
      pop_to_patch(%{state | to_patch: rest}, [next | acc])
    end
  end

  defp current_module?(%{current_module: nil}, _), do: true
  defp current_module?(%{current_module: mod}, mod), do: true
  defp current_module?(_state, _mod), do: false

  defp ensure_exit_with_error!(reason, arg)

  defp ensure_exit_with_error!(:skipped, skipped) do
    ensure_exit_with_error!(fn ->
      message = if skipped == 1, do: "1 assertion skipped", else: "#{skipped} assertions skipped"

      IO.puts(["\n", IO.ANSI.format([:red, "[Mneme] ", message])])
    end)
  end

  defp ensure_exit_with_error!(:not_saved, files) do
    ensure_exit_with_error!(fn ->
      message = [
        "Could not save the following files (possibly because their content changed):\n\n",
        Enum.map(files, &["  * ", &1, "\n"])
      ]

      IO.puts(["\n", IO.ANSI.format([:red, "[Mneme] ", message])])
    end)
  end

  defp ensure_exit_with_error!(fun) when is_function(fun, 0) do
    System.at_exit(fn _ ->
      fun.()

      exit_status =
        ExUnit.configuration()
        |> Keyword.fetch!(:exit_status)

      exit({:shutdown, exit_status})
    end)
  end
end
