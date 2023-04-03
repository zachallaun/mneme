defmodule Mneme.Server.ExUnitFormatter do
  @moduledoc false

  use GenServer

  @impl true
  def init(opts) do
    formatter = Keyword.fetch!(opts, :default_formatter)
    {:ok, config} = formatter.init(opts)
    Mneme.Server.on_formatter_init()
    {:ok, {formatter, config}}
  end

  @impl true
  def handle_cast(message, {formatter, config}) do
    {:noreply, config} = formatter.handle_cast(message, config)
    Mneme.Server.on_formatter_event(message)
    {:noreply, {formatter, config}}
  end
end
