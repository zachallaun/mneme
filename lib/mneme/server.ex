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
  alias Mneme.Patcher

  defstruct [
    :patch_state,
    :patching,
    :io_pid,
    :current_module,
    to_patch: [],
    stats: %{
      counter: 0,
      new: 0,
      updated: 0,
      skipped: 0,
      rejected: 0
    },
    not_saved: MapSet.new()
  ]

  @type t :: %__MODULE__{
          patch_state: any(),
          patching: {Task.t(), Assertion.t(), GenServer.from()},
          io_pid: pid(),
          current_module: module(),
          to_patch: [{Assertion.t(), GenServer.from()}],
          stats: %{
            counter: non_neg_integer(),
            new: non_neg_integer(),
            updated: non_neg_integer(),
            skipped: non_neg_integer(),
            rejected: non_neg_integer()
          }
        }

  @doc """
  Returns `true` if the server has started.
  """
  def started?, do: !!GenServer.whereis(__MODULE__)

  @doc """
  Start a Mneme server.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new assertion.

  This will not return until the test has been reported as started.
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

  @doc """
  Cancels any in-process patching and skips all remaining assertions.
  """
  def skip_all do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      server -> GenServer.call(server, :skip_all, :infinity)
    end
  end

  @doc false
  def on_formatter_init do
    {:ok, io_pid} = StringIO.open("")
    Process.group_leader(self(), io_pid)
    GenServer.call(__MODULE__, {:capture_formatter, io_pid}, :infinity)
  end

  @doc false
  def on_formatter_event(message) do
    GenServer.call(__MODULE__, {:formatter, message}, :infinity)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{patch_state: Patcher.init()}}
  end

  @impl true
  def handle_call({:register_assertion, %Assertion{} = assertion}, from, state) do
    case do_register_assertion(assertion, from, state) do
      {:run_now, state} -> {:reply, {:ok, assertion}, state, {:continue, :process_next}}
      {:await_patch, state} -> {:noreply, state, {:continue, :process_next}}
    end
  end

  def handle_call({:patch_assertion, assertion}, from, state) do
    state = update_in(state.to_patch, &[{assertion, from} | &1])
    {:noreply, state, {:continue, :process_next}}
  end

  def handle_call({:capture_formatter, io_pid}, _from, state) do
    {:reply, :ok, Map.put(state, :io_pid, io_pid)}
  end

  def handle_call({:formatter, {:test_started, _test}}, _from, state) do
    {:reply, :ok, state, {:continue, :process_next}}
  end

  def handle_call({:formatter, {:module_finished, %{name: mod}}}, _from, state) do
    if state.current_module == mod do
      state =
        state
        |> Map.put(:current_module, nil)
        |> flush_io()

      {:reply, :ok, state, {:continue, :process_next}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:formatter, {:suite_finished, _}}, _from, state) do
    {:reply, :ok, state |> finalize() |> flush_io()}
  end

  def handle_call({:formatter, _msg}, _from, %{current_module: nil} = state) do
    {:reply, :ok, flush_io(state)}
  end

  def handle_call({:formatter, _msg}, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:skip_all, _from, %{patching: :skip} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:skip_all, _from, state) do
    state =
      case state do
        %{patching: {%Task{} = task, assertion, from}} ->
          Task.shutdown(task, :brutal_kill)

          # HACK: Assume we were prompting, which means we need to move
          # the cursor down a couple of lines.
          IO.write("\n\n")

          %{state | to_patch: [{assertion, from} | state.to_patch]}

        _ ->
          state
      end

    {:reply, :ok, %{state | patching: :skip}, {:continue, :process_next}}
  end

  @impl true
  def handle_continue(:process_next, %{patching: :skip} = state) do
    case pop_to_patch(state) do
      {{_assertion, from}, state} ->
        state =
          state
          |> inc_stat(:counter)
          |> inc_stat(:skipped)

        GenServer.reply(from, {:error, :skipped})

        {:noreply, state, {:continue, :process_next}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_continue(:process_next, %{patching: nil} = state) do
    case pop_to_patch(state) do
      {next, state} -> {:noreply, schedule_patch(state, next)}
      nil -> {:noreply, state}
    end
  end

  def handle_continue(:process_next, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, patch_result}, %{patching: {%Task{ref: ref}, _, _}} = state) do
    {:noreply, complete_patch(state, patch_result), {:continue, :process_next}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp do_register_assertion(%Assertion{stage: :new} = assertion, from, state) do
    state = update_in(state.to_patch, &[{assertion, from} | &1])
    {:await_patch, state}
  end

  defp do_register_assertion(%Assertion{stage: :update} = assertion, from, state) do
    %{options: opts} = assertion

    if opts.force_update || opts.target == :ex_unit do
      state = update_in(state.to_patch, &[{assertion, from} | &1])
      {:await_patch, state}
    else
      {:run_now, state}
    end
  end

  defp schedule_patch(state, {assertion, from}) do
    %{patch_state: patch_state} = state

    state = inc_stat(state, :counter)
    counter = state.stats.counter

    task =
      Task.async(fn ->
        Patcher.patch!(patch_state, assertion, counter)
      end)

    %{state | patching: {task, assertion, from}, current_module: assertion.context.module}
  end

  defp complete_patch(state, {reply, patch_state}) do
    %{patching: {_task, assertion, from}} = state

    GenServer.reply(from, reply)

    state =
      case {reply, assertion.stage} do
        {{:ok, _}, :new} ->
          inc_stat(state, :new)

        {{:ok, _}, :update} ->
          inc_stat(state, :updated)

        {{:error, :skipped}, _} ->
          inc_stat(state, :skipped)

        {{:error, :rejected}, _} ->
          inc_stat(state, :rejected)

        {{:error, :file_changed}, _} ->
          state
          |> inc_stat(:skipped)
          |> update_in([Access.key(:not_saved)], &MapSet.put(&1, assertion.context.file))

        _ ->
          state
      end

    state
    |> Map.put(:patch_state, patch_state)
    |> Map.put(:patching, nil)
  end

  defp flush_io(%{io_pid: io_pid} = state) when is_pid(io_pid) do
    output = StringIO.flush(io_pid)
    if output != "", do: IO.write(output)
    state
  end

  defp flush_io(state), do: state

  defp pop_to_patch(state), do: pop_to_patch(state, [])

  defp pop_to_patch(%{to_patch: []}, _acc), do: nil

  defp pop_to_patch(%{to_patch: [next | rest]} = state, acc) do
    {%Assertion{context: %{module: module}}, _from} = next

    if current_module?(state, module) do
      {next, %{state | to_patch: acc ++ rest}}
    else
      pop_to_patch(%{state | to_patch: rest}, [next | acc])
    end
  end

  defp current_module?(%{current_module: nil}, _), do: true
  defp current_module?(%{current_module: mod}, mod), do: true
  defp current_module?(_state, _mod), do: false

  defp finalize(%{stats: stats} = state) do
    not_saved_files =
      case Patcher.finalize!(state.patch_state) do
        :ok -> []
        {:error, {:not_saved, files}} -> files
      end ++ MapSet.to_list(state.not_saved)

    if not_saved_files != [] do
      ensure_exit_with_error!(:not_saved, not_saved_files)
    end

    if stats.skipped > 0 do
      ensure_exit_with_error!()
    end

    print_summary(stats)

    state
  end

  defp ensure_exit_with_error!(:not_saved, files) do
    ensure_exit_with_error!(fn ->
      message = [
        "The following files could not be saved. Their content may have changed.\n\n",
        Enum.map(files, &["  * ", &1]),
        "\n\nYou may need to run these tests again."
      ]

      Owl.IO.puts(["\n", Owl.Data.tag(["[Mneme] ", message], :red)])
    end)
  end

  defp ensure_exit_with_error!(fun \\ nil) do
    System.at_exit(fn _ ->
      fun && fun.()

      exit_status =
        Keyword.fetch!(ExUnit.configuration(), :exit_status)

      exit({:shutdown, exit_status})
    end)
  end

  defp inc_stat(state, stat) do
    Map.update!(state, :stats, fn stats ->
      Map.update!(stats, stat, &(&1 + 1))
    end)
  end

  defp print_summary(stats) do
    formatted =
      for stat <- [:new, :updated, :rejected, :skipped],
          stats[stat] != 0 do
        format_stat(stat, stats[stat])
      end

    if formatted != [] do
      Owl.IO.puts([
        "\n\n[Mneme] ",
        Enum.intersperse(formatted, ", ")
      ])
    end
  end

  defp format_stat(:new, n), do: Owl.Data.tag("#{n} new", :green)
  defp format_stat(:updated, n), do: Owl.Data.tag("#{n} updated", :green)
  defp format_stat(:rejected, n), do: Owl.Data.tag("#{n} rejected", :red)
  defp format_stat(:skipped, n), do: Owl.Data.tag("#{n} skipped", :yellow)
end
