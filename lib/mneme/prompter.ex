defmodule Mneme.Prompter do
  # Behaviour controlling how to prompt acceptance or rejection of an
  # assertion patch. This behaviour may become public in the future.
  @moduledoc false

  @callback prompt!(Rewrite.Source.t(), assertion :: term()) :: boolean()
end
