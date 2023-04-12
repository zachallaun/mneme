defmodule Mneme.Prompter do
  @moduledoc false

  # This module defines a behaviour and utilities for prompting a user
  # when an assertion should be updated.

  @type response :: :accept | :reject | :skip | :prev | :next
  @type diff :: %{left: String.t(), right: String.t()}
  @type options :: map()

  @callback prompt!(Mneme.Assertion.t(), counter :: non_neg_integer(), diff, options) :: response
end
