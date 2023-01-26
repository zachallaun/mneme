defmodule Mneme.ExUnitFormatter do
  @moduledoc false

  use GenServer

  @impl true
  def init(opts) do
    Mneme.Server.formatter_init(opts)
  end

  @impl true
  def handle_cast(message, state) do
    Mneme.Server.formatter_handle_cast(message, state)
  end
end
