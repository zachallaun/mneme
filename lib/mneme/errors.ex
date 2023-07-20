defmodule Mneme.AssertionError do
  @moduledoc false
  defexception [:message]
end

defmodule Mneme.CompileError do
  @moduledoc false
  defexception [:message]
end

defmodule Mneme.InternalError do
  @moduledoc false
  defexception [:original_error, :original_stacktrace]

  @impl true
  def message(%{original_error: e, original_stacktrace: st}) do
    """
    Mneme encountered an internal error. This is likely a bug in Mneme.

    Please consider reporting this error at https://github.com/zachallaun/mneme/issues. Thanks!

    #{Exception.format(:error, e, st)}
    """
  end
end
