defmodule Mneme.AssertionError do
  @moduledoc "Raised when Mneme fails to generate an assertion."
  defexception [:message]
end

defmodule Mneme.CompileError do
  @moduledoc "Raised at compile-time when Mneme is used in an incorrect environment."
  defexception [:message]
end
