defmodule Mneme.Server do
  @moduledoc false
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def after_suite(_results) do
    GenServer.call(__MODULE__, :after_suite)
  end

  def new_assertion(value, expr, location) do
    GenServer.cast(__MODULE__, {:new_assertion, {value, expr, location}})
  end

  @impl true
  def init(_arg) do
    ExUnit.after_suite(&__MODULE__.after_suite/1)
    {:ok, []}
  end

  @impl true
  def handle_call(:after_suite, _from, state) do
    IO.inspect(state, prefix: "assertions")
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:new_assertion, assertion}, state) do
    {:noreply, [assertion | state]}
  end
end
