defmodule Mneme.Prompter do
  # Behaviour controlling how to prompt acceptance or rejection of an
  # assertion patch. This behaviour may become public in the future.
  @moduledoc false

  @type response :: :accept | :reject | :skip | :prev | :next
  @type diff :: %{left: String.t(), right: String.t()}
  @type options :: map()

  @callback prompt!(Mneme.Assertion.t(), counter :: non_neg_integer(), diff, options) :: response
end
