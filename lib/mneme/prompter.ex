defmodule Mneme.Prompter do
  # Behaviour controlling how to prompt acceptance or rejection of an
  # assertion patch. This behaviour may become public in the future.
  @moduledoc false

  @type response :: :accept | :reject | :prev | :next
  @type prompt_state :: term()

  @callback prompt!(
              Rewrite.Source.t(),
              assertion :: term(),
              opts :: map(),
              reprompt :: nil | prompt_state
            ) :: {response, prompt_state}
end
