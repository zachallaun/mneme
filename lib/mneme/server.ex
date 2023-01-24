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

  @impl true
  def init(_arg) do
    ExUnit.after_suite(&__MODULE__.after_suite/1)
    {:ok, Patch.init()}
  end

  @impl true
  def handle_call({:assertion, {_type, _value, context} = assertion}, _from, state) do
    state = Patch.load_file!(state, context)
    {patch, state} = Patch.patch_assertion(state, assertion)

    case Patch.accept_patch?(state, patch) do
      {true, state} ->
        {:reply, {:ok, patch.expr}, Patch.accept(state, patch)}

      {false, state} ->
        {:reply, :error, Patch.reject(state, patch)}
    end
  end

  def handle_call(:after_suite, _from, state) do
    {:reply, :ok, Patch.finalize!(state)}
  end
end
