defmodule Mneme.Server do
  @moduledoc false
  use GenServer

  alias Mneme.Code
  alias Mneme.Code.AssertionResult

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def after_suite(_results) do
    GenServer.call(__MODULE__, :after_suite)
  end

  def assertion(type, expr, actual, location) do
    result = %AssertionResult{
      type: type,
      expr: expr,
      actual: actual,
      location: location
    }

    GenServer.cast(__MODULE__, {:result, result})
  end

  @impl true
  def init(_arg) do
    ExUnit.after_suite(&__MODULE__.after_suite/1)
    {:ok, []}
  end

  @impl true
  def handle_call(:after_suite, _from, results) do
    Code.handle_results(results)
    {:reply, :ok, results}
  end

  @impl true
  def handle_cast({:result, result}, results) do
    {:noreply, [result | results]}
  end
end
