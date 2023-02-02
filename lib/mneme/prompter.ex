defmodule Mneme.Prompter do
  @moduledoc """
  Behaviour controlling how to prompt acceptance or rejection of an assertion patch.
  """

  @callback prompt!(patch :: map()) :: boolean()
end
