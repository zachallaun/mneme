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

defmodule Mneme.UnboundVariableError do
  @moduledoc false
  defexception [:vars, :result, :message]

  @impl true
  def message(%{message: nil} = exception) do
    %{vars: vars, result: result} = exception

    """
    The amended match obsoleted one or several of already bound variables
      (#{inspect(vars)}) while adjusting for the result #{inspect(result)}.

    Please run test(s) again.
    """
  end

  def message(%{message: message}) do
    message
  end
end
