defmodule Mix.Tasks.Mneme.Watch do
  @shortdoc "Re-runs tests on save, interrupting Mneme prompts"
  @moduledoc """
  TODO
  """

  use Mix.Task

  @impl Mix.Task
  defdelegate run(args), to: Mneme.Watch
end
