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

  def await_assertion(type, expr, actual, location) do
    GenServer.call(__MODULE__, {:assertion, {type, expr, actual, location}})
  end

  @impl true
  def init(_arg) do
    ExUnit.after_suite(&__MODULE__.after_suite/1)
    {:ok, %Patch.SuiteResult{}}
  end

  @impl true
  def handle_call({:assertion, assertion}, _from, state) do
    {:reply, :ok, Patch.handle_assertion(state, assertion)}
  end

  def handle_call(:after_suite, _from, state) do
    {:reply, :ok, Patch.apply_changes!(state)}
  end
end
