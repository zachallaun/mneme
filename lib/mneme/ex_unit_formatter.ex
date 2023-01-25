defmodule Mneme.ExUnitFormatter do
  @moduledoc false

  use GenServer

  @impl true
  def init(opts) do
    formatter = Keyword.fetch!(opts, :default_formatter)
    {:ok, config} = formatter.init(opts)
    :ok = Mneme.Server.capture_io()

    {:ok, {formatter, config}}
  end

  @impl true
  def handle_cast(message, {formatter, config}) do
    {:noreply, config} = formatter.handle_cast(message, config)
    Mneme.Server.flush_io()
    {:noreply, {formatter, config}}
  end
end
