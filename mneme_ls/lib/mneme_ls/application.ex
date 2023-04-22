defmodule MnemeLS.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      GenLSP.Buffer,
      MnemeLS
    ]

    opts = [strategy: :one_for_one, name: MnemeLS.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
