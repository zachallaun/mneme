defmodule Mneme.Prompter do
  # Behaviour controlling how to prompt acceptance or rejection of an
  # assertion patch. This behaviour may become public in the future.
  @moduledoc false

  @type response :: :accept | :reject | :shrink | :expand

  @callback prompt!(Rewrite.Source.t(), assertion :: term(), reprompt :: boolean()) :: response
end
